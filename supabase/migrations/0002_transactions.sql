-- EZ POS - Phase 1 - 0002: transactional tables, ledgers, views and row level security

-- ---------------------------------------------------------------- sales
create table public.sales (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  invoice_no text not null,
  customer_id uuid references public.customers(id),
  sale_date timestamptz not null default now(),
  status text not null default 'completed' check (status in ('completed','void')),
  sale_type text not null default 'regular' check (sale_type in ('regular','installment')),
  payment_status text not null default 'paid' check (payment_status in ('paid','partial','due')),
  subtotal numeric(14,2) not null default 0,
  item_discount numeric(14,2) not null default 0,
  invoice_discount numeric(14,2) not null default 0,
  net_amount numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  paid_amount numeric(14,2) not null default 0,
  due_amount numeric(14,2) not null default 0,
  returned_amount numeric(14,2) not null default 0,
  note text,
  cashier_id uuid,
  client_ref uuid,
  void_reason text,
  voided_at timestamptz,
  voided_by uuid,
  created_at timestamptz not null default now(),
  unique (business_id, invoice_no)
);
create unique index sales_client_ref_uq on public.sales(business_id, client_ref) where client_ref is not null;
create index on public.sales(business_id, sale_date desc);
create index on public.sales(customer_id) where customer_id is not null;

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  line_no integer not null default 1,
  product_id uuid not null references public.products(id),
  product_name text not null,
  sku text,
  unit_name text,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null,
  discount numeric(14,2) not null default 0,
  tax_rate numeric(6,2) not null default 0,
  net_amount numeric(14,2) not null,
  tax_amount numeric(14,2) not null default 0,
  line_total numeric(14,2) not null,
  unit_cost numeric(14,4) not null default 0,
  cost_amount numeric(14,2) not null default 0,
  returned_quantity numeric(14,3) not null default 0
);
create index on public.sale_items(sale_id);
create index on public.sale_items(product_id);

create table public.sale_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  account_id uuid not null references public.payment_accounts(id),
  amount numeric(14,2) not null check (amount > 0),
  reference text,
  created_at timestamptz not null default now()
);
create index on public.sale_payments(sale_id);

create table public.customer_ledger (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  entry_date timestamptz not null default now(),
  entry_type text not null check (entry_type in ('opening','sale','payment','return','refund','void','adjustment')),
  description text,
  debit numeric(14,2) not null default 0 check (debit >= 0),
  credit numeric(14,2) not null default 0 check (credit >= 0),
  reference_type text,
  reference_id uuid,
  reference_no text,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index on public.customer_ledger(customer_id, entry_date);
create index on public.customer_ledger(business_id);

create table public.customer_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id),
  customer_id uuid not null references public.customers(id),
  receipt_no text not null,
  amount numeric(14,2) not null check (amount > 0),
  account_id uuid not null references public.payment_accounts(id),
  payment_date timestamptz not null default now(),
  reference text,
  note text,
  status text not null default 'active' check (status in ('active','void')),
  client_ref uuid,
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (business_id, receipt_no)
);
create unique index customer_payments_client_ref_uq on public.customer_payments(business_id, client_ref) where client_ref is not null;
create index on public.customer_payments(customer_id, payment_date desc);

create table public.customer_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  payment_id uuid not null references public.customer_payments(id) on delete cascade,
  sale_id uuid not null references public.sales(id),
  amount numeric(14,2) not null check (amount > 0)
);
create index on public.customer_payment_allocations(sale_id);

create table public.sales_returns (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  return_no text not null,
  sale_id uuid not null references public.sales(id),
  customer_id uuid references public.customers(id),
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
create index on public.sales_returns(business_id, return_date desc);
create index on public.sales_returns(sale_id);

create table public.sales_return_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  return_id uuid not null references public.sales_returns(id) on delete cascade,
  sale_item_id uuid not null references public.sale_items(id),
  product_id uuid not null references public.products(id),
  product_name text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  condition text not null check (condition in ('resellable','damaged','inspection')),
  net_amount numeric(14,2) not null,
  tax_amount numeric(14,2) not null default 0,
  line_total numeric(14,2) not null,
  cost_amount numeric(14,2) not null default 0
);
create index on public.sales_return_items(return_id);

