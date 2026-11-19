-- EZ POS - Phase 1 - 0001: tenancy, access control, master data
-- Multi-branch ready: every transactional row carries business_id and branch_id.

create schema if not exists app;

-- ---------------------------------------------------------------- tenancy
create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  logo_url text,
  address text,
  phone text,
  email text,
  website text,
  currency text not null default 'BDT',
  timezone text not null default 'Asia/Dhaka',
  date_format text not null default 'dd MMM yyyy',
  language text not null default 'en',
  settings jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  address text,
  phone text,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index on public.branches(business_id);

create table public.business_members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  email text,
  role text not null check (role in ('owner','manager','cashier','storekeeper')),
  branch_id uuid references public.branches(id) on delete set null,
  employee_code text,
  is_active boolean not null default true,
  joined_on date not null default current_date,
  created_at timestamptz not null default now(),
  unique (user_id)
);
create index on public.business_members(business_id);

create table public.role_permissions (
  business_id uuid not null references public.businesses(id) on delete cascade,
  role text not null check (role in ('manager','cashier','storekeeper')),
  permission text not null,
  primary key (business_id, role, permission)
);

create table public.doc_counters (
  business_id uuid not null references public.businesses(id) on delete cascade,
  doc_type text not null,
  last_value bigint not null default 0,
  primary key (business_id, doc_type)
);

create table public.activity_log (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid,
  action text not null,
  entity_type text,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index on public.activity_log(business_id, created_at desc);

-- ---------------------------------------------------------------- helpers (private schema)
create or replace function app.current_business_id() returns uuid
language sql stable security definer set search_path = public as $$
  select m.business_id from public.business_members m
  where m.user_id = auth.uid() and m.is_active limit 1
$$;

create or replace function app.current_role() returns text
language sql stable security definer set search_path = public as $$
  select m.role from public.business_members m
  where m.user_id = auth.uid() and m.is_active limit 1
$$;

create or replace function app.has_perm(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.business_members m
    where m.user_id = auth.uid() and m.is_active
      and (m.role = 'owner' or exists (
        select 1 from public.role_permissions rp
        where rp.business_id = m.business_id and rp.role = m.role and rp.permission = p))
  )
$$;

create or replace function app.require_perm(p text) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v uuid;
begin
  v := app.current_business_id();
  if v is null then raise exception 'You are not part of a business yet.'; end if;
  if not app.has_perm(p) then raise exception 'You do not have permission for this action (%).', p; end if;
  return v;
end $$;

create or replace function app.next_no(p_business uuid, p_type text) returns bigint
language plpgsql security definer set search_path = public as $$
declare v bigint;
begin
  insert into public.doc_counters(business_id, doc_type, last_value) values (p_business, p_type, 1)
  on conflict (business_id, doc_type) do update set last_value = public.doc_counters.last_value + 1
  returning last_value into v;
  return v;
end $$;

create or replace function app.doc_no(p_business uuid, p_type text, p_default_prefix text) returns text
language plpgsql security definer set search_path = public as $$
declare pre text; n bigint;
begin
  select coalesce(nullif(settings ->> (p_type || '_prefix'), ''), p_default_prefix) into pre
  from public.businesses where id = p_business;
  n := app.next_no(p_business, p_type);
  return pre || '-' || lpad(n::text, 6, '0');
end $$;

create or replace function app.log(p_business uuid, p_action text, p_entity text, p_entity_id uuid, p_details jsonb default '{}')
returns void language sql security definer set search_path = public as $$
  insert into public.activity_log(business_id, user_id, action, entity_type, entity_id, details)
  values (p_business, auth.uid(), p_action, p_entity, p_entity_id, coalesce(p_details, '{}'::jsonb))
$$;

create or replace function app.tz(p_business uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select timezone from public.businesses where id = p_business), 'Asia/Dhaka')
$$;

-- ---------------------------------------------------------------- master data
create table public.units (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  short_name text not null,
  allow_decimal boolean not null default false,
  unique (business_id, name)
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  parent_id uuid references public.categories(id) on delete set null,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index categories_name_uq on public.categories(business_id, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name));

