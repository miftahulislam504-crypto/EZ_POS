-- EZ POS - Phase 1 - 0004: dashboard, reports, summaries and grants
-- Reporting rules (see docs/ACCOUNTING_RULES.md):
--   Sales          = sum of completed sales totals (tax included); Returns are shown separately.
--   Revenue ex tax = sale line net_amount (after discounts) minus returned net_amount.
--   COGS           = sale line cost_amount (average cost snapshot at sale time) minus returned cost_amount.
--   Gross profit   = Revenue ex tax - COGS.   Net profit = Gross profit - approved expenses.
--   Customer due   = sum of positive customer ledger balances (debit - credit).
--   Supplier payable = sum of positive supplier ledger balances (credit - debit).
--   Stock value    = positive on-hand quantity x average cost.

create or replace function public.stock_report(
  p_branch uuid default null, p_filter text default 'all', p_search text default null,
  p_limit integer default 500, p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_biz uuid; v jsonb; v_q text;
begin
  v_biz := app.require_perm('inventory.view');
  v_q := nullif(trim(coalesce(p_search, '')), '');
  select coalesce(jsonb_agg(r order by r->>'name'), '[]'::jsonb) into v from (
    select jsonb_build_object(
      'product_id', x.id, 'name', x.name, 'sku', x.sku, 'barcode', x.barcode, 'image_url', x.image_url,
      'category', x.category, 'unit', x.unit, 'quantity', x.q, 'damaged', x.dmg, 'inspection', x.insp,
      'avg_cost', x.avg_cost, 'value', round(greatest(x.q, 0) * x.avg_cost, 2),
      'low_limit', x.low_stock_limit,
      'status', case when x.q <= 0 then 'out' when x.low_stock_limit > 0 and x.q <= x.low_stock_limit then 'low' else 'ok' end
    ) as r
    from (
      select p.id, p.name, p.sku, p.barcode, p.image_url, p.avg_cost, p.low_stock_limit,
             c.name as category, u.short_name as unit,
             coalesce(sum(sl.quantity), 0) as q,
             coalesce(sum(sl.damaged_quantity), 0) as dmg,
             coalesce(sum(sl.inspection_quantity), 0) as insp
      from products p
      left join categories c on c.id = p.category_id
      left join units u on u.id = p.unit_id
      left join stock_levels sl on sl.product_id = p.id and (p_branch is null or sl.branch_id = p_branch)
      where p.business_id = v_biz and p.is_active and p.track_stock
        and (v_q is null or p.name ilike '%' || v_q || '%' or p.sku ilike '%' || v_q || '%' or p.barcode ilike '%' || v_q || '%')
      group by p.id, c.name, u.short_name
    ) x
    where case p_filter
            when 'low' then x.q > 0 and x.low_stock_limit > 0 and x.q <= x.low_stock_limit
            when 'out' then x.q <= 0
            when 'attention' then x.q <= 0 or (x.low_stock_limit > 0 and x.q <= x.low_stock_limit)
            else true end
    order by x.name
    limit greatest(p_limit, 1) offset greatest(p_offset, 0)
  ) t;
  return v;
end $$;

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
  where business_id = v_biz and source_type in ('sale_payment', 'customer_payment', 'sale_void')
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

create or replace function public.sales_trend(p_from date, p_to date, p_branch uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_biz uuid; v_tz text; v_can boolean; v jsonb;
begin
  v_biz := app.require_perm('dashboard.view');
  v_can := app.has_perm('reports.view');
  v_tz := app.tz(v_biz);
  if p_to - p_from > 400 then raise exception 'Date range is too long.'; end if;
  with days as (select generate_series(p_from, p_to, interval '1 day')::date as day),
  s as (
    select (sale_date at time zone v_tz)::date as day, sum(total) as total, count(*) as cnt
    from sales where business_id = v_biz and status = 'completed' and (p_branch is null or branch_id = p_branch)
      and (sale_date at time zone v_tz)::date between p_from and p_to group by 1),
  sp as (
    select (sa.sale_date at time zone v_tz)::date as day, sum(si.net_amount - si.cost_amount) as profit
    from sale_items si join sales sa on sa.id = si.sale_id
    where sa.business_id = v_biz and sa.status = 'completed' and (p_branch is null or sa.branch_id = p_branch)
      and (sa.sale_date at time zone v_tz)::date between p_from and p_to group by 1),
  rp as (
    select (r.return_date at time zone v_tz)::date as day, sum(ri.net_amount - ri.cost_amount) as profit
    from sales_return_items ri join sales_returns r on r.id = ri.return_id
    where r.business_id = v_biz and (p_branch is null or r.branch_id = p_branch)
      and (r.return_date at time zone v_tz)::date between p_from and p_to group by 1)
  select coalesce(jsonb_agg(jsonb_build_object(
      'day', d.day, 'sales', coalesce(s.total, 0), 'invoices', coalesce(s.cnt, 0),
      'profit', case when v_can then coalesce(sp.profit, 0) - coalesce(rp.profit, 0) end) order by d.day), '[]'::jsonb)
  into v
  from days d left join s on s.day = d.day left join sp on sp.day = d.day left join rp on rp.day = d.day;
  return v;
end $$;

create or replace function public.top_products(p_from date, p_to date, p_branch uuid default null, p_limit integer default 5)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_biz uuid; v_tz text; v jsonb;
begin
  v_biz := app.require_perm('dashboard.view');
  v_tz := app.tz(v_biz);
  select coalesce(jsonb_agg(x order by (x->>'revenue')::numeric desc), '[]'::jsonb) into v from (
    select jsonb_build_object('product_id', si.product_id, 'name', max(si.product_name),
             'quantity', sum(si.quantity - si.returned_quantity),
             'revenue', round(sum(si.net_amount * (si.quantity - si.returned_quantity) / si.quantity), 2)) as x
    from sale_items si join sales s on s.id = si.sale_id
    where s.business_id = v_biz and s.status = 'completed' and (p_branch is null or s.branch_id = p_branch)
      and (s.sale_date at time zone v_tz)::date between p_from and p_to
    group by si.product_id
    having sum(si.quantity - si.returned_quantity) > 0
    order by 1 desc
    limit greatest(p_limit, 1)) t;
  return v;
end $$;

create or replace function public.top_categories(p_from date, p_to date, p_branch uuid default null, p_limit integer default 5)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_biz uuid; v_tz text; v jsonb;
begin
  v_biz := app.require_perm('dashboard.view');
  v_tz := app.tz(v_biz);
  select coalesce(jsonb_agg(x order by (x->>'revenue')::numeric desc), '[]'::jsonb) into v from (
    select jsonb_build_object('name', coalesce(c.name, 'Uncategorised'),
             'quantity', sum(si.quantity - si.returned_quantity),
             'revenue', round(sum(si.net_amount * (si.quantity - si.returned_quantity) / si.quantity), 2)) as x
    from sale_items si
    join sales s on s.id = si.sale_id
    join products p on p.id = si.product_id
    left join categories c on c.id = p.category_id
    where s.business_id = v_biz and s.status = 'completed' and (p_branch is null or s.branch_id = p_branch)
      and (s.sale_date at time zone v_tz)::date between p_from and p_to
    group by c.name
    order by sum(si.net_amount * (si.quantity - si.returned_quantity) / si.quantity) desc
    limit greatest(p_limit, 1)) t;
  return v;
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
           sum(greatest(sa.total - coalesce(pp.paid, 0), 0)) as credit_given
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
    where business_id = v_biz and source_type in ('sale_payment', 'customer_payment', 'sale_void')
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
      and t.source_type in ('sale_payment', 'customer_payment', 'sale_void', 'sales_return_refund')
      and (t.txn_date at time zone v_tz)::date between p_from and p_to
    group by a.name having sum(case when t.direction = 'in' then t.amount else -t.amount end) <> 0) m;

  return jsonb_build_object('rows', v_rows, 'methods', v_methods);
end $$;

create or replace function public.customer_summary(p_customer uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_biz uuid; v_tz text; v_today date;
begin
  v_biz := app.require_perm('customers.view');
  if not exists (select 1 from customers where id = p_customer and business_id = v_biz) then
    raise exception 'Customer not found.';
  end if;
  v_tz := app.tz(v_biz);
  v_today := (now() at time zone v_tz)::date;
  return jsonb_build_object(
    'total_purchase', coalesce((select sum(total) from sales where business_id = v_biz and customer_id = p_customer and status = 'completed'), 0),
    'total_returns', coalesce((select sum(total) from sales_returns where business_id = v_biz and customer_id = p_customer), 0),
    'total_paid', coalesce((select sum(credit) from customer_ledger where customer_id = p_customer and entry_type = 'payment'), 0)
                  - coalesce((select sum(debit) from customer_ledger where customer_id = p_customer and entry_type = 'void'), 0),
    'balance', coalesce((select sum(debit - credit) from customer_ledger where customer_id = p_customer), 0),
    'last_sale', (select max(sale_date) from sales where business_id = v_biz and customer_id = p_customer and status = 'completed'),
    'last_payment', (select max(entry_date) from customer_ledger where customer_id = p_customer and entry_type = 'payment'),
    'open_invoices', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'invoice_no', invoice_no, 'sale_date', sale_date, 'total', total,
               'due', due_amount, 'age_days', v_today - (sale_date at time zone v_tz)::date) order by sale_date)
      from sales where business_id = v_biz and customer_id = p_customer and status = 'completed' and due_amount > 0), '[]'::jsonb));
