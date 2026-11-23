-- EZ POS - Phase 2 - 0007: internal helpers for serial/IMEI units and batches.

-- Parses a JSON array of serial numbers into a clean, upper-case, duplicate-free array.
create or replace function app.serial_list(j jsonb) returns text[]
language plpgsql immutable as $$
declare r text[] := '{}'; x text; v text;
begin
  if j is null or jsonb_typeof(j) <> 'array' then return r; end if;
  for x in select jsonb_array_elements_text(j) loop
    v := app.norm_serial(x);
    if v = '' then continue; end if;
    if v = any (r) then raise exception 'Serial/IMEI % is entered twice.', v; end if;
    r := r || v;
  end loop;
  return r;
end $$;

create or replace function app.unit_event(
  p_biz uuid, p_unit uuid, p_type text, p_from text, p_to text, p_ref_type text, p_ref_id uuid, p_note text)
returns void language sql security definer set search_path = public as $$
  insert into stock_unit_events(business_id, unit_id, event_type, from_status, to_status, reference_type, reference_id, note, created_by)
  values (p_biz, p_unit, p_type, p_from, p_to, p_ref_type, p_ref_id, p_note, auth.uid())
$$;

-- Registers new units (purchase, opening stock, increase). A unit we returned to the supplier may be received again.
create or replace function app.add_units(
  p_biz uuid, p_branch uuid, p_product uuid, p_serials text[], p_kind text, p_cost numeric,
  p_purchase uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare s text; u record; v_id uuid;
begin
  foreach s in array coalesce(p_serials, '{}') loop
    if p_kind = 'imei' and not app.valid_imei(s) then
      raise exception '% is not a valid IMEI (15 digits with a correct check digit).', s;
    end if;
    select * into u from stock_units
    where business_id = p_biz and serial_no = s and (product_id = p_product or kind = 'imei' or p_kind = 'imei')
    limit 1 for update;
    if found then
      if u.status = 'returned_to_supplier' and u.product_id = p_product then
        update stock_units set status = 'in_stock', branch_id = p_branch, unit_cost = coalesce(p_cost, 0),
               purchase_id = p_purchase, sale_id = null, sale_item_id = null, customer_id = null, sold_at = null,
               warranty_until = null, updated_at = now()
        where id = u.id;
        perform app.unit_event(p_biz, u.id, 'received_again', u.status, 'in_stock', 'purchase', p_purchase, p_note);
      else
        raise exception 'Serial/IMEI % already exists in your records.', s;
      end if;
    else
      insert into stock_units(business_id, branch_id, product_id, serial_no, kind, status, unit_cost, purchase_id, note)
      values (p_biz, p_branch, p_product, s, p_kind, 'in_stock', coalesce(p_cost, 0), p_purchase, p_note)
      returning id into v_id;
      perform app.unit_event(p_biz, v_id, 'received', null, 'in_stock', case when p_purchase is null then 'adjustment' else 'purchase' end,
                             p_purchase, p_note);
    end if;
  end loop;
end $$;

-- Locks the units and checks they are in the expected state; returns their ids in the order given.
create or replace function app.take_units(
  p_biz uuid, p_branch uuid, p_product uuid, p_serials text[], p_status text default 'in_stock')
returns uuid[] language plpgsql security definer set search_path = public as $$
declare s text; u record; ids uuid[] := '{}';
begin
  foreach s in array coalesce(p_serials, '{}') loop
    select * into u from stock_units where business_id = p_biz and product_id = p_product and serial_no = s for update;
    if not found then raise exception 'Serial/IMEI % was not found for this product.', s; end if;
    if u.status <> p_status then
      raise exception 'Serial/IMEI % is not available (current status: %).', s, replace(u.status, '_', ' ');
    end if;
    if p_branch is not null and u.branch_id <> p_branch then
      raise exception 'Serial/IMEI % is in a different branch.', s;
    end if;
    ids := ids || u.id;
  end loop;
  return ids;
end $$;

create or replace function app.sell_units(
  p_biz uuid, p_branch uuid, p_product uuid, p_serials text[], p_sale uuid, p_item uuid,
  p_customer uuid, p_invoice text, p_warranty_months integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_unit uuid;
begin
  foreach v_unit in array app.take_units(p_biz, p_branch, p_product, p_serials, 'in_stock') loop
    update stock_units set status = 'sold', sale_id = p_sale, sale_item_id = p_item, customer_id = p_customer,
           sold_at = now(),
           warranty_until = case when coalesce(p_warranty_months, 0) > 0
                                 then (current_date + make_interval(months => p_warranty_months))::date end,
           updated_at = now()
    where stock_units.id = v_unit;
    perform app.unit_event(p_biz, v_unit, 'sold', 'in_stock', 'sold', 'sale', p_sale, p_invoice);
  end loop;
end $$;

-- Puts sold units back (void sale).
create or replace function app.release_sale_units(p_biz uuid, p_sale uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare u record;
begin
  for u in select id from stock_units where business_id = p_biz and sale_id = p_sale and status = 'sold' for update loop
    update stock_units set status = 'in_stock', sale_id = null, sale_item_id = null, customer_id = null,
           sold_at = null, warranty_until = null, updated_at = now()
    where id = u.id;
    perform app.unit_event(p_biz, u.id, 'sale_void', 'sold', 'in_stock', 'sale', p_sale, p_note);
  end loop;
end $$;

-- Customer returns specific units: they must belong to that invoice line.
create or replace function app.return_units(
  p_biz uuid, p_product uuid, p_serials text[], p_sale_item uuid, p_condition text, p_return uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare s text; u record; v_to text;
begin
  v_to := case p_condition when 'resellable' then 'in_stock' when 'damaged' then 'damaged' else 'inspection' end;
  foreach s in array coalesce(p_serials, '{}') loop
    select * into u from stock_units where business_id = p_biz and product_id = p_product and serial_no = s for update;
    if not found or u.status <> 'sold' or u.sale_item_id is distinct from p_sale_item then
      raise exception 'Serial/IMEI % was not sold on this invoice line.', s;
    end if;
    update stock_units set status = v_to, sale_id = null, sale_item_id = null, customer_id = null,
           sold_at = null, warranty_until = null, updated_at = now()
    where id = u.id;
    perform app.unit_event(p_biz, u.id, 'sales_return', 'sold', v_to, 'sales_return', p_return, p_note);
  end loop;
end $$;

-- ---------------------------------------------------------------- batches
-- First-expiry-first-out. Returns the batches used as [{batch_id, batch_no, expiry_date, quantity, unit_cost}].
-- Stock that pre-dates batch tracking has no batch row; any remainder is simply left unbatched unless p_strict.
create or replace function app.consume_batches(
  p_biz uuid, p_branch uuid, p_product uuid, p_qty numeric, p_batch_no text default null, p_strict boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record; v_left numeric := p_qty; v_take numeric; v_used jsonb := '[]'::jsonb;
begin
  for b in
    select * from stock_batches
    where business_id = p_biz and branch_id = p_branch and product_id = p_product and quantity_left > 0
      and (p_batch_no is null or batch_no = p_batch_no)
    order by expiry_date nulls last, created_at, id
    for update
  loop
    exit when v_left <= 0;
    v_take := least(b.quantity_left, v_left);
    update stock_batches set quantity_left = quantity_left - v_take where id = b.id;
    v_used := v_used || jsonb_build_object('batch_id', b.id, 'batch_no', b.batch_no, 'expiry_date', b.expiry_date,
                                           'quantity', v_take, 'unit_cost', b.unit_cost);
    v_left := v_left - v_take;
  end loop;
  if p_strict and v_left > 0.0004 then
    raise exception 'Not enough quantity left in batch %.', coalesce(p_batch_no, '');
  end if;
  return v_used;
end $$;

create or replace function app.record_sale_batches(p_biz uuid, p_item uuid, p_used jsonb)
returns void language sql security definer set search_path = public as $$
  insert into sale_item_batches(business_id, sale_item_id, batch_id, quantity)
  select p_biz, p_item, (x->>'batch_id')::uuid, (x->>'quantity')::numeric
  from jsonb_array_elements(coalesce(p_used, '[]'::jsonb)) as x
$$;

-- Gives quantity back to the batches a sale line took from (void and resellable returns).
create or replace function app.restore_sale_batches(p_item uuid, p_qty numeric)
returns void language plpgsql security definer set search_path = public as $$
declare r record; v_left numeric := p_qty; v_back numeric;
begin
  for r in
    select * from sale_item_batches where sale_item_id = p_item and quantity - returned_quantity > 0
    order by seq desc for update
  loop
    exit when v_left <= 0;
    v_back := least(r.quantity - r.returned_quantity, v_left);
    update sale_item_batches set returned_quantity = returned_quantity + v_back where seq = r.seq;
    update stock_batches set quantity_left = quantity_left + v_back where id = r.batch_id;
    v_left := v_left - v_back;
  end loop;
end $$;

-- Takes the slice [p_offset, p_offset + p_qty) out of an ordered batch list (partial transfer receipts).
create or replace function app.batch_slice(p_batches jsonb, p_offset numeric, p_qty numeric)
returns jsonb language plpgsql immutable as $$
declare x jsonb; pos numeric := 0; q numeric; lo numeric; hi numeric; out jsonb := '[]'::jsonb;
begin
  for x in select * from jsonb_array_elements(coalesce(p_batches, '[]'::jsonb)) loop
    q := (x->>'quantity')::numeric;
    lo := greatest(pos, p_offset);
    hi := least(pos + q, p_offset + p_qty);
    if hi > lo then out := out || jsonb_set(x, '{quantity}', to_jsonb(hi - lo)); end if;
    pos := pos + q;
  end loop;
  return out;
end $$;

create or replace function app.create_batches(
  p_biz uuid, p_branch uuid, p_product uuid, p_batches jsonb, p_purchase uuid)
returns void language sql security definer set search_path = public as $$
  insert into stock_batches(business_id, branch_id, product_id, batch_no, expiry_date, quantity_received, quantity_left, unit_cost, purchase_id)
  select p_biz, p_branch, p_product, x->>'batch_no', nullif(x->>'expiry_date', '')::date,
         (x->>'quantity')::numeric, (x->>'quantity')::numeric, coalesce((x->>'unit_cost')::numeric, 0), p_purchase
  from jsonb_array_elements(coalesce(p_batches, '[]'::jsonb)) as x
$$;
