-- EZ POS - Phase 2 - 0014: closes the open Phase 2 items.
--   1. customers_view and installment_plans_view are rebuilt: they were created with "select table.*" before the
--      Phase 2 columns existed, so workplace, emergency contact, reminders and the plan return total were invisible.
--   2. create_customer accepts reminders_enabled.
--   3. Return on an installment sale (the unpaid schedule shrinks, excess is refunded or kept as credit).
--   4. Return time limit (business setting return_window_days) with a manager override permission.
--   5. SKU numbering rules (prefix, digits, start number) and a safe generator that skips taken codes.
--   6. Password confirmation for sensitive actions (verify_password, throttled).
-- Never edit an applied migration: this file only adds to 0001 to 0013.

-- ---------------------------------------------------------------- 1. views that must expose the new columns
alter table public.installment_plans add column if not exists returned_amount numeric(14,2) not null default 0;

drop view if exists public.customers_view;
create view public.customers_view with (security_invoker = true) as
select c.*,
       coalesce(l.balance, 0)::numeric(14,2) as balance,
       l.last_entry
from public.customers c
left join (
  select customer_id, sum(debit - credit) as balance, max(entry_date) as last_entry
  from public.customer_ledger group by customer_id
) l on l.customer_id = c.id;

drop view if exists public.installment_plans_view;
create view public.installment_plans_view with (security_invoker = true) as
select p.*,
       c.name as customer_name,
       c.phone as customer_phone,
       s.invoice_no,
       (p.total_payable - p.paid_amount)::numeric(14,2) as outstanding,
       n.next_due_date,
       n.next_due_amount,
       coalesce(o.overdue_amount, 0)::numeric(14,2) as overdue_amount,
       coalesce(o.overdue_count, 0)::integer as overdue_count,
       coalesce(o.max_days, 0)::integer as overdue_days
from public.installment_plans p
join public.customers c on c.id = p.customer_id
join public.sales s on s.id = p.sale_id
left join lateral (
  select i.due_date as next_due_date, (i.amount - i.paid_amount) as next_due_amount
  from public.installment_items i
  where i.plan_id = p.id and i.status in ('pending','partial')
  order by i.due_date, i.seq limit 1
) n on true
left join lateral (
  select sum(i.amount - i.paid_amount) as overdue_amount, count(*) as overdue_count,
         max(app.today(p.business_id) - i.due_date) as max_days
  from public.installment_items i
  where i.plan_id = p.id and i.status in ('pending','partial') and i.due_date < app.today(p.business_id)
) o on true;

-- ---------------------------------------------------------------- permissions
-- returns.override_window lets a person approve a return after the return period has ended.
create or replace function app.default_permissions(p_role text) returns text[]
language sql immutable as $$
  select case p_role
    when 'manager' then array[
      'dashboard.view','sales.view','sales.create','sales.discount','sales.due','sales.void','returns.create',
      'returns.override_window',
      'customers.view','customers.manage','customers.payment','suppliers.view','suppliers.manage','suppliers.payment',
      'purchases.view','purchases.create','products.view','products.manage','inventory.view','inventory.adjust',
      'expenses.view','expenses.create','expenses.void','reports.view',
      'installments.view','installments.create','installments.collect','installments.reschedule','installments.manage',
      'transfers.view','transfers.manage','purchases.return','inventory.count',
      'cash.view','cash.shift','cash.close_day','accounts.view','accounts.manage','customers.documents']
    when 'cashier' then array[
      'dashboard.view','sales.view','sales.create','sales.due','customers.view','customers.manage',
      'customers.payment','products.view','inventory.view',
      'installments.view','installments.create','installments.collect','cash.view','cash.shift','customers.documents']
    when 'storekeeper' then array[
      'dashboard.view','products.view','products.manage','inventory.view','inventory.adjust',
      'purchases.view','suppliers.view','transfers.view','transfers.manage','inventory.count']
    else array[]::text[]
  end
$$;

