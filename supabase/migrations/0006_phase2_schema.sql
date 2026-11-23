-- EZ POS - Phase 2 - 0006: schema for installments, serial/IMEI and batch tracking, stock transfer,
-- purchase return, exchange, cash register and day closing, documents.
-- Applies on top of the Phase 1 migrations 0001 to 0004. Functions follow in 0007 and later.

-- ---------------------------------------------------------------- helpers
create or replace function app.today(p_business uuid) returns date
language sql stable security definer set search_path = public as $$
  select (now() at time zone app.tz(p_business))::date
$$;

create or replace function app.norm_serial(s text) returns text
language sql immutable as $$ select upper(btrim(coalesce(s, ''))) $$;

-- IMEI = 15 digits that satisfy the Luhn check.
create or replace function app.valid_imei(s text) returns boolean
language plpgsql immutable as $$
declare i integer; d integer; total integer := 0;
begin
  if s !~ '^[0-9]{15}$' then return false; end if;
  for i in 1..15 loop
    d := substr(s, 16 - i, 1)::integer;
    if i % 2 = 0 then
      d := d * 2;
      if d > 9 then d := d - 9; end if;
    end if;
    total := total + d;
  end loop;
  return total % 10 = 0;
end $$;

-- ---------------------------------------------------------------- permissions
create or replace function app.default_permissions(p_role text) returns text[]
language sql immutable as $$
  select case p_role
    when 'manager' then array[
      'dashboard.view','sales.view','sales.create','sales.discount','sales.due','sales.void','returns.create',
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

-- Existing businesses receive the new permissions only (earlier custom choices stay untouched).
insert into public.role_permissions(business_id, role, permission)
select b.id, r.role, p
from public.businesses b
cross join (values ('manager'), ('cashier'), ('storekeeper')) as r(role)
cross join lateral unnest(app.default_permissions(r.role)) as p
where p = any (array[
  'installments.view','installments.create','installments.collect','installments.reschedule','installments.manage',
  'transfers.view','transfers.manage','purchases.return','inventory.count',
  'cash.view','cash.shift','cash.close_day','cash.reopen','accounts.view','accounts.manage','customers.documents'])
on conflict do nothing;

-- ---------------------------------------------------------------- column and constraint changes
alter table public.branches add column if not exists kind text not null default 'branch'
  check (kind in ('branch', 'warehouse'));

alter table public.customers add column if not exists workplace text;
alter table public.customers add column if not exists emergency_contact_name text;
alter table public.customers add column if not exists emergency_contact_phone text;
alter table public.customers add column if not exists reminders_enabled boolean not null default true;

alter table public.sales add column if not exists finance_charge numeric(14,2) not null default 0;
alter table public.sales add column if not exists exchange_credit numeric(14,2) not null default 0;
alter table public.sales add column if not exists exchange_of_return_id uuid;

alter table public.sales_returns add column if not exists exchange_sale_id uuid;

alter table public.purchases add column if not exists returned_amount numeric(14,2) not null default 0;
alter table public.purchase_items add column if not exists returned_quantity numeric(14,3) not null default 0;
alter table public.purchase_items add column if not exists batch_no text;
alter table public.purchase_items add column if not exists expiry_date date;

do $$
declare c record;
begin
  for c in
    select con.conname, rel.relname
    from pg_constraint con join pg_class rel on rel.oid = con.conrelid
    where con.contype = 'c' and rel.relnamespace = 'public'::regnamespace
      and ((rel.relname = 'customer_ledger' and pg_get_constraintdef(con.oid) like '%entry_type%')
        or (rel.relname = 'sales_returns' and pg_get_constraintdef(con.oid) like '%refund_mode%'))
  loop
    execute format('alter table public.%I drop constraint %I', c.relname, c.conname);
  end loop;
end $$;

alter table public.customer_ledger add constraint customer_ledger_entry_type_check
  check (entry_type in ('opening','sale','payment','return','refund','void','adjustment','finance_charge'));
alter table public.sales_returns add constraint sales_returns_refund_mode_check
  check (refund_mode in ('cash','credit','exchange'));

-- ---------------------------------------------------------------- serial / IMEI units and batches
create table public.stock_units (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  product_id uuid not null references public.products(id),
  serial_no text not null,
  kind text not null check (kind in ('serial','imei')),
  status text not null default 'in_stock'
    check (status in ('in_stock','sold','in_transit','returned_to_supplier','damaged','inspection','lost')),
  unit_cost numeric(14,4) not null default 0,
  purchase_id uuid references public.purchases(id),
  sale_id uuid references public.sales(id),
  sale_item_id uuid references public.sale_items(id),
  customer_id uuid references public.customers(id),
  sold_at timestamptz,
  warranty_until date,
  transfer_id uuid,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index stock_units_serial_uq on public.stock_units(business_id, product_id, serial_no);
create unique index stock_units_imei_uq on public.stock_units(business_id, serial_no) where kind = 'imei';
create index on public.stock_units(business_id, status);
create index on public.stock_units(product_id, branch_id, status);
create index on public.stock_units(sale_id) where sale_id is not null;

create table public.stock_unit_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  unit_id uuid not null references public.stock_units(id) on delete cascade,
  event_type text not null,
  from_status text,
  to_status text,
  reference_type text,
  reference_id uuid,
  note text,
  created_by uuid,
  created_at timestamptz not null default clock_timestamp()
);
create index on public.stock_unit_events(unit_id, created_at);

create table public.stock_batches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  product_id uuid not null references public.products(id),
  batch_no text not null,
  expiry_date date,
  quantity_received numeric(14,3) not null,
  quantity_left numeric(14,3) not null check (quantity_left >= 0),
  unit_cost numeric(14,4) not null default 0,
  purchase_id uuid references public.purchases(id),
  created_at timestamptz not null default clock_timestamp()
);
create index on public.stock_batches(product_id, branch_id, expiry_date);
create index on public.stock_batches(business_id, expiry_date) where quantity_left > 0;

