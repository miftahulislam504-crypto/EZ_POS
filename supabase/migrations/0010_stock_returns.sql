-- EZ POS - Phase 2 - 0010: branches, stock transfer, purchase return, exchange, physical stock count,
-- serial/IMEI and batch look-ups, documents.

-- ---------------------------------------------------------------- branches and warehouses (minimal, full multi-branch is Phase 3)
-- Payload: {id?, name, address?, phone?, kind: branch|warehouse, is_active?}
create or replace function public.save_branch(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; v_id uuid := nullif(p->>'id', '')::uuid; v_kind text;
begin
  v_biz := app.require_perm('settings.manage');
  if nullif(trim(coalesce(p->>'name', '')), '') is null then raise exception 'Enter a name.'; end if;
  v_kind := coalesce(nullif(p->>'kind', ''), 'branch');
  if v_kind not in ('branch', 'warehouse') then raise exception 'Invalid type.'; end if;
  if v_id is null then
    insert into branches(business_id, name, address, phone, kind)
    values (v_biz, trim(p->>'name'), nullif(p->>'address', ''), nullif(p->>'phone', ''), v_kind)
    returning id into v_id;
  else
    update branches set name = trim(p->>'name'), address = nullif(p->>'address', ''), phone = nullif(p->>'phone', ''),
           kind = v_kind, is_active = coalesce((p->>'is_active')::boolean, is_active)
    where id = v_id and business_id = v_biz;
    if not found then raise exception 'Branch not found.'; end if;
    if exists (select 1 from branches where id = v_id and is_default and not is_active) then
      raise exception 'The main branch cannot be deactivated.';
    end if;
  end if;
  perform app.log(v_biz, 'branch.save', 'branch', v_id, p);
  return v_id;
end $$;

-- ---------------------------------------------------------------- stock transfer
-- Payload: {from_branch_id, to_branch_id, note?, client_ref?, dispatch?: bool,
--           items: [{product_id, quantity, serials?: [text]}]}
create or replace function public.create_stock_transfer(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; v_from uuid; v_to uuid; v_id uuid; v_no text; v_ref uuid; ex record; it record; pr record;
  v_qty numeric; v_ser text[];
begin
  v_biz := app.require_perm('transfers.manage');
  v_ref := nullif(p->>'client_ref', '')::uuid;
  if v_ref is not null then
    select id, transfer_no, status into ex from stock_transfers where business_id = v_biz and client_ref = v_ref;
    if found then
      return jsonb_build_object('id', ex.id, 'transfer_no', ex.transfer_no, 'status', ex.status, 'duplicate', true);
    end if;
  end if;
  v_from := (p->>'from_branch_id')::uuid;
  v_to := (p->>'to_branch_id')::uuid;
  if v_from is null or v_to is null or v_from = v_to then raise exception 'Choose two different locations.'; end if;
  if (select count(*) from branches where business_id = v_biz and is_active and id in (v_from, v_to)) <> 2 then
    raise exception 'Location not found.';
  end if;
  if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') = 0 then
    raise exception 'Add at least one product.';
  end if;

  v_no := app.doc_no(v_biz, 'stock_transfer', 'TRF');
  insert into stock_transfers(business_id, transfer_no, from_branch_id, to_branch_id, note, requested_by, client_ref)
  values (v_biz, v_no, v_from, v_to, nullif(p->>'note', ''), auth.uid(), v_ref)
  returning id into v_id;

  for it in select e.value as j from jsonb_array_elements(p->'items') as e(value) loop
    select * into pr from products where id = (it.j->>'product_id')::uuid and business_id = v_biz;
    if not found then raise exception 'Product not found.'; end if;
    if not pr.track_stock then raise exception '"%" does not track stock.', pr.name; end if;
    v_qty := (it.j->>'quantity')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Invalid quantity for "%".', pr.name; end if;
    v_ser := app.serial_list(it.j->'serials');
    if pr.tracking_type in ('serial', 'imei') then
      if v_qty <> trunc(v_qty) then raise exception '"%" is counted in whole units.', pr.name; end if;
      if array_length(v_ser, 1) is not null and array_length(v_ser, 1) <> v_qty then
        raise exception 'Select exactly % serial/IMEI number(s) for "%".', v_qty, pr.name;
      end if;
    else
      v_ser := '{}';
    end if;
    insert into stock_transfer_items(business_id, transfer_id, product_id, product_name, quantity, unit_cost, serials)
    values (v_biz, v_id, pr.id, pr.name, v_qty, pr.avg_cost, v_ser);
  end loop;

  perform app.log(v_biz, 'transfer.create', 'stock_transfer', v_id, jsonb_build_object('transfer_no', v_no));
  if coalesce((p->>'dispatch')::boolean, false) then
    perform public.dispatch_stock_transfer(jsonb_build_object('id', v_id));
  end if;
  return jsonb_build_object('id', v_id, 'transfer_no', v_no,
    'status', (select status from stock_transfers where id = v_id), 'duplicate', false);
end $$;

-- Payload: {id, items?: [{item_id, serials: [text]}]}  (serials are needed for IMEI/serial products)
-- Stock leaves the sending location now; units move to "in transit".
create or replace function public.dispatch_stock_transfer(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; t record; it record; pr record; v_ser text[]; v_cur numeric; v_ids uuid[]; v_id uuid; v_used jsonb; x jsonb;
begin
  v_biz := app.require_perm('transfers.manage');
  select * into t from stock_transfers where id = (p->>'id')::uuid and business_id = v_biz for update;
  if not found then raise exception 'Transfer not found.'; end if;
  if t.status <> 'requested' then raise exception 'This transfer is already %.', replace(t.status, '_', ' '); end if;

  for it in select * from stock_transfer_items where transfer_id = t.id order by id loop
    select * into pr from products where id = it.product_id;
    v_ser := it.serials;
    if jsonb_typeof(p->'items') = 'array' then
      for x in select * from jsonb_array_elements(p->'items') loop
        if (x->>'item_id')::uuid = it.id then v_ser := app.serial_list(x->'serials'); end if;
      end loop;
    end if;

    select quantity into v_cur from stock_levels where branch_id = t.from_branch_id and product_id = it.product_id for update;
    if coalesce(v_cur, 0) < it.quantity then
      raise exception 'Only % of "%" is in stock at the sending location.', coalesce(v_cur, 0), it.product_name;
    end if;

    v_used := '[]'::jsonb;
    if pr.tracking_type in ('serial', 'imei') then
      if coalesce(array_length(v_ser, 1), 0) <> it.quantity then
        raise exception 'Select % serial/IMEI number(s) for "%".', it.quantity, it.product_name;
      end if;
      v_ids := app.take_units(v_biz, t.from_branch_id, it.product_id, v_ser, 'in_stock');
      foreach v_id in array v_ids loop
        update stock_units set status = 'in_transit', transfer_id = t.id, updated_at = now() where id = v_id;
        perform app.unit_event(v_biz, v_id, 'transfer_out', 'in_stock', 'in_transit', 'stock_transfer', t.id, t.transfer_no);
      end loop;
    elsif pr.tracking_type in ('batch', 'expiry') then
      v_used := app.consume_batches(v_biz, t.from_branch_id, it.product_id, it.quantity);
    end if;

    perform app.apply_stock(v_biz, t.from_branch_id, it.product_id, -it.quantity, 'transfer_out', pr.avg_cost,
                            'stock_transfer', t.id, t.transfer_no);
    update stock_transfer_items set sent_quantity = quantity, serials = coalesce(v_ser, '{}'), batches = v_used,
           unit_cost = pr.avg_cost
    where id = it.id;
  end loop;

  update stock_transfers set status = 'in_transit', dispatched_by = auth.uid(), dispatched_at = now() where id = t.id;
  perform app.log(v_biz, 'transfer.dispatch', 'stock_transfer', t.id, jsonb_build_object('transfer_no', t.transfer_no));
  return jsonb_build_object('id', t.id, 'transfer_no', t.transfer_no, 'status', 'in_transit');
end $$;

-- Payload: {id, receive_all?: bool, items?: [{item_id, quantity, serials?}], close_short?: bool, short_reason?: text}
-- A transfer can be received in several steps. Closing it short records the difference and writes the missing units off.
create or replace function public.receive_stock_transfer(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; t record; it record; pr record; x jsonb; v_all boolean; v_q numeric; v_ser text[]; v_ids uuid[]; v_id uuid;
  v_left numeric; v_status text; v_short boolean := coalesce((p->>'close_short')::boolean, false);
  v_receive_all boolean := coalesce((p->>'receive_all')::boolean, false); v_item jsonb; v_done boolean;
begin
  v_biz := app.require_perm('transfers.manage');
  select * into t from stock_transfers where id = (p->>'id')::uuid and business_id = v_biz for update;
  if not found then raise exception 'Transfer not found.'; end if;
  if t.status not in ('in_transit', 'partially_received') then
    raise exception 'This transfer is %, so it cannot be received.', replace(t.status, '_', ' ');
  end if;
  if v_short and nullif(trim(coalesce(p->>'short_reason', '')), '') is null then
    raise exception 'Write the reason for the missing quantity.';
  end if;

  for it in select * from stock_transfer_items where transfer_id = t.id order by id for update loop
    v_left := it.sent_quantity - it.received_quantity;
    v_item := null;
    if v_receive_all then
      v_q := v_left;
    elsif jsonb_typeof(p->'items') = 'array' then
      v_q := 0;
      for x in select * from jsonb_array_elements(p->'items') loop
        if (x->>'item_id')::uuid = it.id then v_q := coalesce((x->>'quantity')::numeric, 0); v_item := x; end if;
      end loop;
    else
      v_q := 0;
    end if;
    if v_q < 0 or v_q > v_left + 0.0005 then
      raise exception 'Cannot receive % of "%": only % is still on the way.', v_q, it.product_name, v_left;
    end if;
    if v_q <= 0 then continue; end if;

    select * into pr from products where id = it.product_id;
    v_ser := '{}';
    if pr.tracking_type in ('serial', 'imei') then
      if v_q <> trunc(v_q) then raise exception '"%" is counted in whole units.', it.product_name; end if;
      if v_receive_all or v_item is null or v_item->'serials' is null then
        v_ser := array(select s from unnest(it.serials) as s where not (s = any (it.received_serials)) limit v_q::integer);
      else
        v_ser := app.serial_list(v_item->'serials');
      end if;
      if coalesce(array_length(v_ser, 1), 0) <> v_q then
        raise exception 'Select % serial/IMEI number(s) received for "%".', v_q, it.product_name;
      end if;
      if exists (select 1 from unnest(v_ser) as s where not (s = any (it.serials)) or s = any (it.received_serials)) then
        raise exception 'A serial/IMEI number does not belong to this transfer.';
      end if;
      v_ids := app.take_units(v_biz, null, it.product_id, v_ser, 'in_transit');
      foreach v_id in array v_ids loop
        update stock_units set status = 'in_stock', branch_id = t.to_branch_id, transfer_id = null, updated_at = now()
        where id = v_id;
        perform app.unit_event(v_biz, v_id, 'transfer_in', 'in_transit', 'in_stock', 'stock_transfer', t.id, t.transfer_no);
      end loop;
    elsif pr.tracking_type in ('batch', 'expiry') then
      perform app.create_batches(v_biz, t.to_branch_id, it.product_id,
                                 app.batch_slice(it.batches, it.received_quantity, v_q), null);
    end if;

    perform app.apply_stock(v_biz, t.to_branch_id, it.product_id, v_q, 'transfer_in', it.unit_cost,
                            'stock_transfer', t.id, t.transfer_no);
    update stock_transfer_items set received_quantity = received_quantity + v_q,
           received_serials = received_serials || v_ser
    where id = it.id;
  end loop;

  v_done := not exists (select 1 from stock_transfer_items where transfer_id = t.id and received_quantity < sent_quantity - 0.0005);
  if v_done then
    v_status := 'received';
  elsif v_short then
    -- missing units are written off; the difference stays visible on the transfer
    for it in select * from stock_transfer_items where transfer_id = t.id and received_quantity < sent_quantity - 0.0005 loop
      update stock_transfer_items set shortage_reason = trim(p->>'short_reason') where id = it.id;
      for v_id in select u.id from stock_units u where u.transfer_id = t.id and u.product_id = it.product_id and u.status = 'in_transit' loop
        update stock_units set status = 'lost', updated_at = now() where id = v_id;
        perform app.unit_event(v_biz, v_id, 'transfer_short', 'in_transit', 'lost', 'stock_transfer', t.id, p->>'short_reason');
      end loop;
    end loop;
    v_status := 'received';
  else
    v_status := 'partially_received';
  end if;
  update stock_transfers set status = v_status,
         received_by = case when v_status = 'received' then auth.uid() else received_by end,
         received_at = case when v_status = 'received' then now() else received_at end
  where id = t.id;
  perform app.log(v_biz, 'transfer.receive', 'stock_transfer', t.id,
                  jsonb_build_object('transfer_no', t.transfer_no, 'status', v_status));
  return jsonb_build_object('id', t.id, 'transfer_no', t.transfer_no, 'status', v_status);
end $$;

create or replace function public.cancel_stock_transfer(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; t record; it record; v_id uuid;
begin
  v_biz := app.require_perm('transfers.manage');
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'A reason is required to cancel a transfer.'; end if;
  select * into t from stock_transfers where id = p_id and business_id = v_biz for update;
  if not found then raise exception 'Transfer not found.'; end if;
  if t.status = 'in_transit' then
    for it in select * from stock_transfer_items where transfer_id = t.id loop
      perform app.apply_stock(v_biz, t.from_branch_id, it.product_id, it.sent_quantity, 'transfer_cancel', it.unit_cost,
                              'stock_transfer', t.id, 'Cancelled ' || t.transfer_no);
      for v_id in select u.id from stock_units u where u.transfer_id = t.id and u.product_id = it.product_id and u.status = 'in_transit' loop
        update stock_units set status = 'in_stock', transfer_id = null, updated_at = now() where id = v_id;
        perform app.unit_event(v_biz, v_id, 'transfer_cancel', 'in_transit', 'in_stock', 'stock_transfer', t.id, p_reason);
      end loop;
      perform app.create_batches(v_biz, t.from_branch_id, it.product_id, it.batches, null);
    end loop;
  elsif t.status <> 'requested' then
    raise exception 'A % transfer cannot be cancelled.', replace(t.status, '_', ' ');
  end if;
  update stock_transfers set status = 'cancelled', cancel_reason = trim(p_reason) where id = t.id;
  perform app.log(v_biz, 'transfer.cancel', 'stock_transfer', t.id, jsonb_build_object('reason', p_reason));
end $$;

-- ---------------------------------------------------------------- purchase return
-- Payload: {purchase_id, reason?, refund_mode: credit|cash, refund_account_id? (cash), return_date?,
--           items: [{purchase_item_id, quantity, serials?: [text]}]}
-- Credit value of a line = its line total pro-rata (header discount, tax and other charges are not credited).
create or replace function public.create_purchase_return(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; pu record; pi record; pr record; it record; b record; v_ret uuid := gen_random_uuid(); v_no text; v_mode text;
  v_q numeric; v_val numeric; v_total numeric := 0; v_apply numeric := 0; v_refund numeric := 0; v_acc uuid;
  v_ser text[]; v_ids uuid[]; v_id uuid; v_cur numeric; v_left numeric; v_take numeric;
begin
  v_biz := app.require_perm('purchases.return');
  select * into pu from purchases where id = (p->>'purchase_id')::uuid and business_id = v_biz for update;
  if not found then raise exception 'Purchase not found.'; end if;
  if pu.status <> 'received' then raise exception 'Only received purchases can be returned.'; end if;
  if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') = 0 then
    raise exception 'Select at least one item to return.';
  end if;
  v_mode := coalesce(nullif(p->>'refund_mode', ''), 'credit');
  if v_mode not in ('credit', 'cash') then raise exception 'Invalid refund mode.'; end if;

  v_no := app.doc_no(v_biz, 'purchase_return', 'PRT');
  insert into purchase_returns(id, business_id, branch_id, return_no, purchase_id, supplier_id, return_date, reason,
                               refund_mode, created_by)
  values (v_ret, v_biz, pu.branch_id, v_no, pu.id, pu.supplier_id, coalesce(nullif(p->>'return_date', '')::timestamptz, now()),
          nullif(p->>'reason', ''), v_mode, auth.uid());

  for it in select e.value as j from jsonb_array_elements(p->'items') as e(value) loop
    select * into pi from purchase_items where id = (it.j->>'purchase_item_id')::uuid and purchase_id = pu.id for update;
    if not found then raise exception 'Purchase line not found.'; end if;
    v_q := (it.j->>'quantity')::numeric;
    if v_q is null or v_q <= 0 then continue; end if;
    if v_q > pi.received_quantity - pi.returned_quantity + 0.0005 then
      raise exception 'Cannot return % of "%": only % can still be returned.', v_q, pi.product_name,
                      pi.received_quantity - pi.returned_quantity;
    end if;
    select * into pr from products where id = pi.product_id;
    v_val := round(pi.line_total * v_q / pi.quantity, 2);
    v_ser := '{}';

    if pr.track_stock then
      select quantity into v_cur from stock_levels where branch_id = pu.branch_id and product_id = pi.product_id for update;
      if coalesce(v_cur, 0) < v_q then
        raise exception 'Only % of "%" is in stock, so % cannot be returned.', coalesce(v_cur, 0), pi.product_name, v_q;
      end if;
      if pr.tracking_type in ('serial', 'imei') then
        v_ser := app.serial_list(it.j->'serials');
        if v_q <> trunc(v_q) or coalesce(array_length(v_ser, 1), 0) <> v_q then
          raise exception 'Select the serial/IMEI number of each returned unit of "%".', pi.product_name;
        end if;
        v_ids := app.take_units(v_biz, pu.branch_id, pi.product_id, v_ser, 'in_stock');
        if exists (select 1 from stock_units where id = any (v_ids) and purchase_id is distinct from pu.id) then
          raise exception 'A serial/IMEI number was not bought on this purchase.';
        end if;
        foreach v_id in array v_ids loop
          update stock_units set status = 'returned_to_supplier', updated_at = now() where id = v_id;
          perform app.unit_event(v_biz, v_id, 'purchase_return', 'in_stock', 'returned_to_supplier', 'purchase_return', v_ret, v_no);
        end loop;
      elsif pr.tracking_type in ('batch', 'expiry') then
        v_left := v_q;
        for b in select * from stock_batches
                 where purchase_id = pu.id and product_id = pi.product_id and branch_id = pu.branch_id and quantity_left > 0
                 order by created_at, id for update loop
          exit when v_left <= 0;
          v_take := least(b.quantity_left, v_left);
          update stock_batches set quantity_left = quantity_left - v_take where id = b.id;
          v_left := v_left - v_take;
        end loop;
        if v_left > 0.0004 then
          raise exception 'Only part of "%" is left in the purchased batch; the rest was already sold.', pi.product_name;
        end if;
      end if;
      perform app.apply_stock(v_biz, pu.branch_id, pi.product_id, -v_q, 'purchase_return', pi.landed_unit_cost,
                              'purchase_return', v_ret, v_no);
    end if;

    insert into purchase_return_items(business_id, return_id, purchase_item_id, product_id, product_name, quantity, line_total, serials)
    values (v_biz, v_ret, pi.id, pi.product_id, pi.product_name, v_q, v_val, v_ser);
    update purchase_items set returned_quantity = returned_quantity + v_q where id = pi.id;
    v_total := v_total + v_val;
  end loop;
  if v_total <= 0 then raise exception 'Select at least one item to return.'; end if;

  v_apply := least(pu.due_amount, v_total);
  v_refund := case when v_mode = 'cash' then v_total - v_apply else 0 end;
  if v_refund > 0 then
    v_acc := nullif(p->>'refund_account_id', '')::uuid;
    perform app.check_account(v_biz, v_acc);
  end if;

  perform app.supp_ledger(v_biz, pu.supplier_id, 'return', 'Return ' || v_no || ' on ' || pu.purchase_no, v_total, 0,
                          'purchase_return', v_ret, v_no);
  if v_refund > 0 then
    perform app.supp_ledger(v_biz, pu.supplier_id, 'refund', 'Refund received ' || v_no, 0, v_refund,
                            'purchase_return', v_ret, v_no);
    perform app.acct_txn(v_biz, pu.branch_id, v_acc, 'in', v_refund, 'purchase_return_refund', v_ret, 'Supplier refund ' || v_no);
  end if;

  update purchase_returns set total = v_total, due_adjusted = v_apply, refund_amount = v_refund,
         refund_account_id = case when v_refund > 0 then v_acc end
  where id = v_ret;
  update purchases set returned_amount = returned_amount + v_total, due_amount = due_amount - v_apply where id = pu.id;

  perform app.log(v_biz, 'purchase.return', 'purchase_return', v_ret,
                  jsonb_build_object('return_no', v_no, 'purchase_no', pu.purchase_no, 'total', v_total, 'refund', v_refund));
  return jsonb_build_object('id', v_ret, 'return_no', v_no, 'total', v_total, 'due_adjusted', v_apply, 'refund', v_refund);
end $$;

-- ---------------------------------------------------------------- exchange
-- Takes back items from a completed regular sale and sells new items in one step. The value of the returned items
-- becomes credit on the new invoice (exchange_credit); the customer pays any extra, and any leftover is refunded
-- or kept as customer credit.
-- Payload: {sale_id, reason?, return_items: [{sale_item_id, quantity, condition, serials?}],
--           new_sale: {items: [...], note?, invoice_discount?, client_ref?}, payments: [{account_id, amount}],
--           refund_mode: cash|credit, refund_account_id?}
create or replace function public.create_exchange(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; s record; ns record; v_ret jsonb; v_new jsonb; v_avail numeric; v_used numeric; v_left numeric;
  v_mode text; v_acc uuid; v_payload jsonb; v_ret_id uuid;
begin
  v_biz := app.require_perm('returns.create');
  perform app.require_perm('sales.create');
  select * into s from sales where id = (p->>'sale_id')::uuid and business_id = v_biz;
  if not found then raise exception 'Sale not found.'; end if;
  if jsonb_typeof(p->'return_items') is distinct from 'array' or jsonb_array_length(p->'return_items') = 0 then
    raise exception 'Select the items being returned.';
  end if;
  if jsonb_typeof(p->'new_sale'->'items') is distinct from 'array' or jsonb_array_length(p->'new_sale'->'items') = 0 then
    raise exception 'Add the new items the customer is taking.';
  end if;
  v_mode := coalesce(nullif(p->>'refund_mode', ''), 'cash');
  if v_mode not in ('cash', 'credit') then raise exception 'Invalid refund mode.'; end if;
  if v_mode = 'credit' and s.customer_id is null then v_mode := 'cash'; end if;

  v_ret := public.create_sales_return(jsonb_build_object(
    'sale_id', s.id, 'reason', 'Exchange: ' || coalesce(nullif(trim(p->>'reason'), ''), 'exchange'),
    'refund_mode', 'exchange', 'items', p->'return_items'));
  v_ret_id := (v_ret->>'id')::uuid;
  v_avail := (v_ret->>'total')::numeric - (v_ret->>'due_adjusted')::numeric;

  v_payload := (p->'new_sale') || jsonb_build_object('payments', coalesce(p->'payments', '[]'::jsonb));
  if s.customer_id is not null and nullif(v_payload->>'customer_id', '') is null then
    v_payload := v_payload || jsonb_build_object('customer_id', s.customer_id);
  end if;
  perform set_config('app.exchange_credit', v_avail::text, true);
  v_new := public.create_sale(v_payload);
  perform set_config('app.exchange_credit', '', true);

  select * into ns from sales where id = (v_new->>'id')::uuid;
  v_used := ns.exchange_credit;
  v_left := round(v_avail - v_used, 2);
  if v_left > 0.004 and not (v_mode = 'credit' and s.customer_id is not null) then
    v_acc := nullif(p->>'refund_account_id', '')::uuid;
    perform app.check_account(v_biz, v_acc);
    if s.customer_id is not null then
      perform app.cust_ledger(v_biz, s.customer_id, 'refund', 'Exchange refund ' || (v_ret->>'return_no'),
                              v_left, 0, 'sales_return', v_ret_id, v_ret->>'return_no');
    end if;
    perform app.acct_txn(v_biz, s.branch_id, v_acc, 'out', v_left, 'sales_return_refund', v_ret_id,
                         'Exchange refund ' || (v_ret->>'return_no'));
    update sales_returns set refund_amount = v_left, refund_account_id = v_acc where id = v_ret_id;
    v_left := 0;
  end if;

  update sales set exchange_of_return_id = v_ret_id where id = ns.id;
  update sales_returns set exchange_sale_id = ns.id where id = v_ret_id;
  perform app.log(v_biz, 'sale.exchange', 'sales_return', v_ret_id,
    jsonb_build_object('return_no', v_ret->>'return_no', 'new_invoice', ns.invoice_no));
  return jsonb_build_object('return_id', v_ret_id, 'return_no', v_ret->>'return_no', 'return_total', (v_ret->>'total')::numeric,
    'sale_id', ns.id, 'invoice_no', ns.invoice_no, 'new_total', ns.total, 'credit_used', v_used,
    'customer_paid', ns.paid_amount - v_used, 'due', ns.due_amount, 'customer_credit_left', v_left);
end $$;

-- ---------------------------------------------------------------- physical stock count
-- Payload: {id?, branch_id?, note?, items: [{product_id, counted_quantity, reason?}], finalize?: bool}
-- Draft counts can be saved and reopened; finalizing posts one adjustment per product that differs.
-- Serial/IMEI and batch products are counted from their own screens, not here.
create or replace function public.save_stock_count(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; v_id uuid := nullif(p->>'id', '')::uuid; c record; v_branch uuid; it record; pr record; v_sys numeric;
  v_q numeric; v_diff numeric; v_no text; v_lines integer := 0; v_changed integer := 0; v_reason text;
begin
  v_biz := app.require_perm('inventory.count');
  if v_id is null then
    v_branch := app.resolve_branch(v_biz, nullif(p->>'branch_id', '')::uuid);
    v_no := app.doc_no(v_biz, 'stock_count', 'CNT');
    insert into stock_counts(business_id, branch_id, count_no, note, created_by)
    values (v_biz, v_branch, v_no, nullif(p->>'note', ''), auth.uid()) returning id into v_id;
  else
    select * into c from stock_counts where id = v_id and business_id = v_biz for update;
    if not found then raise exception 'Stock count not found.'; end if;
    if c.status <> 'draft' then raise exception 'This stock count is already completed.'; end if;
    v_branch := c.branch_id; v_no := c.count_no;
    update stock_counts set note = coalesce(nullif(p->>'note', ''), note) where id = v_id;
  end if;

  for it in select e.value as j from jsonb_array_elements(coalesce(p->'items', '[]'::jsonb)) as e(value) loop
    select * into pr from products where id = (it.j->>'product_id')::uuid and business_id = v_biz;
    if not found then raise exception 'Product not found.'; end if;
    if not pr.track_stock then raise exception '"%" does not track stock.', pr.name; end if;
    if pr.tracking_type <> 'none' then
      raise exception '"%" is tracked by serial/batch; count it from the Serial/IMEI or Batch screens.', pr.name;
    end if;
    v_q := (it.j->>'counted_quantity')::numeric;
    if v_q is null or v_q < 0 then raise exception 'Enter the counted quantity for "%".', pr.name; end if;
    select coalesce(quantity, 0) into v_sys from stock_levels where branch_id = v_branch and product_id = pr.id;
    v_sys := coalesce(v_sys, 0);
    insert into stock_count_items(business_id, count_id, product_id, product_name, system_quantity, counted_quantity, difference, reason)
    values (v_biz, v_id, pr.id, pr.name, v_sys, v_q, v_q - v_sys, nullif(trim(coalesce(it.j->>'reason', '')), ''))
    on conflict (count_id, product_id) do update set system_quantity = excluded.system_quantity,
      counted_quantity = excluded.counted_quantity, difference = excluded.difference, reason = excluded.reason;
  end loop;

  if coalesce((p->>'finalize')::boolean, false) then
    perform app.require_perm('inventory.adjust');
    for it in select * from stock_count_items where count_id = v_id order by product_name loop
      -- refresh against the live stock so sales during the count are not lost
      select coalesce(quantity, 0) into v_sys from stock_levels where branch_id = v_branch and product_id = it.product_id;
      v_sys := coalesce(v_sys, 0);
      v_diff := it.counted_quantity - v_sys;
      update stock_count_items set system_quantity = v_sys, difference = v_diff where id = it.id;
      v_lines := v_lines + 1;
      if abs(v_diff) < 0.0005 then continue; end if;
      v_reason := coalesce(it.reason, '');
      if v_reason = '' then raise exception 'Write the reason for the difference on "%".', it.product_name; end if;
      v_changed := v_changed + 1;
      perform public.adjust_stock(it.product_id, v_branch, abs(v_diff),
                                  case when v_diff > 0 then 'increase' else 'decrease' end,
                                  'Stock count ' || v_no || ': ' || v_reason);
    end loop;
    if v_lines = 0 then raise exception 'Add at least one counted product.'; end if;
    update stock_counts set status = 'completed', completed_by = auth.uid(), completed_at = now() where id = v_id;
    perform app.log(v_biz, 'stock.count', 'stock_count', v_id, jsonb_build_object('count_no', v_no, 'adjusted', v_changed));
  end if;
  return jsonb_build_object('id', v_id, 'count_no', v_no, 'status', (select status from stock_counts where id = v_id),
                            'adjusted_products', v_changed);
end $$;

-- ---------------------------------------------------------------- serial / IMEI and batch look-ups
-- Everything known about one serial/IMEI: current state, buyer, warranty and its full history.
create or replace function public.serial_lookup(p_serial text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_biz uuid; u record; v_ev jsonb; v_key text := app.norm_serial(p_serial);
begin
  v_biz := app.require_perm('inventory.view');
  if v_key = '' then raise exception 'Enter a serial/IMEI number.'; end if;
  select * into u from stock_units where business_id = v_biz and serial_no = v_key order by created_at limit 1;
  if not found then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('event_type', e.event_type, 'from_status', e.from_status,
           'to_status', e.to_status, 'reference_type', e.reference_type, 'note', e.note, 'at', e.created_at)
           order by e.created_at), '[]'::jsonb) into v_ev
  from stock_unit_events e where e.unit_id = u.id;
  return jsonb_build_object(
    'id', u.id, 'serial_no', u.serial_no, 'kind', u.kind, 'status', u.status,
    'product_id', u.product_id, 'product_name', (select name from products where id = u.product_id),
    'branch_id', u.branch_id, 'branch_name', (select name from branches where id = u.branch_id),
    'unit_cost', u.unit_cost, 'warranty_until', u.warranty_until, 'sold_at', u.sold_at,
    'invoice_no', (select invoice_no from sales where id = u.sale_id),
    'customer_name', (select name from customers where id = u.customer_id),
    'customer_phone', (select phone from customers where id = u.customer_id),
    'purchase_no', (select purchase_no from purchases where id = u.purchase_id),
    'events', v_ev);
end $$;

-- Batches that expire within p_days (already expired ones included), earliest first.
create or replace function public.expiry_report(p_days integer default 30, p_branch uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_biz uuid; v_today date; v jsonb;
begin
  v_biz := app.require_perm('inventory.view');
  v_today := app.today(v_biz);
  select coalesce(jsonb_agg(jsonb_build_object(
      'batch_id', b.id, 'product_id', b.product_id, 'product_name', pr.name, 'batch_no', b.batch_no,
      'expiry_date', b.expiry_date, 'quantity_left', b.quantity_left, 'unit_cost', b.unit_cost,
      'value', round(b.quantity_left * b.unit_cost, 2), 'branch_name', br.name,
      'days_left', b.expiry_date - v_today, 'expired', b.expiry_date < v_today)
      order by b.expiry_date, pr.name), '[]'::jsonb) into v
  from stock_batches b join products pr on pr.id = b.product_id join branches br on br.id = b.branch_id
  where b.business_id = v_biz and b.quantity_left > 0 and b.expiry_date is not null
    and b.expiry_date <= v_today + greatest(coalesce(p_days, 30), 0)
    and (p_branch is null or b.branch_id = p_branch);
  return v;
end $$;

-- ---------------------------------------------------------------- documents (NID, agreements, bills, receipts)
-- Files live in the private "documents" bucket under <business_id>/<entity_type>/<entity_id>/<file>.
create or replace function public.add_document(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; v_type text := p->>'entity_type'; v_id uuid; v_path text := p->>'storage_path';
begin
  if v_type in ('customer', 'guarantor') then v_biz := app.require_perm('customers.documents');
  elsif v_type = 'supplier' then v_biz := app.require_perm('suppliers.manage');
  elsif v_type = 'installment' then v_biz := app.require_perm('installments.collect');
  elsif v_type = 'purchase' then v_biz := app.require_perm('purchases.create');
  elsif v_type = 'expense' then v_biz := app.require_perm('expenses.create');
  else raise exception 'Unknown document type.'; end if;
  if v_path is null or split_part(v_path, '/', 1) <> v_biz::text then raise exception 'Invalid file path.'; end if;
  insert into documents(business_id, entity_type, entity_id, doc_type, storage_path, file_name, note, uploaded_by)
  values (v_biz, v_type, (p->>'entity_id')::uuid, coalesce(nullif(p->>'doc_type', ''), 'other'), v_path,
          nullif(p->>'file_name', ''), nullif(p->>'note', ''), auth.uid())
  returning id into v_id;
  perform app.log(v_biz, 'document.add', v_type, (p->>'entity_id')::uuid, jsonb_build_object('doc_type', p->>'doc_type'));
  return v_id;
end $$;

create or replace function public.delete_document(p_id uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; d record;
begin
  select * into d from documents where id = p_id;
  if not found then raise exception 'Document not found.'; end if;
  if d.entity_type in ('customer', 'guarantor') then v_biz := app.require_perm('customers.documents');
  elsif d.entity_type = 'supplier' then v_biz := app.require_perm('suppliers.manage');
  elsif d.entity_type = 'installment' then v_biz := app.require_perm('installments.manage');
  elsif d.entity_type = 'purchase' then v_biz := app.require_perm('purchases.create');
  else v_biz := app.require_perm('expenses.create'); end if;
  if d.business_id <> v_biz then raise exception 'Document not found.'; end if;
  delete from documents where id = p_id;
  perform app.log(v_biz, 'document.delete', d.entity_type, d.entity_id, jsonb_build_object('doc_type', d.doc_type));
  return d.storage_path;
end $$;