insert into public.role_permissions(business_id, role, permission)
select b.id, 'manager', 'returns.override_window' from public.businesses b
on conflict do nothing;

-- ---------------------------------------------------------------- 2. create_customer with reminders_enabled
create or replace function public.create_customer(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; v_id uuid; v_open numeric;
begin
  v_biz := app.require_perm('customers.manage');
  if nullif(trim(coalesce(p->>'name', '')), '') is null then raise exception 'Customer name is required.'; end if;
  begin
    insert into customers(business_id, code, name, phone, alt_phone, email, present_address, permanent_address,
                          nid_number, birth_date, occupation, customer_group, notes,
                          workplace, emergency_contact_name, emergency_contact_phone, reminders_enabled)
    values (v_biz, nullif(p->>'code', ''), trim(p->>'name'), nullif(trim(coalesce(p->>'phone', '')), ''),
            nullif(p->>'alt_phone', ''), nullif(p->>'email', ''), nullif(p->>'present_address', ''),
            nullif(p->>'permanent_address', ''), nullif(p->>'nid_number', ''),
            nullif(p->>'birth_date', '')::date, nullif(p->>'occupation', ''),
            coalesce(nullif(p->>'customer_group', ''), 'regular'), nullif(p->>'notes', ''),
            nullif(p->>'workplace', ''), nullif(p->>'emergency_contact_name', ''), nullif(p->>'emergency_contact_phone', ''),
            coalesce((p->>'reminders_enabled')::boolean, true))
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

-- ---------------------------------------------------------------- 3. return on an installment sale
-- Shrinks the unpaid schedule by the value credited to the plan, latest installments first. Paid installments are
-- never touched. When nothing is left to pay the plan completes, or is cancelled if every item was returned.
create or replace function app.apply_return_to_plan(p_biz uuid, p_sale uuid, p_apply numeric, p_writeoff numeric, p_full boolean)
returns void language plpgsql security definer set search_path = public as $$
declare pl record; it record; v_left numeric; v_take numeric; v_unpaid numeric; v_unpaid_sum numeric; v_open integer;
begin
  select * into pl from installment_plans where sale_id = p_sale and business_id = p_biz for update;
  if not found then return; end if;
  select coalesce(sum(amount - paid_amount), 0) into v_unpaid_sum
  from installment_items where plan_id = pl.id and status in ('pending', 'partial');
  v_left := least(coalesce(p_apply, 0) + coalesce(p_writeoff, 0), v_unpaid_sum);
  update installment_plans set total_payable = total_payable - v_left,
                               returned_amount = returned_amount + coalesce(p_apply, 0)
  where id = pl.id;

  for it in
    select * from installment_items
    where plan_id = pl.id and status in ('pending', 'partial')
    order by due_date desc, seq desc for update
  loop
    exit when v_left <= 0.004;
    v_unpaid := it.amount - it.paid_amount;
    v_take := least(v_unpaid, v_left);
    if v_take >= v_unpaid - 0.004 then
      if it.paid_amount > 0 then
        update installment_items set amount = paid_amount, status = 'paid', paid_at = coalesce(paid_at, now()) where id = it.id;
      else
        update installment_items set status = 'cancelled' where id = it.id;
      end if;
    else
      update installment_items set amount = amount - v_take where id = it.id;
    end if;
    v_left := v_left - v_take;
  end loop;

  select count(*) into v_open from installment_items where plan_id = pl.id and status in ('pending', 'partial');
  if v_open = 0 and pl.status = 'active' then
    if p_full then
      update installment_plans set status = 'cancelled', cancelled_at = now(), cancel_reason = 'All items were returned' where id = pl.id;
    else
      update installment_plans set status = 'completed', completed_at = now() where id = pl.id;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------- 4. create_sales_return: time limit and installment sales
-- Same function as 0008 plus: the return period check, and the installment branch in place of the old block.
create or replace function public.create_sales_return(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; s record; si record; it record; v_ret uuid; v_no text;
  v_q numeric; v_net numeric; v_tax numeric; v_cost numeric; v_cond text; v_bucket text;
  v_total numeric := 0; v_apply numeric := 0; v_refund numeric := 0; v_mode text; v_acc uuid; v_serials text[];
  v_window integer; v_age integer; v_late boolean := false; v_full boolean := false; v_writeoff numeric := 0;
begin
  v_biz := app.require_perm('returns.create');
  select * into s from sales where id = (p->>'sale_id')::uuid and business_id = v_biz for update;
  if not found then raise exception 'Sale not found.'; end if;
  if s.status <> 'completed' then raise exception 'Returns are only possible on completed sales.'; end if;
  if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') = 0 then
    raise exception 'Select at least one item to return.';
  end if;

  select coalesce(case when (settings->>'return_window_days') ~ '^[0-9]+$' then (settings->>'return_window_days')::integer end, 0)
    into v_window from businesses where id = v_biz;
  if v_window > 0 then
    v_age := app.today(v_biz) - (s.sale_date at time zone app.tz(v_biz))::date;
    if v_age > v_window then
      if not app.has_perm('returns.override_window') then
        raise exception 'The return period of % days for % has ended. A manager must approve this return.', v_window, s.invoice_no;
      end if;
      v_late := true;
    end if;
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

  -- Installment sale: when every unit is back, whatever the plan still asks for after the goods credit (the service
  -- charge beyond what the customer paid) is written off, so a returned product never leaves a debt behind.
  if s.sale_type = 'installment' then
    v_full := not exists (select 1 from sale_items where sale_id = s.id and returned_quantity < quantity - 0.0005);
    if v_full then v_writeoff := greatest(round(s.due_amount - v_apply, 2), 0); end if;
  end if;

  if s.customer_id is not null then
    perform app.cust_ledger(v_biz, s.customer_id, 'return', 'Return ' || v_no || ' on ' || s.invoice_no,
                            0, v_total, 'sales_return', v_ret, v_no);
    if v_refund > 0 then
      perform app.cust_ledger(v_biz, s.customer_id, 'refund', 'Refund for ' || v_no, v_refund, 0,
                              'sales_return', v_ret, v_no);
    end if;
    if v_writeoff > 0 then
      perform app.cust_ledger(v_biz, s.customer_id, 'adjustment', 'Balance written off, all items returned (' || v_no || ')',
                              0, v_writeoff, 'sales_return', v_ret, v_no);
    end if;
  end if;
  if v_refund > 0 then
    perform app.acct_txn(v_biz, s.branch_id, v_acc, 'out', v_refund, 'sales_return_refund', v_ret, 'Refund ' || v_no);
  end if;

  update sales_returns set total = v_total, due_adjusted = v_apply, refund_amount = v_refund,
                           refund_account_id = case when v_refund > 0 then v_acc end
  where id = v_ret;
  update sales set returned_amount = returned_amount + v_total,
                   due_amount = greatest(due_amount - v_apply - v_writeoff, 0),
                   payment_status = case when due_amount - v_apply - v_writeoff <= 0.004 then 'paid'
                                         when paid_amount > 0 then 'partial' else 'due' end
  where id = s.id;
  if s.sale_type = 'installment' then
    perform app.apply_return_to_plan(v_biz, s.id, v_apply, v_writeoff, v_full);
  end if;

  perform app.log(v_biz, case when v_late then 'sale.return_override' else 'sale.return' end, 'sales_return', v_ret,
                  jsonb_build_object('return_no', v_no, 'invoice_no', s.invoice_no, 'total', v_total, 'refund', v_refund,
                                     'late', v_late, 'written_off', v_writeoff));
  return jsonb_build_object('id', v_ret, 'return_no', v_no, 'total', v_total, 'due_adjusted', v_apply, 'refund', v_refund,
                            'written_off', v_writeoff, 'late_override', v_late);
end $$;

-- ---------------------------------------------------------------- 5. SKU rules
-- Business settings sku_prefix (letters and digits, default P) and sku_digits (3 to 10, default 6).
create or replace function app.set_product_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_s jsonb; v_pre text; v_digits integer; v_try text;
begin
  if new.sku is null or new.sku = '' then
    select settings into v_s from businesses where id = new.business_id;
    v_pre := coalesce(nullif(left(regexp_replace(upper(coalesce(v_s->>'sku_prefix', '')), '[^A-Z0-9]', '', 'g'), 8), ''), 'P');
    v_digits := least(greatest(coalesce(case when (v_s->>'sku_digits') ~ '^[0-9]+$' then (v_s->>'sku_digits')::integer end, 6), 3), 10);
    loop
      v_try := v_pre || '-' || lpad(app.next_no(new.business_id, 'product_sku')::text, v_digits, '0');
      exit when not exists (select 1 from products where business_id = new.business_id and sku = v_try);
    end loop;
    new.sku := v_try;
  end if;
  if tg_op = 'INSERT' and new.avg_cost = 0 then new.avg_cost := new.purchase_price; end if;
  new.updated_at := now();
  return new;
end $$;

-- The counter can be moved forward, never back, so a number is never issued twice.
create or replace function public.set_sku_start(p_next bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; v_last bigint;
begin
  v_biz := app.require_perm('settings.manage');
  if p_next is null or p_next < 1 then raise exception 'Enter a start number of 1 or more.'; end if;
  select last_value into v_last from doc_counters where business_id = v_biz and doc_type = 'product_sku';
  if v_last is not null and p_next - 1 < v_last then
    raise exception 'The next SKU number must be higher than the last one used (%).', v_last;
  end if;
  insert into doc_counters(business_id, doc_type, last_value) values (v_biz, 'product_sku', p_next - 1)
  on conflict (business_id, doc_type) do update set last_value = excluded.last_value;
  perform app.log(v_biz, 'settings.sku_start', 'business', v_biz, jsonb_build_object('next', p_next));
  return p_next;
end $$;

create or replace function public.sku_counter() returns bigint
language plpgsql security definer set search_path = public as $$
declare v_biz uuid;
begin
  v_biz := app.require_perm('settings.manage');
  return coalesce((select last_value from doc_counters where business_id = v_biz and doc_type = 'product_sku'), 0);
end $$;

-- ---------------------------------------------------------------- 6. password confirmation
create table if not exists public.password_check_failures (
  user_id uuid not null,
  failed_at timestamptz not null default now()
);
create index if not exists password_check_failures_idx on public.password_check_failures(user_id, failed_at);
alter table public.password_check_failures enable row level security;

-- Returns true when the signed-in user's password matches. Five wrong tries in ten minutes lock the check.
-- crypt() comes from pgcrypto, which Supabase installs in the "extensions" schema.
create or replace function public.verify_password(p_password text) returns boolean
language plpgsql security definer set search_path = public, extensions, auth as $$
declare v_hash text; v_fails integer;
begin
  if auth.uid() is null then raise exception 'Sign in first.'; end if;
  select count(*) into v_fails from password_check_failures
  where user_id = auth.uid() and failed_at > now() - interval '10 minutes';
  if v_fails >= 5 then raise exception 'Too many wrong passwords. Try again in 10 minutes.'; end if;
  select encrypted_password into v_hash from auth.users where id = auth.uid();
  if v_hash is null or v_hash = '' or coalesce(p_password, '') = '' then return false; end if;
  if crypt(p_password, v_hash) = v_hash then
    delete from password_check_failures where user_id = auth.uid();
    return true;
  end if;
  insert into password_check_failures(user_id) values (auth.uid());
  return false;
end $$;

-- ---------------------------------------------------------------- privileges (same rules as the end of 0012)
revoke all on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
grant usage on schema app to authenticated;
grant execute on all functions in schema app to authenticated;
grant select on public.customers_view, public.installment_plans_view to authenticated;