create table public.sale_item_batches (
  seq bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_item_id uuid not null references public.sale_items(id) on delete cascade,
  batch_id uuid not null references public.stock_batches(id),
  quantity numeric(14,3) not null,
  returned_quantity numeric(14,3) not null default 0
);
create index on public.sale_item_batches(sale_item_id);

-- ---------------------------------------------------------------- installments
create table public.installment_plans (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  sale_id uuid not null unique references public.sales(id),
  customer_id uuid not null references public.customers(id),
  plan_no text not null,
  status text not null default 'active' check (status in ('active','completed','cancelled')),
  product_total numeric(14,2) not null,
  down_payment numeric(14,2) not null default 0,
  financed_amount numeric(14,2) not null,
  service_charge numeric(14,2) not null default 0,
  total_payable numeric(14,2) not null,
  installment_count integer not null check (installment_count > 0),
  frequency text not null check (frequency in ('weekly','biweekly','monthly','custom')),
  first_due_date date not null,
  paid_amount numeric(14,2) not null default 0,
  terms text,
  reminders_enabled boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  unique (business_id, plan_no)
);
create index on public.installment_plans(business_id, status);
create index on public.installment_plans(customer_id);

create table public.installment_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  plan_id uuid not null references public.installment_plans(id) on delete cascade,
  seq integer not null,
  due_date date not null,
  original_due_date date not null,
  amount numeric(14,2) not null check (amount > 0),
  paid_amount numeric(14,2) not null default 0,
  status text not null default 'pending' check (status in ('pending','partial','paid','cancelled')),
  paid_at timestamptz,
  unique (plan_id, seq)
);
create index on public.installment_items(business_id, due_date) where status in ('pending','partial');

