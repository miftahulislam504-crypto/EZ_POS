-- EZ POS - Phase 1 - 0003: business setup and transactional RPCs
-- All financial writes happen here, atomically, with permission checks and audit entries.

-- ---------------------------------------------------------------- permission catalogue
create or replace function app.default_permissions(p_role text) returns text[]
language sql immutable as $$
  select case p_role
    when 'manager' then array[
      'dashboard.view','sales.view','sales.create','sales.discount','sales.due','sales.void','returns.create',
      'customers.view','customers.manage','customers.payment','suppliers.view','suppliers.manage','suppliers.payment',
      'purchases.view','purchases.create','products.view','products.manage','inventory.view','inventory.adjust',
      'expenses.view','expenses.create','expenses.void','reports.view']
    when 'cashier' then array[
      'dashboard.view','sales.view','sales.create','sales.due','customers.view','customers.manage',
      'customers.payment','products.view','inventory.view']
    when 'storekeeper' then array[
      'dashboard.view','products.view','products.manage','inventory.view','inventory.adjust',
      'purchases.view','suppliers.view']
    else array[]::text[]
  end
$$;

-- ---------------------------------------------------------------- internal helpers
create or replace function app.resolve_branch(p_biz uuid, p_branch uuid) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v uuid;
begin
  v := coalesce(p_branch,
        (select branch_id from business_members where user_id = auth.uid() and business_id = p_biz),
        (select id from branches where business_id = p_biz and is_default limit 1));
  if not exists (select 1 from branches where id = v and business_id = p_biz and is_active) then
    raise exception 'Branch not found.';
  end if;
  return v;
end $$;

create or replace function app.apply_stock(
  p_biz uuid, p_branch uuid, p_product uuid, p_qty numeric, p_type text, p_cost numeric,
  p_ref_type text, p_ref_id uuid, p_note text, p_bucket text default 'quantity')
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into stock_levels(business_id, branch_id, product_id, quantity, damaged_quantity, inspection_quantity)
  values (p_biz, p_branch, p_product,
          case when p_bucket = 'quantity' then p_qty else 0 end,
          case when p_bucket = 'damaged' then p_qty else 0 end,
          case when p_bucket = 'inspection' then p_qty else 0 end)
  on conflict (branch_id, product_id) do update set
    quantity = stock_levels.quantity + excluded.quantity,
    damaged_quantity = stock_levels.damaged_quantity + excluded.damaged_quantity,
    inspection_quantity = stock_levels.inspection_quantity + excluded.inspection_quantity;

  insert into stock_movements(business_id, branch_id, product_id, movement_type, bucket, quantity, unit_cost,
                              reference_type, reference_id, note, created_by)
  values (p_biz, p_branch, p_product, p_type, p_bucket, p_qty, coalesce(p_cost, 0),
          p_ref_type, p_ref_id, p_note, auth.uid());
end $$;

create or replace function app.cust_ledger(
  p_biz uuid, p_customer uuid, p_type text, p_desc text, p_debit numeric, p_credit numeric,
  p_ref_type text, p_ref_id uuid, p_ref_no text, p_date timestamptz default null)
returns void language sql security definer set search_path = public as $$
  insert into customer_ledger(business_id, customer_id, entry_date, entry_type, description, debit, credit,
                              reference_type, reference_id, reference_no, created_by, created_at)
  values (p_biz, p_customer, coalesce(p_date, clock_timestamp()), p_type, p_desc,
          coalesce(p_debit, 0), coalesce(p_credit, 0), p_ref_type, p_ref_id, p_ref_no, auth.uid(), clock_timestamp())
$$;

create or replace function app.supp_ledger(
  p_biz uuid, p_supplier uuid, p_type text, p_desc text, p_debit numeric, p_credit numeric,
  p_ref_type text, p_ref_id uuid, p_ref_no text, p_date timestamptz default null)