-- ---------------------------------------------------------------- purchases
create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  purchase_no text not null,
  supplier_invoice_no text,
  supplier_id uuid not null references public.suppliers(id),
  purchase_date date not null,
  status text not null default 'received'
    check (status in ('draft','ordered','received','partially_received','cancelled')),
  subtotal numeric(14,2) not null default 0,
  discount numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  other_charges numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  paid_amount numeric(14,2) not null default 0,
  due_amount numeric(14,2) not null default 0,
  note text,
  attachment_url text,
  client_ref uuid,
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (business_id, purchase_no)
);
create unique index purchases_client_ref_uq on public.purchases(business_id, client_ref) where client_ref is not null;
create index on public.purchases(business_id, purchase_date desc);
create index on public.purchases(supplier_id);

create table public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  purchase_id uuid not null references public.purchases(id) on delete cascade,
  line_no integer not null default 1,
  product_id uuid not null references public.products(id),
  product_name text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  received_quantity numeric(14,3) not null default 0,
  unit_cost numeric(14,2) not null,
  discount numeric(14,2) not null default 0,
  line_total numeric(14,2) not null,
  landed_unit_cost numeric(14,4) not null default 0
);
create index on public.purchase_items(purchase_id);

create table public.purchase_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  purchase_id uuid not null references public.purchases(id) on delete cascade,
  account_id uuid not null references public.payment_accounts(id),
  amount numeric(14,2) not null check (amount > 0),
  reference text,
  created_at timestamptz not null default now()
);

create table public.supplier_ledger (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  entry_date timestamptz not null default now(),
  entry_type text not null check (entry_type in ('opening','purchase','payment','return','refund','void','adjustment')),
  description text,
  debit numeric(14,2) not null default 0 check (debit >= 0),
  credit numeric(14,2) not null default 0 check (credit >= 0),
  reference_type text,
  reference_id uuid,
  reference_no text,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index on public.supplier_ledger(supplier_id, entry_date);
create index on public.supplier_ledger(business_id);

create table public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id),
  supplier_id uuid not null references public.suppliers(id),
  payment_no text not null,
  amount numeric(14,2) not null check (amount > 0),
  account_id uuid not null references public.payment_accounts(id),
  payment_date timestamptz not null default now(),
  reference text,
  note text,
  status text not null default 'active' check (status in ('active','void')),
  client_ref uuid,
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (business_id, payment_no)
);
create unique index supplier_payments_client_ref_uq on public.supplier_payments(business_id, client_ref) where client_ref is not null;
create index on public.supplier_payments(supplier_id, payment_date desc);

create table public.supplier_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  payment_id uuid not null references public.supplier_payments(id) on delete cascade,
  purchase_id uuid not null references public.purchases(id),
  amount numeric(14,2) not null check (amount > 0)
);

-- ---------------------------------------------------------------- expenses
create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id),
  category_id uuid references public.expense_categories(id) on delete set null,
  title text not null,
  amount numeric(14,2) not null check (amount > 0),
  expense_date date not null,
  account_id uuid not null references public.payment_accounts(id),
  paid_by text,
  note text,
  receipt_url text,
  status text not null default 'approved' check (status in ('pending','approved','void')),
  is_recurring boolean not null default false,
  recurrence text check (recurrence in ('weekly','monthly','yearly')),
  void_reason text,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index on public.expenses(business_id, expense_date desc);

-- ---------------------------------------------------------------- views (RLS applies to the caller)
create view public.customers_view with (security_invoker = true) as
select c.*,
       coalesce(l.balance, 0)::numeric(14,2) as balance,
       l.last_entry
from public.customers c
left join (
  select customer_id, sum(debit - credit) as balance, max(entry_date) as last_entry
  from public.customer_ledger group by customer_id
) l on l.customer_id = c.id;

create view public.suppliers_view with (security_invoker = true) as
select s.*,
       coalesce(l.balance, 0)::numeric(14,2) as balance,
       l.last_entry
from public.suppliers s
left join (
  select supplier_id, sum(credit - debit) as balance, max(entry_date) as last_entry
  from public.supplier_ledger group by supplier_id
) l on l.supplier_id = s.id;

create view public.accounts_view with (security_invoker = true) as
select a.*,
       (a.opening_balance + coalesce(t.net, 0))::numeric(14,2) as balance
from public.payment_accounts a
left join (
  select account_id, sum(case when direction = 'in' then amount else -amount end) as net
  from public.account_transactions group by account_id
) t on t.account_id = a.id;

-- ---------------------------------------------------------------- row level security
alter table public.businesses enable row level security;
alter table public.doc_counters enable row level security;

create policy businesses_sel on public.businesses for select to authenticated
  using (id = app.current_business_id());
create policy businesses_upd on public.businesses for update to authenticated
  using (id = app.current_business_id() and app.has_perm('settings.manage'))
  with check (id = app.current_business_id());