create table public.installment_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id),
  plan_id uuid not null references public.installment_plans(id),
  customer_id uuid not null references public.customers(id),
  receipt_no text not null,
  amount numeric(14,2) not null check (amount > 0),
  allocated_amount numeric(14,2) not null default 0,
  account_id uuid not null references public.payment_accounts(id),
  payment_date timestamptz not null default now(),
  reference text,
  note text,
  client_ref uuid,
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (business_id, receipt_no)
);
create unique index installment_payments_client_ref_uq on public.installment_payments(business_id, client_ref) where client_ref is not null;
create index on public.installment_payments(plan_id, payment_date desc);

create table public.installment_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  payment_id uuid not null references public.installment_payments(id) on delete cascade,
  item_id uuid not null references public.installment_items(id),
  amount numeric(14,2) not null check (amount > 0)
);
create index on public.installment_payment_allocations(item_id);

create table public.installment_date_changes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  plan_id uuid not null references public.installment_plans(id) on delete cascade,
  item_id uuid not null references public.installment_items(id) on delete cascade,
  old_date date not null,
  new_date date not null,
  reason text not null,
  changed_by uuid,
  changed_at timestamptz not null default now()
);

create table public.installment_guarantors (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  plan_id uuid not null references public.installment_plans(id) on delete cascade,
  kind text not null default 'guarantor' check (kind in ('guarantor','reference','emergency')),
  name text not null,
  phone text,
  address text,
  relationship text,
  nid_number text
);
create index on public.installment_guarantors(plan_id);

create table public.installment_followups (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  plan_id uuid not null references public.installment_plans(id) on delete cascade,
  item_id uuid references public.installment_items(id) on delete set null,
  customer_id uuid not null references public.customers(id),
  due_date date not null,
  note text not null,
  status text not null default 'open' check (status in ('open','done')),
  assigned_to uuid,
  outcome text,
  created_by uuid,
  created_at timestamptz not null default now(),
  done_at timestamptz,
  done_by uuid
);
create index on public.installment_followups(business_id, status, due_date);

create table public.installment_reminder_log (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  plan_id uuid not null references public.installment_plans(id) on delete cascade,
  item_id uuid references public.installment_items(id) on delete set null,
  customer_id uuid not null references public.customers(id),
  kind text not null check (kind in ('before','due','overdue','manual')),
  channel text not null check (channel in ('whatsapp','sms','call','in_app','other')),
  message text,
  sent_by uuid,
  sent_at timestamptz not null default now()
);
create index on public.installment_reminder_log(business_id, sent_at desc);
create index on public.installment_reminder_log(customer_id, sent_at desc);

-- ---------------------------------------------------------------- stock transfer
create table public.stock_transfers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  transfer_no text not null,
  from_branch_id uuid not null references public.branches(id),
  to_branch_id uuid not null references public.branches(id),
  status text not null default 'requested'
    check (status in ('requested','in_transit','partially_received','received','cancelled')),
  note text,
  requested_by uuid,
  requested_at timestamptz not null default now(),
  dispatched_by uuid,
  dispatched_at timestamptz,
  received_by uuid,
  received_at timestamptz,
  cancel_reason text,
  client_ref uuid,
  check (from_branch_id <> to_branch_id),
  unique (business_id, transfer_no)
);
create unique index stock_transfers_client_ref_uq on public.stock_transfers(business_id, client_ref) where client_ref is not null;
create index on public.stock_transfers(business_id, requested_at desc);

create table public.stock_transfer_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  transfer_id uuid not null references public.stock_transfers(id) on delete cascade,
  product_id uuid not null references public.products(id),
  product_name text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  sent_quantity numeric(14,3) not null default 0,
  received_quantity numeric(14,3) not null default 0,
  unit_cost numeric(14,4) not null default 0,
  serials text[] not null default '{}',
  received_serials text[] not null default '{}',
  batches jsonb not null default '[]'::jsonb,
  shortage_reason text
);
create index on public.stock_transfer_items(transfer_id);