returns void language sql security definer set search_path = public as $$
  insert into supplier_ledger(business_id, supplier_id, entry_date, entry_type, description, debit, credit,
                              reference_type, reference_id, reference_no, created_by, created_at)
  values (p_biz, p_supplier, coalesce(p_date, clock_timestamp()), p_type, p_desc,
          coalesce(p_debit, 0), coalesce(p_credit, 0), p_ref_type, p_ref_id, p_ref_no, auth.uid(), clock_timestamp())
$$;

create or replace function app.acct_txn(
  p_biz uuid, p_branch uuid, p_account uuid, p_dir text, p_amount numeric,
  p_source text, p_source_id uuid, p_desc text, p_date timestamptz default null)
returns void language sql security definer set search_path = public as $$
  insert into account_transactions(business_id, branch_id, account_id, txn_date, direction, amount,
                                   source_type, source_id, description, created_by)
  values (p_biz, p_branch, p_account, coalesce(p_date, clock_timestamp()), p_dir, p_amount,
          p_source, p_source_id, p_desc, auth.uid())
$$;

create or replace function app.check_account(p_biz uuid, p_account uuid) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if p_account is null or not exists (
    select 1 from payment_accounts where id = p_account and business_id = p_biz and is_active) then
    raise exception 'Payment method not found.';
  end if;
end $$;

