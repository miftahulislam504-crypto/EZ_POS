-- EZ POS - Phase 2 - 0008: Phase 1 functions extended for serial/IMEI and batch tracking, installment sales,
-- exchange credit and installment collections. Each function below is the Phase 1 version plus the marked additions.

create or replace function public.create_customer(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; v_id uuid; v_open numeric;
begin
  v_biz := app.require_perm('customers.manage');
  if nullif(trim(coalesce(p->>'name', '')), '') is null then raise exception 'Customer name is required.'; end if;
  begin
    insert into customers(business_id, code, name, phone, alt_phone, email, present_address, permanent_address,
                          nid_number, birth_date, occupation, customer_group, notes,
                          workplace, emergency_contact_name, emergency_contact_phone)
    values (v_biz, nullif(p->>'code', ''), trim(p->>'name'), nullif(trim(coalesce(p->>'phone', '')), ''),
            nullif(p->>'alt_phone', ''), nullif(p->>'email', ''), nullif(p->>'present_address', ''),
            nullif(p->>'permanent_address', ''), nullif(p->>'nid_number', ''),
            nullif(p->>'birth_date', '')::date, nullif(p->>'occupation', ''),
            coalesce(nullif(p->>'customer_group', ''), 'regular'), nullif(p->>'notes', ''),
            nullif(p->>'workplace', ''), nullif(p->>'emergency_contact_name', ''), nullif(p->>'emergency_contact_phone', ''))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'A customer with this phone number already exists.';
  end;
  v_open := coalesce((p->>'opening_balance')::numeric, 0);
  if v_open > 0 then
    perform app.cust_ledger(v_biz, v_id, 'opening', 'Opening balance (due)', v_open, 0, 'customer', v_id, null);
  elsif v_open < 0 then
    perform app.cust_ledger(v_biz, v_id, 'opening', 'Opening balance (advance)', 0, -v_open, 'customer', v_id, null);
  end if;
  perform app.log(v_biz, 'customer.create', 'customer', v_id, jsonb_build_object('name', p->>'name'));
  return v_id;
end $$;

create or replace function public.create_sale(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; v_branch uuid; v_customer uuid; v_sale uuid; v_invoice text;
  v_settings jsonb; v_allow_neg boolean; v_allow_due boolean; v_ref uuid; v_role text;
  ex record; it record; pr record; pay record; v_unit text;
  v_qty numeric; v_price numeric; v_disc numeric; v_gross numeric; v_net1 numeric;
  v_sub1 numeric := 0; v_gross_total numeric := 0; v_item_disc numeric := 0;
  v_inv_disc numeric; v_ratio numeric := 0;
  v_line_net numeric; v_line_tax numeric; v_net_total numeric := 0; v_tax_total numeric := 0;
  v_total numeric; v_paid numeric := 0; v_due numeric; v_stock numeric; v_amt numeric;
  v_item uuid; v_inst boolean; v_xc numeric; v_xcu numeric := 0; v_used jsonb;
begin
  v_biz := app.require_perm('sales.create');
  v_role := app.current_role();
  -- Set only by create_installment_sale / create_exchange inside their own transaction.
  v_inst := coalesce(current_setting('app.installment_sale', true), '') = '1';
  v_xc := coalesce(nullif(current_setting('app.exchange_credit', true), '')::numeric, 0);
  select settings into v_settings from businesses where id = v_biz;
  v_allow_neg := coalesce((v_settings->>'allow_negative_stock')::boolean, false);
  v_allow_due := coalesce((v_settings->>'allow_due_sale')::boolean, true);

  v_ref := nullif(p->>'client_ref', '')::uuid;
  if v_ref is not null then
    select id, invoice_no, total, paid_amount, due_amount into ex
    from sales where business_id = v_biz and client_ref = v_ref;
    if found then
      return jsonb_build_object('id', ex.id, 'invoice_no', ex.invoice_no, 'total', ex.total,
                                'paid', ex.paid_amount, 'due', ex.due_amount, 'duplicate', true);
    end if;
  end if;

  if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') = 0 then
    raise exception 'Add at least one item to the cart.';
  end if;

  v_branch := app.resolve_branch(v_biz, nullif(p->>'branch_id', '')::uuid);
  v_customer := nullif(p->>'customer_id', '')::uuid;
  if v_customer is not null and not exists (select 1 from customers where id = v_customer and business_id = v_biz) then
    raise exception 'Customer not found.';
  end if;
  if v_customer is null and coalesce((v_settings->>'customer_required')::boolean, false) then
    raise exception 'Select a customer to complete this sale.';
  end if;

  v_inv_disc := greatest(coalesce((p->>'invoice_discount')::numeric, 0), 0);
  if v_inv_disc > 0 and not app.has_perm('sales.discount') then
    raise exception 'You do not have permission to give discounts.';
  end if;

  -- pass 1: validate lines and size the discount base
  for it in select e.value as j from jsonb_array_elements(p->'items') as e(value) loop
    select id, name, selling_price, wholesale_price, min_selling_price, is_active, tracking_type into pr
    from products where id = (it.j->>'product_id')::uuid and business_id = v_biz;
    if not found or not pr.is_active then raise exception 'A product in the cart is no longer available.'; end if;
    v_qty := (it.j->>'quantity')::numeric;
    v_price := coalesce((it.j->>'unit_price')::numeric, pr.selling_price);
    v_disc := greatest(coalesce((it.j->>'discount')::numeric, 0), 0);
    if v_qty is null or v_qty <= 0 then raise exception 'Invalid quantity for "%".', pr.name; end if;
    if pr.tracking_type in ('serial', 'imei') then
      if v_qty <> trunc(v_qty) or coalesce(array_length(app.serial_list(it.j->'serials'), 1), 0) <> v_qty then
        raise exception '"%" needs one serial/IMEI number for each unit sold.', pr.name;
      end if;
    end if;
    if v_price < 0 then raise exception 'Invalid price for "%".', pr.name; end if;
    if (v_disc > 0 or (v_price < pr.selling_price and v_price is distinct from pr.wholesale_price))
       and not app.has_perm('sales.discount') then
      raise exception 'You do not have permission to give discounts.';
    end if;
    v_gross := round(v_qty * v_price, 2);
    v_disc := least(v_disc, v_gross);
    if pr.min_selling_price is not null and v_role not in ('owner', 'manager')
       and round((v_gross - v_disc) / v_qty, 2) < pr.min_selling_price then
      raise exception '"%" cannot be sold below its minimum price.', pr.name;
    end if;
    v_sub1 := v_sub1 + (v_gross - v_disc);
  end loop;

  v_inv_disc := least(v_inv_disc, v_sub1);
  v_ratio := case when v_sub1 > 0 then v_inv_disc / v_sub1 else 0 end;

  v_invoice := app.doc_no(v_biz, 'invoice', 'INV');
  insert into sales(business_id, branch_id, invoice_no, customer_id, note, cashier_id, client_ref, invoice_discount, sale_type)
  values (v_biz, v_branch, v_invoice, v_customer, nullif(p->>'note', ''), auth.uid(), v_ref, v_inv_disc,
          case when v_inst then 'installment' else 'regular' end)
  returning id into v_sale;

  -- pass 2: lines, stock (ordered by product to keep lock order stable)
  for it in
    select e.value as j, e.ordinality as ord
    from jsonb_array_elements(p->'items') with ordinality as e(value, ordinality)
    order by (e.value->>'product_id')
  loop
    select * into pr from products where id = (it.j->>'product_id')::uuid;
    v_qty := (it.j->>'quantity')::numeric;
    v_price := coalesce((it.j->>'unit_price')::numeric, pr.selling_price);
    v_disc := greatest(coalesce((it.j->>'discount')::numeric, 0), 0);
    v_gross := round(v_qty * v_price, 2);
    v_disc := least(v_disc, v_gross);
    v_net1 := v_gross - v_disc;
    v_line_net := case when v_sub1 > 0 then round(v_net1 * (v_sub1 - v_inv_disc) / v_sub1, 2) else 0 end;
    v_line_tax := round(v_line_net * pr.tax_rate / 100, 2);
    select short_name into v_unit from units where id = pr.unit_id;

    insert into sale_items(business_id, sale_id, line_no, product_id, product_name, sku, unit_name, quantity,
                           unit_price, discount, tax_rate, net_amount, tax_amount, line_total, unit_cost, cost_amount)
    values (v_biz, v_sale, it.ord, pr.id, pr.name, pr.sku, v_unit, v_qty, v_price, v_disc, pr.tax_rate,
            v_line_net, v_line_tax, v_line_net + v_line_tax, pr.avg_cost, round(v_qty * pr.avg_cost, 2))
    returning id into v_item;

    if pr.track_stock then
      insert into stock_levels(business_id, branch_id, product_id) values (v_biz, v_branch, pr.id)
      on conflict (branch_id, product_id) do nothing;
      select quantity into v_stock from stock_levels where branch_id = v_branch and product_id = pr.id for update;
      if v_stock < v_qty and not v_allow_neg then
        raise exception 'Insufficient stock for "%": % available, % requested.', pr.name, v_stock, v_qty;
      end if;
      perform app.apply_stock(v_biz, v_branch, pr.id, -v_qty, 'sale', pr.avg_cost, 'sale', v_sale, v_invoice);
      if pr.tracking_type in ('serial', 'imei') then
        perform app.sell_units(v_biz, v_branch, pr.id, app.serial_list(it.j->'serials'), v_sale, v_item,
                               v_customer, v_invoice, pr.warranty_months);
      elsif pr.tracking_type in ('batch', 'expiry') then
        v_used := app.consume_batches(v_biz, v_branch, pr.id, v_qty);
        perform app.record_sale_batches(v_biz, v_item, v_used);
      end if;
    end if;

    v_gross_total := v_gross_total + v_gross;
    v_item_disc := v_item_disc + v_disc;
    v_net_total := v_net_total + v_line_net;
    v_tax_total := v_tax_total + v_line_tax;
  end loop;

  v_total := v_net_total + v_tax_total;
  if v_customer is not null then
    perform app.cust_ledger(v_biz, v_customer, 'sale', 'Sale ' || v_invoice, v_total, 0, 'sale', v_sale, v_invoice);
  end if;

  -- payments
  if jsonb_typeof(p->'payments') = 'array' then
    for pay in select e.value as j from jsonb_array_elements(p->'payments') as e(value) loop
      v_amt := round(coalesce((pay.j->>'amount')::numeric, 0), 2);
      continue when v_amt <= 0;
      perform app.check_account(v_biz, (pay.j->>'account_id')::uuid);
      insert into sale_payments(business_id, sale_id, account_id, amount, reference)
      values (v_biz, v_sale, (pay.j->>'account_id')::uuid, v_amt, nullif(pay.j->>'reference', ''));
      perform app.acct_txn(v_biz, v_branch, (pay.j->>'account_id')::uuid, 'in', v_amt, 'sale_payment', v_sale,
                           'Sale ' || v_invoice);
      if v_customer is not null then
        perform app.cust_ledger(v_biz, v_customer, 'payment', 'Payment at sale ' || v_invoice, 0, v_amt,
                                'sale', v_sale, v_invoice);
      end if;
      v_paid := v_paid + v_amt;
    end loop;
  end if;

  if v_paid > v_total + 0.005 then
    raise exception 'Payment (%) is more than the bill total (%).', v_paid, v_total;
  end if;
  -- Credit carried over from an exchange counts as paid.
  if v_xc > 0 then
    v_xcu := least(v_xc, greatest(v_total - v_paid, 0));
    v_paid := v_paid + v_xcu;
  end if;
  v_due := round(v_total - v_paid, 2);
  if v_due < 0.005 then v_due := 0; end if;
  if v_inst and v_customer is null then raise exception 'Select a customer for an installment sale.'; end if;
  if v_due > 0 and not v_inst then
    if v_customer is null then raise exception 'Select a customer to sell on credit.'; end if;
    if not v_allow_due then raise exception 'Credit sales are turned off for this business.'; end if;
    if not app.has_perm('sales.due') then raise exception 'You do not have permission to sell on credit.'; end if;
  end if;

  update sales set
    subtotal = v_gross_total, item_discount = v_item_disc, net_amount = v_net_total, tax_amount = v_tax_total,
    total = v_total, paid_amount = v_paid, due_amount = v_due, exchange_credit = v_xcu,
    payment_status = case when v_due = 0 then 'paid' when v_paid = 0 then 'due' else 'partial' end
  where id = v_sale;

  perform app.log(v_biz, 'sale.create', 'sale', v_sale,
    jsonb_build_object('invoice_no', v_invoice, 'total', v_total, 'discount', v_item_disc + v_inv_disc, 'due', v_due));

  return jsonb_build_object('id', v_sale, 'invoice_no', v_invoice, 'total', v_total, 'paid', v_paid, 'due', v_due,
                            'duplicate', false);
end $$;

create or replace function public.void_sale(p_sale uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; s record; it record; pm record;
begin
  v_biz := app.require_perm('sales.void');
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'A reason is required to void a sale.'; end if;
  select * into s from sales where id = p_sale and business_id = v_biz for update;
  if not found then raise exception 'Sale not found.'; end if;
  if s.status = 'void' then raise exception 'This sale is already void.'; end if;
  if s.returned_amount > 0 then raise exception 'A sale with returns cannot be voided.'; end if;
  if s.exchange_credit > 0 or s.exchange_of_return_id is not null then
    raise exception 'An exchange invoice cannot be voided. Create a return instead.';
  end if;
  if s.sale_type = 'installment' and exists (
      select 1 from installment_payments ip join installment_plans pl on pl.id = ip.plan_id where pl.sale_id = s.id) then
    raise exception 'Instalments have already been collected on this sale, so it cannot be voided.';
  end if;

  for it in
    select si.product_id, si.quantity, si.unit_cost, p.track_stock
    from sale_items si join products p on p.id = si.product_id where si.sale_id = s.id
  loop
    if it.track_stock then
      perform app.apply_stock(v_biz, s.branch_id, it.product_id, it.quantity, 'sale_void', it.unit_cost,
                              'sale', s.id, 'Void ' || s.invoice_no);
    end if;
  end loop;
  perform app.release_sale_units(v_biz, s.id, 'Void ' || s.invoice_no);
  for it in select id, quantity from sale_items where sale_id = s.id loop
    perform app.restore_sale_batches(it.id, it.quantity);
  end loop;

  if s.customer_id is not null then
    perform app.cust_ledger(v_biz, s.customer_id, 'void', 'Void ' || s.invoice_no, 0, s.total, 'sale', s.id, s.invoice_no);
  end if;
  for pm in select account_id, amount from sale_payments where sale_id = s.id loop
    if s.customer_id is not null then
      perform app.cust_ledger(v_biz, s.customer_id, 'void', 'Payment refunded, void ' || s.invoice_no,
                              pm.amount, 0, 'sale', s.id, s.invoice_no);
    end if;
    perform app.acct_txn(v_biz, s.branch_id, pm.account_id, 'out', pm.amount, 'sale_void', s.id, 'Void ' || s.invoice_no);
  end loop;

  if s.sale_type = 'installment' then
    update installment_plans set status = 'cancelled', cancelled_at = now(), cancel_reason = 'Sale voided: ' || trim(p_reason)
    where sale_id = s.id;
    update installment_items set status = 'cancelled'
    where plan_id in (select id from installment_plans where sale_id = s.id) and status in ('pending', 'partial');
    if s.customer_id is not null and s.finance_charge > 0 then
      perform app.cust_ledger(v_biz, s.customer_id, 'void', 'Service charge reversed, void ' || s.invoice_no,
                              0, s.finance_charge, 'sale', s.id, s.invoice_no);
    end if;
  end if;
  update sales set status = 'void', void_reason = trim(p_reason), voided_at = now(), voided_by = auth.uid(),
                   due_amount = 0
  where id = s.id;
  perform app.log(v_biz, 'sale.void', 'sale', s.id, jsonb_build_object('invoice_no', s.invoice_no, 'reason', p_reason));
end $$;

create or replace function public.create_sales_return(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; s record; si record; it record; v_ret uuid; v_no text;
  v_q numeric; v_net numeric; v_tax numeric; v_cost numeric; v_cond text; v_bucket text;
  v_total numeric := 0; v_apply numeric := 0; v_refund numeric := 0; v_mode text; v_acc uuid; v_serials text[];
begin
  v_biz := app.require_perm('returns.create');
  select * into s from sales where id = (p->>'sale_id')::uuid and business_id = v_biz for update;
  if not found then raise exception 'Sale not found.'; end if;
  if s.status <> 'completed' then raise exception 'Returns are only possible on completed sales.'; end if;
  if s.sale_type = 'installment' then
    raise exception 'Returns on installment sales are not available yet. Void the sale if no instalment was collected.';
  end if;
  if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') = 0 then
    raise exception 'Select at least one item to return.';
  end if;

  v_mode := coalesce(nullif(p->>'refund_mode', ''), 'cash');
  if v_mode not in ('cash', 'credit', 'exchange') then raise exception 'Invalid refund mode.'; end if;
  if s.customer_id is null and v_mode = 'credit' then v_mode := 'cash'; end if;

  v_no := app.doc_no(v_biz, 'sales_return', 'RET');
  v_ret := gen_random_uuid();
  insert into sales_returns(id, business_id, branch_id, return_no, sale_id, customer_id, reason, refund_mode, created_by)
  values (v_ret, v_biz, s.branch_id, v_no, s.id, s.customer_id, nullif(p->>'reason', ''), v_mode, auth.uid());

  for it in select e.value as j from jsonb_array_elements(p->'items') as e(value) loop
    select x.*, pr.track_stock as track_stock, pr.tracking_type as tracking_type into si
    from sale_items x join products pr on pr.id = x.product_id
    where x.id = (it.j->>'sale_item_id')::uuid and x.sale_id = s.id for update of x;
    if not found then raise exception 'Invoice line not found.'; end if;
    v_q := (it.j->>'quantity')::numeric;
    if v_q is null or v_q <= 0 then continue; end if;
    if v_q > si.quantity - si.returned_quantity + 0.0005 then
      raise exception 'Cannot return % of "%": only % left to return.', v_q, si.product_name, si.quantity - si.returned_quantity;
    end if;
    v_cond := coalesce(nullif(it.j->>'condition', ''), 'resellable');
    if v_cond not in ('resellable', 'damaged', 'inspection') then raise exception 'Invalid item condition.'; end if;
    v_bucket := case v_cond when 'resellable' then 'quantity' when 'damaged' then 'damaged' else 'inspection' end;
    if si.tracking_type in ('serial', 'imei') then
      v_serials := app.serial_list(it.j->'serials');
      if v_q <> trunc(v_q) or coalesce(array_length(v_serials, 1), 0) <> v_q then
        raise exception 'Select the serial/IMEI number of each returned unit of "%".', si.product_name;
      end if;
      perform app.return_units(v_biz, si.product_id, v_serials, si.id, v_cond, v_ret, v_no);
    end if;

    v_net := round(si.net_amount * v_q / si.quantity, 2);
    v_tax := round(si.tax_amount * v_q / si.quantity, 2);
    v_cost := round(si.unit_cost * v_q, 2);

    insert into sales_return_items(business_id, return_id, sale_item_id, product_id, product_name, quantity,
                                   condition, net_amount, tax_amount, line_total, cost_amount)
    values (v_biz, v_ret, si.id, si.product_id, si.product_name, v_q, v_cond, v_net, v_tax, v_net + v_tax, v_cost);
    update sale_items set returned_quantity = returned_quantity + v_q where id = si.id;

    if si.track_stock then
      perform app.apply_stock(v_biz, s.branch_id, si.product_id, v_q, 'sales_return', si.unit_cost,
                              'sales_return', v_ret, v_no || ' (' || v_cond || ')', v_bucket);
      if v_cond = 'resellable' then perform app.restore_sale_batches(si.id, v_q); end if;
    end if;
    v_total := v_total + v_net + v_tax;
  end loop;

  if v_total <= 0 then raise exception 'Select at least one item to return.'; end if;

  if s.customer_id is not null then v_apply := least(s.due_amount, v_total); end if;
  v_refund := case when v_mode = 'cash' then v_total - v_apply else 0 end;
  if v_refund > 0 then
    v_acc := nullif(p->>'refund_account_id', '')::uuid;
    perform app.check_account(v_biz, v_acc);
  end if;

  if s.customer_id is not null then
    perform app.cust_ledger(v_biz, s.customer_id, 'return', 'Return ' || v_no || ' on ' || s.invoice_no,
                            0, v_total, 'sales_return', v_ret, v_no);
    if v_refund > 0 then
      perform app.cust_ledger(v_biz, s.customer_id, 'refund', 'Refund for ' || v_no, v_refund, 0,
                              'sales_return', v_ret, v_no);
    end if;
  end if;
  if v_refund > 0 then
    perform app.acct_txn(v_biz, s.branch_id, v_acc, 'out', v_refund, 'sales_return_refund', v_ret, 'Refund ' || v_no);
  end if;

  update sales_returns set total = v_total, due_adjusted = v_apply, refund_amount = v_refund,
                           refund_account_id = case when v_refund > 0 then v_acc end
  where id = v_ret;
  update sales set returned_amount = returned_amount + v_total,
                   due_amount = due_amount - v_apply,
                   payment_status = case when due_amount - v_apply <= 0.004 then 'paid'
                                         when paid_amount > 0 then 'partial' else 'due' end
  where id = s.id;

  perform app.log(v_biz, 'sale.return', 'sales_return', v_ret,
                  jsonb_build_object('return_no', v_no, 'invoice_no', s.invoice_no, 'total', v_total, 'refund', v_refund));
  return jsonb_build_object('id', v_ret, 'return_no', v_no, 'total', v_total, 'due_adjusted', v_apply, 'refund', v_refund);
end $$;

-- Installment sales are collected through collect_installment, never by oldest-first allocation.
create or replace function public.record_customer_payment(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; v_cust uuid; v_amount numeric; v_acc uuid; v_id uuid; v_no text; v_ref uuid; v_branch uuid;
  ex record; s record; a record;
  v_remaining numeric; v_alloc numeric; v_allocated numeric := 0; v_date timestamptz;
begin
  v_biz := app.require_perm('customers.payment');
  v_ref := nullif(p->>'client_ref', '')::uuid;
  if v_ref is not null then
    select id, receipt_no, amount into ex from customer_payments where business_id = v_biz and client_ref = v_ref;
    if found then
      return jsonb_build_object('id', ex.id, 'receipt_no', ex.receipt_no, 'amount', ex.amount, 'duplicate', true);
    end if;
  end if;
  v_cust := (p->>'customer_id')::uuid;
  if not exists (select 1 from customers where id = v_cust and business_id = v_biz) then
    raise exception 'Customer not found.';
  end if;
  v_amount := round(coalesce((p->>'amount')::numeric, 0), 2);
  if v_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;
  v_acc := (p->>'account_id')::uuid;
  perform app.check_account(v_biz, v_acc);
  v_branch := app.resolve_branch(v_biz, null);
  v_date := coalesce(nullif(p->>'payment_date', '')::timestamptz, clock_timestamp());
  v_no := app.doc_no(v_biz, 'customer_payment', 'RCV');

  insert into customer_payments(business_id, branch_id, customer_id, receipt_no, amount, account_id, payment_date,
                                reference, note, client_ref, created_by)
  values (v_biz, v_branch, v_cust, v_no, v_amount, v_acc, v_date, nullif(p->>'reference', ''),
          nullif(p->>'note', ''), v_ref, auth.uid())
  returning id into v_id;

  if jsonb_typeof(p->'allocations') = 'array' and jsonb_array_length(p->'allocations') > 0 then
    for a in select e.value as j from jsonb_array_elements(p->'allocations') as e(value) loop
      v_alloc := round(coalesce((a.j->>'amount')::numeric, 0), 2);
      continue when v_alloc <= 0;
      select id, due_amount into s from sales
      where id = (a.j->>'sale_id')::uuid and business_id = v_biz and customer_id = v_cust
        and status = 'completed' and sale_type = 'regular' for update;
      if not found then raise exception 'Invoice not found for this customer.'; end if;
      if v_alloc > s.due_amount + 0.004 then raise exception 'Allocation is more than the invoice due.'; end if;
      v_allocated := v_allocated + v_alloc;
      if v_allocated > v_amount + 0.004 then raise exception 'Allocations are more than the amount received.'; end if;
      insert into customer_payment_allocations(business_id, payment_id, sale_id, amount) values (v_biz, v_id, s.id, v_alloc);
      update sales set paid_amount = paid_amount + v_alloc, due_amount = due_amount - v_alloc,
                       payment_status = case when due_amount - v_alloc <= 0.004 then 'paid' else 'partial' end
      where id = s.id;
    end loop;
  else
    v_remaining := v_amount;
    for s in
      select id, due_amount from sales
      where business_id = v_biz and customer_id = v_cust and status = 'completed' and sale_type = 'regular' and due_amount > 0
      order by sale_date, created_at for update
    loop
      exit when v_remaining <= 0;
      v_alloc := least(s.due_amount, v_remaining);
      insert into customer_payment_allocations(business_id, payment_id, sale_id, amount) values (v_biz, v_id, s.id, v_alloc);
      update sales set paid_amount = paid_amount + v_alloc, due_amount = due_amount - v_alloc,
                       payment_status = case when due_amount - v_alloc <= 0.004 then 'paid' else 'partial' end
      where id = s.id;
      v_remaining := v_remaining - v_alloc;
      v_allocated := v_allocated + v_alloc;
    end loop;
  end if;

  perform app.cust_ledger(v_biz, v_cust, 'payment', 'Payment received ' || v_no, 0, v_amount, 'customer_payment', v_id, v_no, v_date);
  perform app.acct_txn(v_biz, v_branch, v_acc, 'in', v_amount, 'customer_payment', v_id, 'Receipt ' || v_no, v_date);
  perform app.log(v_biz, 'customer.payment', 'customer_payment', v_id,
                  jsonb_build_object('receipt_no', v_no, 'amount', v_amount, 'customer_id', v_cust));
  return jsonb_build_object('id', v_id, 'receipt_no', v_no, 'amount', v_amount, 'allocated', v_allocated,
                            'unallocated', v_amount - v_allocated, 'duplicate', false);
end $$;

create or replace function public.create_purchase(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; v_branch uuid; v_supplier uuid; v_id uuid; v_no text; v_ref uuid; v_date date;
  ex record; it record; pr record; pay record;
  v_qty numeric; v_cost numeric; v_disc numeric; v_line numeric; v_sub numeric := 0;
  v_hdr_disc numeric; v_tax numeric; v_other numeric; v_adj numeric; v_total numeric;
  v_landed_line numeric; v_landed_unit numeric; v_cur_qty numeric; v_new_avg numeric;
  v_paid numeric := 0; v_due numeric; v_amt numeric;
  v_pi uuid; v_serials text[]; v_bno text; v_exp date;
begin
  v_biz := app.require_perm('purchases.create');
  v_ref := nullif(p->>'client_ref', '')::uuid;
  if v_ref is not null then
    select id, purchase_no, total, paid_amount, due_amount into ex from purchases where business_id = v_biz and client_ref = v_ref;
    if found then
      return jsonb_build_object('id', ex.id, 'purchase_no', ex.purchase_no, 'total', ex.total,
                                'paid', ex.paid_amount, 'due', ex.due_amount, 'duplicate', true);
    end if;
  end if;
  v_supplier := (p->>'supplier_id')::uuid;
  if not exists (select 1 from suppliers where id = v_supplier and business_id = v_biz) then
    raise exception 'Select a supplier for this purchase.';
  end if;
  if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') = 0 then
    raise exception 'Add at least one product to this purchase.';
  end if;
  v_branch := app.resolve_branch(v_biz, nullif(p->>'branch_id', '')::uuid);
  v_date := coalesce(nullif(p->>'purchase_date', '')::date, (now() at time zone app.tz(v_biz))::date);
  v_hdr_disc := greatest(coalesce((p->>'discount')::numeric, 0), 0);
  v_tax := greatest(coalesce((p->>'tax_amount')::numeric, 0), 0);
  v_other := greatest(coalesce((p->>'other_charges')::numeric, 0), 0);

  for it in select e.value as j from jsonb_array_elements(p->'items') as e(value) loop
    v_qty := (it.j->>'quantity')::numeric; v_cost := (it.j->>'unit_cost')::numeric;
    v_disc := greatest(coalesce((it.j->>'discount')::numeric, 0), 0);
    if v_qty is null or v_qty <= 0 then raise exception 'Invalid quantity in purchase items.'; end if;
    if v_cost is null or v_cost < 0 then raise exception 'Invalid unit cost in purchase items.'; end if;
    v_sub := v_sub + greatest(round(v_qty * v_cost, 2) - v_disc, 0);
  end loop;
  if v_hdr_disc > v_sub then raise exception 'Purchase discount is more than the items total.'; end if;
  v_adj := v_tax + v_other - v_hdr_disc;
  v_total := v_sub + v_adj;

  v_no := app.doc_no(v_biz, 'purchase', 'PUR');
  insert into purchases(business_id, branch_id, purchase_no, supplier_invoice_no, supplier_id, purchase_date, status,
                        subtotal, discount, tax_amount, other_charges, total, note, attachment_url, client_ref, created_by)
  values (v_biz, v_branch, v_no, nullif(p->>'supplier_invoice_no', ''), v_supplier, v_date, 'received',
          v_sub, v_hdr_disc, v_tax, v_other, v_total, nullif(p->>'note', ''), nullif(p->>'attachment_url', ''), v_ref, auth.uid())
  returning id into v_id;

  for it in
    select e.value as j, e.ordinality as ord
    from jsonb_array_elements(p->'items') with ordinality as e(value, ordinality)
    order by (e.value->>'product_id')
  loop
    select * into pr from products where id = (it.j->>'product_id')::uuid and business_id = v_biz for update;
    if not found then raise exception 'A product in this purchase was not found.'; end if;
    v_qty := (it.j->>'quantity')::numeric; v_cost := (it.j->>'unit_cost')::numeric;
    v_disc := greatest(coalesce((it.j->>'discount')::numeric, 0), 0);
    v_line := greatest(round(v_qty * v_cost, 2) - v_disc, 0);
    v_landed_line := v_line + case when v_sub > 0 then v_adj * v_line / v_sub else 0 end;
    v_landed_unit := round(v_landed_line / v_qty, 4);
    v_serials := '{}';
    v_bno := nullif(trim(coalesce(it.j->>'batch_no', '')), '');
    v_exp := nullif(it.j->>'expiry_date', '')::date;
    if pr.tracking_type in ('serial', 'imei') then
      v_serials := app.serial_list(it.j->'serials');
      if v_qty <> trunc(v_qty) or coalesce(array_length(v_serials, 1), 0) <> v_qty then
        raise exception '"%" needs one serial/IMEI number for each unit received.', pr.name;
      end if;
    elsif pr.tracking_type = 'batch' and v_bno is null then
      raise exception '"%" needs a batch number.', pr.name;
    elsif pr.tracking_type = 'expiry' and v_exp is null then
      raise exception '"%" needs an expiry date.', pr.name;
    end if;

    insert into purchase_items(business_id, purchase_id, line_no, product_id, product_name, quantity, received_quantity,
                               unit_cost, discount, line_total, landed_unit_cost, batch_no, expiry_date)
    values (v_biz, v_id, it.ord, pr.id, pr.name, v_qty, v_qty, v_cost, v_disc, v_line, v_landed_unit, v_bno, v_exp)
    returning id into v_pi;

    if pr.track_stock then
      select coalesce(sum(greatest(quantity, 0)), 0) into v_cur_qty from stock_levels where product_id = pr.id;
      v_new_avg := case when v_cur_qty > 0
                        then round((v_cur_qty * pr.avg_cost + v_qty * v_landed_unit) / (v_cur_qty + v_qty), 4)
                        else v_landed_unit end;
      perform app.apply_stock(v_biz, v_branch, pr.id, v_qty, 'purchase', v_landed_unit, 'purchase', v_id, v_no);
      if pr.tracking_type in ('serial', 'imei') then
        perform app.add_units(v_biz, v_branch, pr.id, v_serials, pr.tracking_type, v_landed_unit, v_id, v_no);
      elsif pr.tracking_type in ('batch', 'expiry') then
        insert into stock_batches(business_id, branch_id, product_id, batch_no, expiry_date, quantity_received,
                                  quantity_left, unit_cost, purchase_id)
        values (v_biz, v_branch, pr.id, coalesce(v_bno, 'EXP-' || v_exp::text), v_exp, v_qty, v_qty, v_landed_unit, v_id);
      end if;
    else
      v_new_avg := pr.avg_cost;
    end if;
    update products set purchase_price = v_cost, avg_cost = v_new_avg where id = pr.id;
  end loop;

  perform app.supp_ledger(v_biz, v_supplier, 'purchase', 'Purchase ' || v_no, 0, v_total, 'purchase', v_id, v_no);

  if jsonb_typeof(p->'payments') = 'array' then
    for pay in select e.value as j from jsonb_array_elements(p->'payments') as e(value) loop
      v_amt := round(coalesce((pay.j->>'amount')::numeric, 0), 2);
      continue when v_amt <= 0;
      perform app.check_account(v_biz, (pay.j->>'account_id')::uuid);
      insert into purchase_payments(business_id, purchase_id, account_id, amount, reference)
      values (v_biz, v_id, (pay.j->>'account_id')::uuid, v_amt, nullif(pay.j->>'reference', ''));
      perform app.acct_txn(v_biz, v_branch, (pay.j->>'account_id')::uuid, 'out', v_amt, 'purchase_payment', v_id, 'Purchase ' || v_no);
      perform app.supp_ledger(v_biz, v_supplier, 'payment', 'Payment at purchase ' || v_no, v_amt, 0, 'purchase', v_id, v_no);
      v_paid := v_paid + v_amt;
    end loop;
  end if;
  if v_paid > v_total + 0.005 then raise exception 'Payment (%) is more than the purchase total (%).', v_paid, v_total; end if;
  v_due := round(v_total - v_paid, 2);
  if v_due < 0.005 then v_due := 0; end if;
  update purchases set paid_amount = v_paid, due_amount = v_due where id = v_id;

  perform app.log(v_biz, 'purchase.create', 'purchase', v_id, jsonb_build_object('purchase_no', v_no, 'total', v_total, 'due', v_due));
  return jsonb_build_object('id', v_id, 'purchase_no', v_no, 'total', v_total, 'paid', v_paid, 'due', v_due, 'duplicate', false);
end $$;

-- adjust_stock now also accepts serial numbers and batch details for tracked products.
drop function if exists public.adjust_stock(uuid, uuid, numeric, text, text);
create or replace function public.adjust_stock(
  p_product uuid, p_branch uuid, p_qty numeric, p_kind text, p_note text,
  p_serials text[] default null, p_batch_no text default null, p_expiry date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; v_b uuid; pr record; v_cur numeric; v_settings jsonb; v_ser text[]; v_to text; v_id uuid;
begin
  v_biz := app.require_perm('inventory.adjust');
  if p_qty is null or p_qty <= 0 then raise exception 'Enter a quantity greater than zero.'; end if;
  if p_kind not in ('opening', 'increase', 'decrease', 'damage', 'loss', 'expired') then
    raise exception 'Invalid adjustment type.';
  end if;
  if p_kind <> 'opening' and nullif(trim(coalesce(p_note, '')), '') is null then
    raise exception 'A reason is required for this adjustment.';
  end if;
  select * into pr from products where id = p_product and business_id = v_biz;
  if not found then raise exception 'Product not found.'; end if;
  if not pr.track_stock then raise exception 'This item does not track stock.'; end if;
  v_b := app.resolve_branch(v_biz, p_branch);
  select settings into v_settings from businesses where id = v_biz;

  v_ser := array(select app.norm_serial(x) from unnest(coalesce(p_serials, '{}')) as x where app.norm_serial(x) <> '');
  if pr.tracking_type in ('serial', 'imei') then
    if p_qty <> trunc(p_qty) or coalesce(array_length(v_ser, 1), 0) <> p_qty
       or (select count(distinct x) from unnest(v_ser) as x) <> coalesce(array_length(v_ser, 1), 0) then
      raise exception 'Enter one distinct serial/IMEI number for each unit.';
    end if;
  elsif p_kind in ('opening', 'increase') then
    if pr.tracking_type = 'batch' and nullif(trim(coalesce(p_batch_no, '')), '') is null then
      raise exception 'A batch number is required for this product.';
    end if;
    if pr.tracking_type = 'expiry' and p_expiry is null then
      raise exception 'An expiry date is required for this product.';
    end if;
  end if;

  insert into stock_levels(business_id, branch_id, product_id) values (v_biz, v_b, p_product)
  on conflict (branch_id, product_id) do nothing;
  select quantity into v_cur from stock_levels where branch_id = v_b and product_id = p_product for update;

  if p_kind in ('decrease', 'damage', 'loss', 'expired')
     and v_cur < p_qty and not coalesce((v_settings->>'allow_negative_stock')::boolean, false) then
    raise exception 'Only % in stock; cannot remove %.', v_cur, p_qty;
  end if;

  if p_kind in ('opening', 'increase') then
    perform app.apply_stock(v_biz, v_b, p_product, p_qty, 'adjust_' || p_kind, pr.avg_cost, 'adjustment', null, p_note);
    if pr.tracking_type in ('serial', 'imei') then
      perform app.add_units(v_biz, v_b, p_product, v_ser, pr.tracking_type, pr.avg_cost, null, p_note);
    elsif pr.tracking_type in ('batch', 'expiry') then
      insert into stock_batches(business_id, branch_id, product_id, batch_no, expiry_date, quantity_received, quantity_left, unit_cost)
      values (v_biz, v_b, p_product, coalesce(nullif(trim(p_batch_no), ''), 'EXP-' || p_expiry::text), p_expiry, p_qty, p_qty, pr.avg_cost);
    end if;
  else
    if p_kind = 'damage' then
      perform app.apply_stock(v_biz, v_b, p_product, -p_qty, 'adjust_damage', pr.avg_cost, 'adjustment', null, p_note);
      perform app.apply_stock(v_biz, v_b, p_product, p_qty, 'adjust_damage', pr.avg_cost, 'adjustment', null, p_note, 'damaged');
    else
      perform app.apply_stock(v_biz, v_b, p_product, -p_qty, 'adjust_' || p_kind, pr.avg_cost, 'adjustment', null, p_note);
    end if;
    if pr.tracking_type in ('serial', 'imei') then
      v_to := case when p_kind = 'damage' then 'damaged' else 'lost' end;
      foreach v_id in array app.take_units(v_biz, v_b, p_product, v_ser, 'in_stock') loop
        update stock_units set status = v_to, updated_at = now() where id = v_id;
        perform app.unit_event(v_biz, v_id, 'adjust_' || p_kind, 'in_stock', v_to, 'adjustment', null, p_note);
      end loop;
    elsif pr.tracking_type in ('batch', 'expiry') then
      perform app.consume_batches(v_biz, v_b, p_product, p_qty, nullif(trim(p_batch_no), ''));
    end if;
  end if;

  perform app.log(v_biz, 'stock.adjust', 'product', p_product,
                  jsonb_build_object('kind', p_kind, 'qty', p_qty, 'note', p_note, 'branch_id', v_b));
  select quantity into v_cur from stock_levels where branch_id = v_b and product_id = p_product;
  return jsonb_build_object('quantity', v_cur);
end $$;

-- Collections now include installment receipts.
create or replace function public.dashboard_summary(p_branch uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_biz uuid; v_tz text; v_today date; v_can boolean;
  v_sales numeric; v_invoices integer; v_purchases numeric; v_returns numeric; v_expenses numeric;
  v_profit numeric; v_collected numeric; v_cust_due numeric; v_supp_pay numeric; v_stock_value numeric;
  v_products integer; v_low integer; v_out integer;
begin
  v_biz := app.require_perm('dashboard.view');
  v_can := app.has_perm('reports.view');
  v_tz := app.tz(v_biz);
  v_today := (now() at time zone v_tz)::date;

  select coalesce(sum(total), 0), count(*) into v_sales, v_invoices from sales
  where business_id = v_biz and status = 'completed' and (p_branch is null or branch_id = p_branch)
    and (sale_date at time zone v_tz)::date = v_today;

  select coalesce(sum(total), 0) into v_purchases from purchases
  where business_id = v_biz and status = 'received' and (p_branch is null or branch_id = p_branch)
    and purchase_date = v_today;

  select coalesce(sum(total), 0) into v_returns from sales_returns
  where business_id = v_biz and (p_branch is null or branch_id = p_branch)
    and (return_date at time zone v_tz)::date = v_today;

  select coalesce(sum(amount), 0) into v_expenses from expenses
  where business_id = v_biz and status <> 'void' and (p_branch is null or branch_id = p_branch)
    and expense_date = v_today;

  select coalesce(sum(si.net_amount - si.cost_amount), 0) into v_profit
  from sale_items si join sales s on s.id = si.sale_id
  where s.business_id = v_biz and s.status = 'completed' and (p_branch is null or s.branch_id = p_branch)
    and (s.sale_date at time zone v_tz)::date = v_today;
  v_profit := v_profit - coalesce((
    select sum(ri.net_amount - ri.cost_amount) from sales_return_items ri join sales_returns r on r.id = ri.return_id
    where r.business_id = v_biz and (p_branch is null or r.branch_id = p_branch)
      and (r.return_date at time zone v_tz)::date = v_today), 0);

  select coalesce(sum(case when direction = 'in' then amount else -amount end), 0) into v_collected
  from account_transactions
  where business_id = v_biz and source_type in ('sale_payment', 'customer_payment', 'installment_payment', 'sale_void')
    and (p_branch is null or branch_id = p_branch) and (txn_date at time zone v_tz)::date = v_today;

  select coalesce(sum(b), 0) into v_cust_due from (
    select sum(debit - credit) as b from customer_ledger where business_id = v_biz group by customer_id) x where b > 0;
  select coalesce(sum(b), 0) into v_supp_pay from (
    select sum(credit - debit) as b from supplier_ledger where business_id = v_biz group by supplier_id) x where b > 0;

  select coalesce(sum(greatest(sl.quantity, 0) * p.avg_cost), 0) into v_stock_value
  from stock_levels sl join products p on p.id = sl.product_id
  where sl.business_id = v_biz and (p_branch is null or sl.branch_id = p_branch);

  select count(*), count(*) filter (where ts and q > 0 and low > 0 and q <= low), count(*) filter (where ts and q <= 0)
  into v_products, v_low, v_out
  from (
    select p.id, p.track_stock as ts, p.low_stock_limit as low, coalesce(sum(sl.quantity), 0) as q
    from products p left join stock_levels sl on sl.product_id = p.id and (p_branch is null or sl.branch_id = p_branch)
    where p.business_id = v_biz and p.is_active
    group by p.id
  ) x;

  return jsonb_build_object(
    'date', v_today, 'sales', v_sales, 'invoices', v_invoices, 'purchases', v_purchases, 'returns', v_returns,
    'expenses', v_expenses, 'profit', case when v_can then v_profit end, 'collected', v_collected,
    'customer_due', v_cust_due, 'supplier_payable', v_supp_pay,
    'stock_value', case when v_can then v_stock_value end,
    'products', v_products, 'low_stock', v_low, 'out_of_stock', v_out, 'can_view_profit', v_can);
end $$;

create or replace function public.report_daily_sales(p_from date, p_to date, p_branch uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_biz uuid; v_tz text; v_rows jsonb; v_methods jsonb;
begin
  v_biz := app.require_perm('reports.view');
  v_tz := app.tz(v_biz);
  if p_to - p_from > 400 then raise exception 'Date range is too long.'; end if;

  with days as (select generate_series(p_from, p_to, interval '1 day')::date as day),
  s as (
    select (sa.sale_date at time zone v_tz)::date as day, count(*) as invoices, sum(sa.subtotal) as gross,
           sum(sa.item_discount + sa.invoice_discount) as discount, sum(sa.tax_amount) as tax, sum(sa.total) as total,
           sum(greatest(sa.total - coalesce(pp.paid, 0) - sa.exchange_credit, 0)) as credit_given
    from sales sa
    left join (select sale_id, sum(amount) as paid from sale_payments group by sale_id) pp on pp.sale_id = sa.id
    where sa.business_id = v_biz and sa.status = 'completed' and (p_branch is null or sa.branch_id = p_branch)
      and (sa.sale_date at time zone v_tz)::date between p_from and p_to group by 1),
  sp as (
    select (sa.sale_date at time zone v_tz)::date as day, sum(si.net_amount) as rev, sum(si.cost_amount) as cogs
    from sale_items si join sales sa on sa.id = si.sale_id
    where sa.business_id = v_biz and sa.status = 'completed' and (p_branch is null or sa.branch_id = p_branch)
      and (sa.sale_date at time zone v_tz)::date between p_from and p_to group by 1),
  r as (
    select (rt.return_date at time zone v_tz)::date as day, sum(rt.total) as total
    from sales_returns rt where rt.business_id = v_biz and (p_branch is null or rt.branch_id = p_branch)
      and (rt.return_date at time zone v_tz)::date between p_from and p_to group by 1),
  rp as (
    select (rt.return_date at time zone v_tz)::date as day, sum(ri.net_amount) as rev, sum(ri.cost_amount) as cogs
    from sales_return_items ri join sales_returns rt on rt.id = ri.return_id
    where rt.business_id = v_biz and (p_branch is null or rt.branch_id = p_branch)
      and (rt.return_date at time zone v_tz)::date between p_from and p_to group by 1),
  c as (
    select (txn_date at time zone v_tz)::date as day,
           sum(case when direction = 'in' then amount else -amount end) as collected
    from account_transactions
    where business_id = v_biz and source_type in ('sale_payment', 'customer_payment', 'installment_payment', 'sale_void')
      and (p_branch is null or branch_id = p_branch) and (txn_date at time zone v_tz)::date between p_from and p_to
    group by 1)
  select coalesce(jsonb_agg(jsonb_build_object(
      'day', d.day, 'invoices', coalesce(s.invoices, 0), 'gross', coalesce(s.gross, 0),
      'discount', coalesce(s.discount, 0), 'tax', coalesce(s.tax, 0), 'total', coalesce(s.total, 0),
      'returns', coalesce(r.total, 0), 'net_sales', coalesce(s.total, 0) - coalesce(r.total, 0),
      'cogs', coalesce(sp.cogs, 0) - coalesce(rp.cogs, 0),
      'profit', (coalesce(sp.rev, 0) - coalesce(rp.rev, 0)) - (coalesce(sp.cogs, 0) - coalesce(rp.cogs, 0)),
      'collected', coalesce(c.collected, 0), 'credit_given', coalesce(s.credit_given, 0)) order by d.day), '[]'::jsonb)
  into v_rows
  from days d left join s on s.day = d.day left join sp on sp.day = d.day left join r on r.day = d.day
       left join rp on rp.day = d.day left join c on c.day = d.day;

  select coalesce(jsonb_agg(jsonb_build_object('name', n, 'amount', amt) order by amt desc), '[]'::jsonb) into v_methods from (
    select a.name as n, sum(case when t.direction = 'in' then t.amount else -t.amount end) as amt
    from account_transactions t join payment_accounts a on a.id = t.account_id
    where t.business_id = v_biz and (p_branch is null or t.branch_id = p_branch)
      and t.source_type in ('sale_payment', 'customer_payment', 'installment_payment', 'sale_void', 'sales_return_refund')
      and (t.txn_date at time zone v_tz)::date between p_from and p_to
    group by a.name having sum(case when t.direction = 'in' then t.amount else -t.amount end) <> 0) m;

  return jsonb_build_object('rows', v_rows, 'methods', v_methods);
end $$;