end $$;

create or replace function public.supplier_summary(p_supplier uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_biz uuid; v_tz text; v_today date;
begin
  v_biz := app.require_perm('suppliers.view');
  if not exists (select 1 from suppliers where id = p_supplier and business_id = v_biz) then
    raise exception 'Supplier not found.';
  end if;
  v_tz := app.tz(v_biz);
  v_today := (now() at time zone v_tz)::date;
  return jsonb_build_object(
    'total_purchase', coalesce((select sum(total) from purchases where business_id = v_biz and supplier_id = p_supplier and status = 'received'), 0),
    'total_paid', coalesce((select sum(debit) from supplier_ledger where supplier_id = p_supplier and entry_type = 'payment'), 0),
    'balance', coalesce((select sum(credit - debit) from supplier_ledger where supplier_id = p_supplier), 0),
    'last_purchase', (select max(purchase_date) from purchases where business_id = v_biz and supplier_id = p_supplier),
    'last_payment', (select max(entry_date) from supplier_ledger where supplier_id = p_supplier and entry_type = 'payment'),
    'open_purchases', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'purchase_no', purchase_no, 'purchase_date', purchase_date, 'total', total,
               'due', due_amount, 'age_days', v_today - purchase_date) order by purchase_date)
      from purchases where business_id = v_biz and supplier_id = p_supplier and status = 'received' and due_amount > 0), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------- privileges
revoke all on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
grant usage on schema app to authenticated;
grant execute on all functions in schema app to authenticated;
alter default privileges in schema public revoke execute on functions from public, anon;