do $$
declare t text;
begin
  for t in select unnest(array[
    'branches','business_members','role_permissions','units','categories','brands','suppliers','customers',
    'products','payment_accounts','account_transactions','stock_levels','stock_movements','expense_categories',
    'customer_ledger','supplier_ledger','sales','sale_items','sale_payments','sales_returns','sales_return_items',
    'customer_payments','customer_payment_allocations','purchases','purchase_items','purchase_payments',
    'supplier_payments','supplier_payment_allocations','expenses','activity_log'])
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;

  -- Read access: every table is scoped to the business; sensitive ones also need the matching permission.
  for t in select unnest(array[
    'branches','business_members','role_permissions','payment_accounts','expense_categories'])
  loop
    execute format('create policy %I on public.%I for select to authenticated using (business_id = app.current_business_id())', t || '_sel', t);
  end loop;
  for t in select unnest(array[
    'sales:sales.view','sale_items:sales.view','sale_payments:sales.view','sales_returns:sales.view','sales_return_items:sales.view',
    'customers:customers.view','customer_ledger:customers.view','customer_payments:customers.view','customer_payment_allocations:customers.view',
    'suppliers:suppliers.view','supplier_ledger:suppliers.view','supplier_payments:suppliers.view','supplier_payment_allocations:suppliers.view',
    'purchases:purchases.view','purchase_items:purchases.view','purchase_payments:purchases.view',
    'products:products.view','categories:products.view','brands:products.view','units:products.view',
    'stock_levels:inventory.view','stock_movements:inventory.view',
    'expenses:expenses.view','account_transactions:reports.view'])
  loop
    execute format('create policy %I on public.%I for select to authenticated using (business_id = app.current_business_id() and app.has_perm(%L))',
                   split_part(t, ':', 1) || '_sel', split_part(t, ':', 1), split_part(t, ':', 2));
  end loop;
end $$;

create policy activity_log_sel on public.activity_log for select to authenticated
  using (business_id = app.current_business_id() and app.has_perm('users.manage'));

-- catalog (products.manage)
do $$
declare t text;
begin
  for t in select unnest(array['units','categories','brands','products'])
  loop
    execute format('create policy %I on public.%I for insert to authenticated with check (business_id = app.current_business_id() and app.has_perm(''products.manage''))', t || '_ins', t);
    execute format('create policy %I on public.%I for update to authenticated using (business_id = app.current_business_id() and app.has_perm(''products.manage'')) with check (business_id = app.current_business_id())', t || '_upd', t);
    execute format('create policy %I on public.%I for delete to authenticated using (business_id = app.current_business_id() and app.has_perm(''products.manage''))', t || '_del', t);
  end loop;
end $$;

-- parties: inserts go through RPCs (opening balances); updates are direct
create policy customers_upd on public.customers for update to authenticated
  using (business_id = app.current_business_id() and app.has_perm('customers.manage'))
  with check (business_id = app.current_business_id());
create policy suppliers_upd on public.suppliers for update to authenticated
  using (business_id = app.current_business_id() and app.has_perm('suppliers.manage'))
  with check (business_id = app.current_business_id());

-- settings and team
create policy branches_upd on public.branches for update to authenticated
  using (business_id = app.current_business_id() and app.has_perm('settings.manage'))
  with check (business_id = app.current_business_id());
create policy payment_accounts_ins on public.payment_accounts for insert to authenticated
  with check (business_id = app.current_business_id() and app.has_perm('settings.manage'));
create policy payment_accounts_upd on public.payment_accounts for update to authenticated
  using (business_id = app.current_business_id() and app.has_perm('settings.manage'))
  with check (business_id = app.current_business_id());
create policy expense_categories_ins on public.expense_categories for insert to authenticated
  with check (business_id = app.current_business_id() and app.has_perm('expenses.create'));
create policy expense_categories_upd on public.expense_categories for update to authenticated
  using (business_id = app.current_business_id() and app.has_perm('expenses.create'))
  with check (business_id = app.current_business_id());
create policy members_upd on public.business_members for update to authenticated
  using (business_id = app.current_business_id() and app.has_perm('users.manage') and role <> 'owner')
  with check (business_id = app.current_business_id() and role <> 'owner');
create policy role_permissions_ins on public.role_permissions for insert to authenticated
  with check (business_id = app.current_business_id() and app.has_perm('users.manage'));
create policy role_permissions_del on public.role_permissions for delete to authenticated
  using (business_id = app.current_business_id() and app.has_perm('users.manage'));