-- ---------------------------------------------------------------- business setup
create or replace function public.create_business(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_biz uuid; v_branch uuid; v_name text; v_email text; v_role text; v_perm text;
begin
  if v_uid is null then raise exception 'Please sign in first.'; end if;
  if exists (select 1 from business_members where user_id = v_uid) then
    raise exception 'This account already belongs to a business.';
  end if;
  v_name := nullif(trim(coalesce(p->>'name', '')), '');
  if v_name is null then raise exception 'Business name is required.'; end if;
  select email into v_email from auth.users where id = v_uid;

  insert into businesses(name, phone, address, email, created_by, settings)
  values (v_name, nullif(p->>'phone', ''), nullif(p->>'address', ''),
          coalesce(nullif(p->>'email', ''), v_email), v_uid,
          jsonb_build_object(
            'invoice_prefix', 'INV', 'purchase_prefix', 'PUR', 'sales_return_prefix', 'RET',
            'customer_payment_prefix', 'RCV', 'supplier_payment_prefix', 'PAY',
            'allow_negative_stock', false, 'allow_due_sale', true, 'customer_required', false,
            'default_tax_rate', 0, 'paper_size', '80mm', 'auto_print', false,
            'invoice_footer', 'Thank you for shopping with us.', 'invoice_terms', ''))
  returning id into v_biz;

  insert into branches(business_id, name, address, phone, is_default)
  values (v_biz, 'Main Branch', nullif(p->>'address', ''), nullif(p->>'phone', ''), true)
  returning id into v_branch;

  insert into business_members(business_id, user_id, full_name, phone, email, role, branch_id, employee_code)
  values (v_biz, v_uid, coalesce(nullif(trim(p->>'full_name'), ''), split_part(coalesce(v_email, 'Owner'), '@', 1)),
          nullif(p->>'phone', ''), v_email, 'owner', v_branch, 'E-0001');

  foreach v_role in array array['manager', 'cashier', 'storekeeper'] loop
    foreach v_perm in array app.default_permissions(v_role) loop
      insert into role_permissions(business_id, role, permission) values (v_biz, v_role, v_perm);
    end loop;
  end loop;

  insert into units(business_id, name, short_name, allow_decimal) values
    (v_biz, 'Piece', 'pcs', false), (v_biz, 'Box', 'box', false), (v_biz, 'Pack', 'pack', false),
    (v_biz, 'Dozen', 'dz', false), (v_biz, 'Set', 'set', false), (v_biz, 'Kilogram', 'kg', true),
    (v_biz, 'Gram', 'g', true), (v_biz, 'Litre', 'l', true), (v_biz, 'Millilitre', 'ml', true),
    (v_biz, 'Metre', 'm', true);

  insert into categories(business_id, name) values (v_biz, 'General');

  insert into payment_accounts(business_id, name, account_type, sort_order) values
    (v_biz, 'Cash', 'cash', 0), (v_biz, 'bKash', 'mfs', 1), (v_biz, 'Nagad', 'mfs', 2),
    (v_biz, 'Rocket', 'mfs', 3), (v_biz, 'Bank Transfer', 'bank', 4), (v_biz, 'Card', 'card', 5);

  insert into expense_categories(business_id, name) values
    (v_biz, 'Shop Rent'), (v_biz, 'Electricity Bill'), (v_biz, 'Internet Bill'), (v_biz, 'Staff Salary'),
    (v_biz, 'Transport'), (v_biz, 'Food and Refreshments'), (v_biz, 'Repair and Maintenance'),
    (v_biz, 'Marketing'), (v_biz, 'Other Expenses');

  perform app.log(v_biz, 'business.create', 'business', v_biz, jsonb_build_object('name', v_name));
  return v_biz;
end $$;

-- ---------------------------------------------------------------- customers and suppliers
create or replace function public.create_customer(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; v_id uuid; v_open numeric;
begin
  v_biz := app.require_perm('customers.manage');
  if nullif(trim(coalesce(p->>'name', '')), '') is null then raise exception 'Customer name is required.'; end if;
  begin
    insert into customers(business_id, code, name, phone, alt_phone, email, present_address, permanent_address,
                          nid_number, birth_date, occupation, customer_group, notes)
    values (v_biz, nullif(p->>'code', ''), trim(p->>'name'), nullif(trim(coalesce(p->>'phone', '')), ''),
            nullif(p->>'alt_phone', ''), nullif(p->>'email', ''), nullif(p->>'present_address', ''),
            nullif(p->>'permanent_address', ''), nullif(p->>'nid_number', ''),
            nullif(p->>'birth_date', '')::date, nullif(p->>'occupation', ''),
            coalesce(nullif(p->>'customer_group', ''), 'regular'), nullif(p->>'notes', ''))
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

create or replace function public.create_supplier(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; v_id uuid; v_open numeric;
begin
  v_biz := app.require_perm('suppliers.manage');
  if nullif(trim(coalesce(p->>'name', '')), '') is null then raise exception 'Supplier name is required.'; end if;
  insert into suppliers(business_id, code, name, contact_person, phone, alt_phone, email, address, business_type, notes)
  values (v_biz, nullif(p->>'code', ''), trim(p->>'name'), nullif(p->>'contact_person', ''),
          nullif(p->>'phone', ''), nullif(p->>'alt_phone', ''), nullif(p->>'email', ''),
          nullif(p->>'address', ''), nullif(p->>'business_type', ''), nullif(p->>'notes', ''))
  returning id into v_id;
  v_open := coalesce((p->>'opening_balance')::numeric, 0);
  if v_open > 0 then
    perform app.supp_ledger(v_biz, v_id, 'opening', 'Opening balance (payable)', 0, v_open, 'supplier', v_id, null);
  elsif v_open < 0 then
    perform app.supp_ledger(v_biz, v_id, 'opening', 'Opening balance (advance paid)', -v_open, 0, 'supplier', v_id, null);
  end if;
  perform app.log(v_biz, 'supplier.create', 'supplier', v_id, jsonb_build_object('name', p->>'name'));
  return v_id;
end $$;

-- ---------------------------------------------------------------- POS sale
-- Payload: {branch_id?, customer_id?, client_ref?, note?, invoice_discount?,
--           items:[{product_id, quantity, unit_price?, discount?}],
--           payments:[{account_id, amount, reference?}]}
-- Tax is always taken from the product. Invoice discount is spread across lines pro rata.
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
begin
  v_biz := app.require_perm('sales.create');
  v_role := app.current_role();
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
    select id, name, selling_price, wholesale_price, min_selling_price, is_active into pr
    from products where id = (it.j->>'product_id')::uuid and business_id = v_biz;
    if not found or not pr.is_active then raise exception 'A product in the cart is no longer available.'; end if;
    v_qty := (it.j->>'quantity')::numeric;
    v_price := coalesce((it.j->>'unit_price')::numeric, pr.selling_price);
    v_disc := greatest(coalesce((it.j->>'discount')::numeric, 0), 0);
    if v_qty is null or v_qty <= 0 then raise exception 'Invalid quantity for "%".', pr.name; end if;
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
  insert into sales(business_id, branch_id, invoice_no, customer_id, note, cashier_id, client_ref, invoice_discount)
  values (v_biz, v_branch, v_invoice, v_customer, nullif(p->>'note', ''), auth.uid(), v_ref, v_inv_disc)
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
            v_line_net, v_line_tax, v_line_net + v_line_tax, pr.avg_cost, round(v_qty * pr.avg_cost, 2));

    if pr.track_stock then
      insert into stock_levels(business_id, branch_id, product_id) values (v_biz, v_branch, pr.id)
      on conflict (branch_id, product_id) do nothing;
      select quantity into v_stock from stock_levels where branch_id = v_branch and product_id = pr.id for update;
      if v_stock < v_qty and not v_allow_neg then
        raise exception 'Insufficient stock for "%": % available, % requested.', pr.name, v_stock, v_qty;
      end if;
      perform app.apply_stock(v_biz, v_branch, pr.id, -v_qty, 'sale', pr.avg_cost, 'sale', v_sale, v_invoice);
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
  v_due := round(v_total - v_paid, 2);
  if v_due < 0.005 then v_due := 0; end if;
  if v_due > 0 then
    if v_customer is null then raise exception 'Select a customer to sell on credit.'; end if;
    if not v_allow_due then raise exception 'Credit sales are turned off for this business.'; end if;
    if not app.has_perm('sales.due') then raise exception 'You do not have permission to sell on credit.'; end if;
  end if;

  update sales set
    subtotal = v_gross_total, item_discount = v_item_disc, net_amount = v_net_total, tax_amount = v_tax_total,
    total = v_total, paid_amount = v_paid, due_amount = v_due,
    payment_status = case when v_due = 0 then 'paid' when v_paid = 0 then 'due' else 'partial' end
  where id = v_sale;

  perform app.log(v_biz, 'sale.create', 'sale', v_sale,
    jsonb_build_object('invoice_no', v_invoice, 'total', v_total, 'discount', v_item_disc + v_inv_disc, 'due', v_due));

  return jsonb_build_object('id', v_sale, 'invoice_no', v_invoice, 'total', v_total, 'paid', v_paid, 'due', v_due,
                            'duplicate', false);
end $$;

-- ---------------------------------------------------------------- void sale
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

  for it in
    select si.product_id, si.quantity, si.unit_cost, p.track_stock
    from sale_items si join products p on p.id = si.product_id where si.sale_id = s.id
  loop
    if it.track_stock then
      perform app.apply_stock(v_biz, s.branch_id, it.product_id, it.quantity, 'sale_void', it.unit_cost,
                              'sale', s.id, 'Void ' || s.invoice_no);
    end if;
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

  update sales set status = 'void', void_reason = trim(p_reason), voided_at = now(), voided_by = auth.uid(),
                   due_amount = 0
  where id = s.id;
  perform app.log(v_biz, 'sale.void', 'sale', s.id, jsonb_build_object('invoice_no', s.invoice_no, 'reason', p_reason));
end $$;

-- ---------------------------------------------------------------- sales return
-- Payload: {sale_id, reason?, refund_mode:'cash'|'credit', refund_account_id?,
--           items:[{sale_item_id, quantity, condition:'resellable'|'damaged'|'inspection'}]}
create or replace function public.create_sales_return(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; s record; si record; it record; v_ret uuid; v_no text;
  v_q numeric; v_net numeric; v_tax numeric; v_cost numeric; v_cond text; v_bucket text;
  v_total numeric := 0; v_apply numeric := 0; v_refund numeric := 0; v_mode text; v_acc uuid;
begin
  v_biz := app.require_perm('returns.create');
  select * into s from sales where id = (p->>'sale_id')::uuid and business_id = v_biz for update;
  if not found then raise exception 'Sale not found.'; end if;
  if s.status <> 'completed' then raise exception 'Returns are only possible on completed sales.'; end if;
  if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') = 0 then
    raise exception 'Select at least one item to return.';
  end if;

  v_mode := coalesce(nullif(p->>'refund_mode', ''), 'cash');
  if v_mode not in ('cash', 'credit') then raise exception 'Invalid refund mode.'; end if;
  if s.customer_id is null then v_mode := 'cash'; end if;

  v_no := app.doc_no(v_biz, 'sales_return', 'RET');
  v_ret := gen_random_uuid();
  insert into sales_returns(id, business_id, branch_id, return_no, sale_id, customer_id, reason, refund_mode, created_by)
  values (v_ret, v_biz, s.branch_id, v_no, s.id, s.customer_id, nullif(p->>'reason', ''), v_mode, auth.uid());

  for it in select e.value as j from jsonb_array_elements(p->'items') as e(value) loop
    select x.*, pr.track_stock as track_stock into si
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

-- ---------------------------------------------------------------- customer payment (due collection)
-- Payload: {customer_id, amount, account_id, payment_date?, reference?, note?, client_ref?,
--           allocations?:[{sale_id, amount}]}   (no allocations = oldest invoices first)
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
        and status = 'completed' for update;
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
      where business_id = v_biz and customer_id = v_cust and status = 'completed' and due_amount > 0
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

-- ---------------------------------------------------------------- purchase
-- Payload: {branch_id?, supplier_id, supplier_invoice_no?, purchase_date?, discount?, tax_amount?, other_charges?,
--           note?, attachment_url?, client_ref?, items:[{product_id, quantity, unit_cost, discount?}],
--           payments:[{account_id, amount, reference?}]}
-- Landed cost: (discount, tax, other charges) are spread over lines in proportion to line value.
create or replace function public.create_purchase(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; v_branch uuid; v_supplier uuid; v_id uuid; v_no text; v_ref uuid; v_date date;
  ex record; it record; pr record; pay record;
  v_qty numeric; v_cost numeric; v_disc numeric; v_line numeric; v_sub numeric := 0;
  v_hdr_disc numeric; v_tax numeric; v_other numeric; v_adj numeric; v_total numeric;
  v_landed_line numeric; v_landed_unit numeric; v_cur_qty numeric; v_new_avg numeric;
  v_paid numeric := 0; v_due numeric; v_amt numeric;
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

    insert into purchase_items(business_id, purchase_id, line_no, product_id, product_name, quantity, received_quantity,
                               unit_cost, discount, line_total, landed_unit_cost)
    values (v_biz, v_id, it.ord, pr.id, pr.name, v_qty, v_qty, v_cost, v_disc, v_line, v_landed_unit);

    if pr.track_stock then
      select coalesce(sum(greatest(quantity, 0)), 0) into v_cur_qty from stock_levels where product_id = pr.id;
      v_new_avg := case when v_cur_qty > 0
                        then round((v_cur_qty * pr.avg_cost + v_qty * v_landed_unit) / (v_cur_qty + v_qty), 4)
                        else v_landed_unit end;
      perform app.apply_stock(v_biz, v_branch, pr.id, v_qty, 'purchase', v_landed_unit, 'purchase', v_id, v_no);
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

-- ---------------------------------------------------------------- supplier payment
create or replace function public.record_supplier_payment(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; v_sup uuid; v_amount numeric; v_acc uuid; v_id uuid; v_no text; v_ref uuid; v_branch uuid;
  ex record; s record; a record;
  v_remaining numeric; v_alloc numeric; v_allocated numeric := 0; v_date timestamptz;
begin
  v_biz := app.require_perm('suppliers.payment');
  v_ref := nullif(p->>'client_ref', '')::uuid;
  if v_ref is not null then
    select id, payment_no, amount into ex from supplier_payments where business_id = v_biz and client_ref = v_ref;
    if found then
      return jsonb_build_object('id', ex.id, 'payment_no', ex.payment_no, 'amount', ex.amount, 'duplicate', true);
    end if;
  end if;
  v_sup := (p->>'supplier_id')::uuid;
  if not exists (select 1 from suppliers where id = v_sup and business_id = v_biz) then
    raise exception 'Supplier not found.';
  end if;
  v_amount := round(coalesce((p->>'amount')::numeric, 0), 2);
  if v_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;
  v_acc := (p->>'account_id')::uuid;
  perform app.check_account(v_biz, v_acc);
  v_branch := app.resolve_branch(v_biz, null);
  v_date := coalesce(nullif(p->>'payment_date', '')::timestamptz, clock_timestamp());
  v_no := app.doc_no(v_biz, 'supplier_payment', 'PAY');

  insert into supplier_payments(business_id, branch_id, supplier_id, payment_no, amount, account_id, payment_date,
                                reference, note, client_ref, created_by)
  values (v_biz, v_branch, v_sup, v_no, v_amount, v_acc, v_date, nullif(p->>'reference', ''),
          nullif(p->>'note', ''), v_ref, auth.uid())
  returning id into v_id;

  if jsonb_typeof(p->'allocations') = 'array' and jsonb_array_length(p->'allocations') > 0 then
    for a in select e.value as j from jsonb_array_elements(p->'allocations') as e(value) loop
      v_alloc := round(coalesce((a.j->>'amount')::numeric, 0), 2);
      continue when v_alloc <= 0;
      select id, due_amount into s from purchases
      where id = (a.j->>'purchase_id')::uuid and business_id = v_biz and supplier_id = v_sup and status = 'received' for update;
      if not found then raise exception 'Purchase not found for this supplier.'; end if;
      if v_alloc > s.due_amount + 0.004 then raise exception 'Allocation is more than the purchase due.'; end if;
      v_allocated := v_allocated + v_alloc;
      if v_allocated > v_amount + 0.004 then raise exception 'Allocations are more than the amount paid.'; end if;
      insert into supplier_payment_allocations(business_id, payment_id, purchase_id, amount) values (v_biz, v_id, s.id, v_alloc);
      update purchases set paid_amount = paid_amount + v_alloc, due_amount = due_amount - v_alloc where id = s.id;
    end loop;
  else
    v_remaining := v_amount;
    for s in
      select id, due_amount from purchases
      where business_id = v_biz and supplier_id = v_sup and status = 'received' and due_amount > 0
      order by purchase_date, created_at for update
    loop
      exit when v_remaining <= 0;
      v_alloc := least(s.due_amount, v_remaining);
      insert into supplier_payment_allocations(business_id, payment_id, purchase_id, amount) values (v_biz, v_id, s.id, v_alloc);
      update purchases set paid_amount = paid_amount + v_alloc, due_amount = due_amount - v_alloc where id = s.id;
      v_remaining := v_remaining - v_alloc;
      v_allocated := v_allocated + v_alloc;
    end loop;
  end if;

  perform app.supp_ledger(v_biz, v_sup, 'payment', 'Payment made ' || v_no, v_amount, 0, 'supplier_payment', v_id, v_no, v_date);
  perform app.acct_txn(v_biz, v_branch, v_acc, 'out', v_amount, 'supplier_payment', v_id, 'Payment ' || v_no, v_date);
  perform app.log(v_biz, 'supplier.payment', 'supplier_payment', v_id,
                  jsonb_build_object('payment_no', v_no, 'amount', v_amount, 'supplier_id', v_sup));
  return jsonb_build_object('id', v_id, 'payment_no', v_no, 'amount', v_amount, 'allocated', v_allocated,
                            'unallocated', v_amount - v_allocated, 'duplicate', false);
end $$;

-- ---------------------------------------------------------------- stock adjustment
-- p_kind: opening | increase | decrease | damage | loss | expired ; p_qty is a positive magnitude
create or replace function public.adjust_stock(p_product uuid, p_branch uuid, p_qty numeric, p_kind text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_biz uuid; v_b uuid; pr record; v_cur numeric; v_settings jsonb;
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

  insert into stock_levels(business_id, branch_id, product_id) values (v_biz, v_b, p_product)
  on conflict (branch_id, product_id) do nothing;
  select quantity into v_cur from stock_levels where branch_id = v_b and product_id = p_product for update;

  if p_kind in ('decrease', 'damage', 'loss', 'expired')
     and v_cur < p_qty and not coalesce((v_settings->>'allow_negative_stock')::boolean, false) then
    raise exception 'Only % in stock; cannot remove %.', v_cur, p_qty;
  end if;

  if p_kind in ('opening', 'increase') then
    perform app.apply_stock(v_biz, v_b, p_product, p_qty, 'adjust_' || p_kind, pr.avg_cost, 'adjustment', null, p_note);
  elsif p_kind = 'damage' then
    perform app.apply_stock(v_biz, v_b, p_product, -p_qty, 'adjust_damage', pr.avg_cost, 'adjustment', null, p_note);
    perform app.apply_stock(v_biz, v_b, p_product, p_qty, 'adjust_damage', pr.avg_cost, 'adjustment', null, p_note, 'damaged');
  else
    perform app.apply_stock(v_biz, v_b, p_product, -p_qty, 'adjust_' || p_kind, pr.avg_cost, 'adjustment', null, p_note);
  end if;

  perform app.log(v_biz, 'stock.adjust', 'product', p_product,
                  jsonb_build_object('kind', p_kind, 'qty', p_qty, 'note', p_note, 'branch_id', v_b));
  select quantity into v_cur from stock_levels where branch_id = v_b and product_id = p_product;
  return jsonb_build_object('quantity', v_cur);
end $$;

-- ---------------------------------------------------------------- expenses
create or replace function public.create_expense(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; v_id uuid; v_branch uuid; v_amount numeric; v_acc uuid; v_date date; v_title text;
begin
  v_biz := app.require_perm('expenses.create');
  v_amount := round(coalesce((p->>'amount')::numeric, 0), 2);
  if v_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;
  v_title := nullif(trim(coalesce(p->>'title', '')), '');
  if v_title is null then raise exception 'Expense name is required.'; end if;
  v_acc := (p->>'account_id')::uuid;
  perform app.check_account(v_biz, v_acc);
  if nullif(p->>'category_id', '') is not null and not exists (
      select 1 from expense_categories where id = (p->>'category_id')::uuid and business_id = v_biz) then
    raise exception 'Expense category not found.';
  end if;
  v_branch := app.resolve_branch(v_biz, nullif(p->>'branch_id', '')::uuid);
  v_date := coalesce(nullif(p->>'expense_date', '')::date, (now() at time zone app.tz(v_biz))::date);

  insert into expenses(business_id, branch_id, category_id, title, amount, expense_date, account_id, paid_by, note,
                       receipt_url, is_recurring, recurrence, created_by)
  values (v_biz, v_branch, nullif(p->>'category_id', '')::uuid, v_title, v_amount, v_date, v_acc,
          nullif(p->>'paid_by', ''), nullif(p->>'note', ''), nullif(p->>'receipt_url', ''),
          coalesce((p->>'is_recurring')::boolean, false), nullif(p->>'recurrence', ''), auth.uid())
  returning id into v_id;
  perform app.acct_txn(v_biz, v_branch, v_acc, 'out', v_amount, 'expense', v_id, v_title);
  perform app.log(v_biz, 'expense.create', 'expense', v_id, jsonb_build_object('title', v_title, 'amount', v_amount));
  return v_id;
end $$;

create or replace function public.void_expense(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; e record;
begin
  v_biz := app.require_perm('expenses.void');
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'A reason is required.'; end if;
  select * into e from expenses where id = p_id and business_id = v_biz for update;
  if not found then raise exception 'Expense not found.'; end if;
  if e.status = 'void' then raise exception 'This expense is already void.'; end if;
  update expenses set status = 'void', void_reason = trim(p_reason) where id = e.id;
  perform app.acct_txn(v_biz, e.branch_id, e.account_id, 'in', e.amount, 'expense_void', e.id, 'Void: ' || e.title);
  perform app.log(v_biz, 'expense.void', 'expense', e.id, jsonb_build_object('title', e.title, 'reason', p_reason));
end $$;