-- ---------------------------------------------------------------- purchase return
create table public.purchase_returns (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  return_no text not null,
  purchase_id uuid not null references public.purchases(id),
  supplier_id uuid not null references public.suppliers(id),
  return_date timestamptz not null default now(),
  reason text,
  refund_mode text not null check (refund_mode in ('cash','credit')),
  total numeric(14,2) not null default 0,
  due_adjusted numeric(14,2) not null default 0,
  refund_amount numeric(14,2) not null default 0,
  refund_account_id uuid references public.payment_accounts(id),
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (business_id, return_no)
);
create index on public.purchase_returns(business_id, return_date desc);
create index on public.purchase_returns(purchase_id);

create table public.purchase_return_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  return_id uuid not null references public.purchase_returns(id) on delete cascade,
  purchase_item_id uuid not null references public.purchase_items(id),
  product_id uuid not null references public.products(id),
  product_name text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  line_total numeric(14,2) not null,
  serials text[] not null default '{}'
);
create index on public.purchase_return_items(return_id);

-- ---------------------------------------------------------------- physical stock count
create table public.stock_counts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  count_no text not null,
  status text not null default 'draft' check (status in ('draft','completed')),
  note text,
  created_by uuid,
  created_at timestamptz not null default now(),
  completed_by uuid,
  completed_at timestamptz,
  unique (business_id, count_no)
);

create table public.stock_count_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  count_id uuid not null references public.stock_counts(id) on delete cascade,
  product_id uuid not null references public.products(id),
  product_name text not null,
  system_quantity numeric(14,3) not null default 0,
  counted_quantity numeric(14,3) not null,
  difference numeric(14,3) not null default 0,
  reason text,
  unique (count_id, product_id)
);

-- ---------------------------------------------------------------- cash register, accounts, day closing
create table public.cash_registers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (business_id, branch_id, name)
);

create table public.register_shifts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  register_id uuid not null references public.cash_registers(id),
  shift_no text not null,
  opened_by uuid not null,
  opened_by_name text,
  opened_at timestamptz not null default clock_timestamp(),
  opening_cash numeric(14,2) not null default 0 check (opening_cash >= 0),
  status text not null default 'open' check (status in ('open','closed')),
  closed_by uuid,
  closed_at timestamptz,
  expected_cash numeric(14,2),
  counted_cash numeric(14,2),
  difference numeric(14,2),
  difference_reason text,
  denominations jsonb,
  summary jsonb,
  note text,
  unique (business_id, shift_no)
);
create unique index register_shifts_open_user_uq on public.register_shifts(business_id, opened_by) where status = 'open';
create unique index register_shifts_open_register_uq on public.register_shifts(register_id) where status = 'open';
create index on public.register_shifts(business_id, opened_at desc);

create table public.account_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id),
  account_id uuid not null references public.payment_accounts(id),
  to_account_id uuid references public.payment_accounts(id),
  entry_type text not null check (entry_type in ('deposit','withdrawal','transfer')),
  amount numeric(14,2) not null check (amount > 0),
  entry_date timestamptz not null default clock_timestamp(),
  reference text,
  note text,
  shift_id uuid references public.register_shifts(id),
  created_by uuid,
  created_at timestamptz not null default now(),
  check (entry_type <> 'transfer' or (to_account_id is not null and to_account_id <> account_id))
);
create index on public.account_entries(business_id, entry_date desc);
create index on public.account_entries(account_id, entry_date desc);

create table public.day_closings (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  closing_date date not null,
  status text not null default 'closed' check (status in ('closed','reopened')),
  opening_cash numeric(14,2) not null default 0,
  expected_cash numeric(14,2) not null default 0,
  counted_cash numeric(14,2) not null default 0,
  difference numeric(14,2) not null default 0,
  difference_reason text,
  denominations jsonb,
  summary jsonb not null default '{}'::jsonb,
  note text,
  closed_by uuid,
  closed_by_name text,
  closed_at timestamptz not null default now(),
  reopened_by uuid,
  reopened_at timestamptz,
  reopen_reason text
);
create unique index day_closings_closed_uq on public.day_closings(business_id, branch_id, closing_date) where status = 'closed';
create index on public.day_closings(business_id, closing_date desc);