create table public.brands (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  unique (business_id, name)
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  code text,
  name text not null,
  contact_person text,
  phone text,
  alt_phone text,
  email text,
  address text,
  business_type text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index on public.suppliers(business_id, name);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  code text,
  name text not null,
  phone text,
  alt_phone text,
  email text,
  photo_url text,
  present_address text,
  permanent_address text,
  nid_number text,
  birth_date date,
  occupation text,
  customer_group text not null default 'regular'
    check (customer_group in ('regular','wholesale','vip','corporate','custom')),
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index on public.customers(business_id, name);
create unique index customers_phone_uq on public.customers(business_id, phone) where phone is not null and phone <> '';

create table public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  sku text,
  barcode text,
  category_id uuid references public.categories(id) on delete set null,
  brand_id uuid references public.brands(id) on delete set null,
  model text,
  unit_id uuid references public.units(id) on delete set null,
  product_type text not null default 'standard'
    check (product_type in ('standard','variable','service','combo')),
  tracking_type text not null default 'none'
    check (tracking_type in ('none','serial','imei','batch','expiry')),
  track_stock boolean not null default true,
  purchase_price numeric(14,2) not null default 0 check (purchase_price >= 0),
  avg_cost numeric(14,4) not null default 0 check (avg_cost >= 0),
  selling_price numeric(14,2) not null default 0 check (selling_price >= 0),
  wholesale_price numeric(14,2) check (wholesale_price >= 0),
  min_selling_price numeric(14,2) check (min_selling_price >= 0),
  tax_rate numeric(6,2) not null default 0 check (tax_rate >= 0 and tax_rate <= 100),
  warranty_months integer check (warranty_months >= 0),
  description text,
  image_url text,
  supplier_id uuid references public.suppliers(id) on delete set null,
  low_stock_limit numeric(14,3) not null default 0,
  max_stock_limit numeric(14,3),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index products_sku_uq on public.products(business_id, sku) where sku is not null and sku <> '';
create unique index products_barcode_uq on public.products(business_id, barcode) where barcode is not null and barcode <> '';
create index on public.products(business_id, name);
create index on public.products(business_id, category_id);

create table public.payment_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  name text not null,
  account_type text not null check (account_type in ('cash','bank','mfs','card','other')),
  account_no text,
  opening_balance numeric(14,2) not null default 0,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (business_id, name)
);

create table public.account_transactions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  account_id uuid not null references public.payment_accounts(id),
  txn_date timestamptz not null default now(),
  direction text not null check (direction in ('in','out')),
  amount numeric(14,2) not null check (amount > 0),
  source_type text not null,
  source_id uuid,
  description text,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index on public.account_transactions(business_id, txn_date desc);
create index on public.account_transactions(account_id);

create table public.stock_levels (
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity numeric(14,3) not null default 0,
  damaged_quantity numeric(14,3) not null default 0,
  inspection_quantity numeric(14,3) not null default 0,
  primary key (branch_id, product_id)
);
create index on public.stock_levels(business_id, product_id);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  movement_type text not null,
  bucket text not null default 'quantity' check (bucket in ('quantity','damaged','inspection')),
  quantity numeric(14,3) not null,
  unit_cost numeric(14,4) not null default 0,
  reference_type text,
  reference_id uuid,
  note text,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index on public.stock_movements(business_id, created_at desc);
create index on public.stock_movements(product_id, created_at desc);

create table public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  is_active boolean not null default true,
  unique (business_id, name)
);

-- ---------------------------------------------------------------- auto codes
create or replace function app.set_party_code() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.code is null or new.code = '' then
    if tg_table_name = 'customers' then
      new.code := 'C-' || lpad(app.next_no(new.business_id, 'customer_code')::text, 5, '0');
    else
      new.code := 'S-' || lpad(app.next_no(new.business_id, 'supplier_code')::text, 5, '0');
    end if;
  end if;
  return new;
end $$;
create trigger customers_code before insert on public.customers for each row execute function app.set_party_code();
create trigger suppliers_code before insert on public.suppliers for each row execute function app.set_party_code();

create or replace function app.set_product_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.sku is null or new.sku = '' then
    new.sku := 'P-' || lpad(app.next_no(new.business_id, 'product_sku')::text, 6, '0');
  end if;
  if tg_op = 'INSERT' and new.avg_cost = 0 then new.avg_cost := new.purchase_price; end if;
  new.updated_at := now();
  return new;
end $$;
create trigger products_defaults before insert or update on public.products for each row execute function app.set_product_defaults();