-- ---------------------------------------------------------------- documents (NID, agreements, bills, receipts)
create table public.documents (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  entity_type text not null check (entity_type in ('customer','supplier','installment','purchase','expense','guarantor')),
  entity_id uuid not null,
  doc_type text not null default 'other',
  storage_path text not null,
  file_name text,
  note text,
  uploaded_by uuid,
  created_at timestamptz not null default now()
);
create index on public.documents(business_id, entity_type, entity_id);

-- ---------------------------------------------------------------- views
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

create view public.installment_items_view with (security_invoker = true) as
select i.*,
       (i.amount - i.paid_amount)::numeric(14,2) as remaining,
       p.plan_no, p.sale_id, p.customer_id, p.status as plan_status, p.reminders_enabled as plan_reminders,
       p.branch_id,
       c.name as customer_name, c.phone as customer_phone, c.reminders_enabled as customer_reminders,
       greatest(app.today(i.business_id) - i.due_date, 0)::integer as days_overdue,
       (i.status in ('pending','partial') and i.due_date < app.today(i.business_id)) as is_overdue
from public.installment_items i
join public.installment_plans p on p.id = i.plan_id
join public.customers c on c.id = p.customer_id;

-- ---------------------------------------------------------------- row level security
do $$
declare t text;
begin
  for t in select unnest(array[
    'stock_units','stock_unit_events','stock_batches','sale_item_batches',
    'installment_plans','installment_items','installment_payments','installment_payment_allocations',
    'installment_date_changes','installment_guarantors','installment_followups','installment_reminder_log',
    'stock_transfers','stock_transfer_items','purchase_returns','purchase_return_items',
    'stock_counts','stock_count_items','cash_registers','register_shifts','account_entries','day_closings','documents'])
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;

  for t in select unnest(array[
    'stock_units:inventory.view','stock_unit_events:inventory.view','stock_batches:inventory.view','sale_item_batches:inventory.view',
    'installment_plans:installments.view','installment_items:installments.view','installment_payments:installments.view',
    'installment_payment_allocations:installments.view','installment_date_changes:installments.view',
    'installment_guarantors:installments.view','installment_followups:installments.view','installment_reminder_log:installments.view',
    'stock_transfers:transfers.view','stock_transfer_items:transfers.view',
    'purchase_returns:purchases.view','purchase_return_items:purchases.view',
    'stock_counts:inventory.view','stock_count_items:inventory.view',
    'cash_registers:cash.view','day_closings:cash.view'])
  loop
    execute format('create policy %I on public.%I for select to authenticated using (business_id = app.current_business_id() and app.has_perm(%L))',
                   split_part(t, ':', 1) || '_sel', split_part(t, ':', 1), split_part(t, ':', 2));
  end loop;
end $$;

-- Cashiers see their own shifts; people who can close the day see all of them.
create policy register_shifts_sel on public.register_shifts for select to authenticated
  using (business_id = app.current_business_id() and app.has_perm('cash.view')
         and (opened_by = auth.uid() or app.has_perm('cash.close_day')));

create policy account_entries_sel on public.account_entries for select to authenticated
  using (business_id = app.current_business_id() and (app.has_perm('accounts.view') or app.has_perm('cash.view')));

-- The account statement needs the transaction log for people with accounts.view (policies are OR-ed).
create policy account_transactions_sel_accounts on public.account_transactions for select to authenticated
  using (business_id = app.current_business_id() and app.has_perm('accounts.view'));

create policy documents_sel on public.documents for select to authenticated
  using (business_id = app.current_business_id() and (
    (entity_type in ('customer','guarantor') and app.has_perm('customers.documents'))
    or (entity_type = 'supplier' and app.has_perm('suppliers.view'))
    or (entity_type = 'installment' and app.has_perm('installments.view'))
    or (entity_type = 'purchase' and app.has_perm('purchases.view'))
    or (entity_type = 'expense' and app.has_perm('expenses.view'))));
