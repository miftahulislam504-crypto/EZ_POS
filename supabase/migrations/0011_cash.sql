-- EZ POS - Phase 2 - 0011: cash registers, cashier shifts, cash in/out, deposits, withdrawals, transfers,
-- account statements and day closing.
--
-- Rules (docs/ACCOUNTING_RULES.md):
--   * A shift's expected cash = opening cash + every cash-account movement made by that cashier in the branch
--     between opening and closing. Shift differences are recorded for review only.
--   * A day cannot be closed while any cashier shift of that branch is still open (business rule 15).
--   * Closing a day compares the counted cash with the system cash balance and posts the difference as a
--     "cash_difference" movement, so the books match the drawer afterwards.

create or replace function app.account_balance(p_account uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select a.opening_balance
         + coalesce((select sum(case direction when 'in' then amount else -amount end)
                     from account_transactions where account_id = a.id), 0)
  from payment_accounts a where a.id = p_account
$$;

create or replace function app.ensure_register(p_biz uuid, p_branch uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  select id into v from cash_registers where business_id = p_biz and branch_id = p_branch and is_active order by created_at limit 1;
  if v is null then
    insert into cash_registers(business_id, branch_id, name) values (p_biz, p_branch, 'Counter 1')
    on conflict (business_id, branch_id, name) do update set is_active = true
    returning id into v;
  end if;
  return v;
end $$;

-- Payload: {id?, branch_id?, name, is_active?}
create or replace function public.save_register(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; v_id uuid := nullif(p->>'id', '')::uuid; v_branch uuid;
begin
  v_biz := app.require_perm('settings.manage');
  if nullif(trim(coalesce(p->>'name', '')), '') is null then raise exception 'Enter a counter name.'; end if;
  if v_id is null then
    v_branch := app.resolve_branch(v_biz, nullif(p->>'branch_id', '')::uuid);
    insert into cash_registers(business_id, branch_id, name) values (v_biz, v_branch, trim(p->>'name')) returning id into v_id;
  else
    update cash_registers set name = trim(p->>'name'), is_active = coalesce((p->>'is_active')::boolean, is_active)
    where id = v_id and business_id = v_biz;
    if not found then raise exception 'Counter not found.'; end if;
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------- summary of cash movements in a window
create or replace function app.cash_window(
  p_biz uuid, p_branch uuid, p_from timestamptz, p_to timestamptz, p_user uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_src jsonb; v_in numeric; v_out numeric; v_non jsonb; v_sales jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('source_type', source_type, 'direction', direction, 'amount', amt, 'count', n)
                            order by direction desc, source_type), '[]'::jsonb),
         coalesce(sum(amt) filter (where direction = 'in'), 0), coalesce(sum(amt) filter (where direction = 'out'), 0)
  into v_src, v_in, v_out
  from (
    select t.source_type, t.direction, sum(t.amount) as amt, count(*) as n
    from account_transactions t join payment_accounts a on a.id = t.account_id
    where t.business_id = p_biz and a.account_type = 'cash' and t.branch_id = p_branch
      and t.txn_date >= p_from and t.txn_date < p_to and (p_user is null or t.created_by = p_user)
    group by t.source_type, t.direction) x;

  select coalesce(jsonb_agg(jsonb_build_object('account', name, 'type', account_type, 'in', i, 'out', o) order by name), '[]'::jsonb)
  into v_non
  from (
    select a.name, a.account_type,
           coalesce(sum(t.amount) filter (where t.direction = 'in'), 0) as i,
           coalesce(sum(t.amount) filter (where t.direction = 'out'), 0) as o
    from account_transactions t join payment_accounts a on a.id = t.account_id
    where t.business_id = p_biz and a.account_type <> 'cash' and t.branch_id = p_branch
      and t.txn_date >= p_from and t.txn_date < p_to and (p_user is null or t.created_by = p_user)
    group by a.name, a.account_type) y;

  select jsonb_build_object('count', count(*), 'total', coalesce(sum(total), 0))
  into v_sales
  from sales
  where business_id = p_biz and branch_id = p_branch and status = 'completed'
    and sale_date >= p_from and sale_date < p_to and (p_user is null or cashier_id = p_user);

  return jsonb_build_object('by_source', v_src, 'cash_in', v_in, 'cash_out', v_out, 'net_cash', v_in - v_out,
                            'non_cash', v_non, 'sales', v_sales);
end $$;

-- ---------------------------------------------------------------- shifts
-- Payload: {register_id?, opening_cash, note?}
create or replace function public.open_shift(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; v_reg uuid; r record; v_no text; v_id uuid; v_open numeric; v_name text; u record;
begin
  v_biz := app.require_perm('cash.shift');
  if exists (select 1 from register_shifts where business_id = v_biz and opened_by = auth.uid() and status = 'open') then
    raise exception 'You already have an open shift. Close it before opening a new one.';
  end if;
  v_open := round(coalesce((p->>'opening_cash')::numeric, 0), 2);
  if v_open < 0 then raise exception 'Opening cash cannot be negative.'; end if;
  v_reg := nullif(p->>'register_id', '')::uuid;
  if v_reg is null then v_reg := app.ensure_register(v_biz, app.resolve_branch(v_biz, null)); end if;
  select * into r from cash_registers where id = v_reg and business_id = v_biz and is_active;
  if not found then raise exception 'Counter not found.'; end if;
  select s.opened_by_name into u from register_shifts s where s.register_id = r.id and s.status = 'open';
  if found then raise exception 'This counter is already open (%).', coalesce(u.opened_by_name, 'another cashier'); end if;
  select full_name into v_name from business_members where business_id = v_biz and user_id = auth.uid();
  v_no := app.doc_no(v_biz, 'shift', 'SFT');
  insert into register_shifts(business_id, branch_id, register_id, shift_no, opened_by, opened_by_name, opening_cash, note)
  values (v_biz, r.branch_id, r.id, v_no, auth.uid(), v_name, v_open, nullif(p->>'note', ''))
  returning id into v_id;
  perform app.log(v_biz, 'shift.open', 'register_shift', v_id, jsonb_build_object('shift_no', v_no, 'opening_cash', v_open));
  return jsonb_build_object('id', v_id, 'shift_no', v_no);
end $$;

create or replace function public.shift_summary(p_shift uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_biz uuid; sh record; w jsonb; v_to timestamptz;
begin
  v_biz := app.require_perm('cash.view');
  select * into sh from register_shifts where id = p_shift and business_id = v_biz;
  if not found then raise exception 'Shift not found.'; end if;
  if sh.opened_by <> auth.uid() and not app.has_perm('cash.close_day') then raise exception 'You can only view your own shift.'; end if;
  if sh.status = 'closed' and sh.summary is not null then return sh.summary; end if;
  v_to := coalesce(sh.closed_at, clock_timestamp());
  w := app.cash_window(v_biz, sh.branch_id, sh.opened_at, v_to + interval '1 millisecond', sh.opened_by);
  return w || jsonb_build_object('opening_cash', sh.opening_cash, 'expected_cash', sh.opening_cash + (w->>'net_cash')::numeric,
                                 'shift_id', sh.id, 'shift_no', sh.shift_no);
end $$;

-- Payload: {shift_id, counted_cash, difference_reason?, denominations?: {note: count}, note?}
create or replace function public.close_shift(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; sh record; w jsonb; v_exp numeric; v_cnt numeric; v_diff numeric; v_now timestamptz := clock_timestamp();
begin
  v_biz := app.require_perm('cash.shift');
  select * into sh from register_shifts where id = (p->>'shift_id')::uuid and business_id = v_biz for update;
  if not found then raise exception 'Shift not found.'; end if;
  if sh.status <> 'open' then raise exception 'This shift is already closed.'; end if;
  if sh.opened_by <> auth.uid() and not app.has_perm('cash.close_day') then
    raise exception 'Only the cashier or a manager can close this shift.';
  end if;
  v_cnt := round((p->>'counted_cash')::numeric, 2);
  if v_cnt is null or v_cnt < 0 then raise exception 'Enter the counted cash.'; end if;
  w := app.cash_window(v_biz, sh.branch_id, sh.opened_at, v_now + interval '1 millisecond', sh.opened_by);
  v_exp := round(sh.opening_cash + (w->>'net_cash')::numeric, 2);
  v_diff := round(v_cnt - v_exp, 2);
  if abs(v_diff) >= 0.005 and nullif(trim(coalesce(p->>'difference_reason', '')), '') is null then
    raise exception 'The counted cash differs from the expected cash by %. Write the reason.', v_diff;
  end if;
  update register_shifts set status = 'closed', closed_by = auth.uid(), closed_at = v_now, expected_cash = v_exp,
         counted_cash = v_cnt, difference = v_diff, difference_reason = nullif(trim(coalesce(p->>'difference_reason', '')), ''),
         denominations = p->'denominations', note = coalesce(nullif(p->>'note', ''), note),
         summary = w || jsonb_build_object('opening_cash', sh.opening_cash, 'expected_cash', v_exp, 'counted_cash', v_cnt,
                                           'difference', v_diff, 'shift_id', sh.id, 'shift_no', sh.shift_no)
  where id = sh.id;
  perform app.log(v_biz, 'shift.close', 'register_shift', sh.id,
                  jsonb_build_object('shift_no', sh.shift_no, 'expected', v_exp, 'counted', v_cnt, 'difference', v_diff));
  return jsonb_build_object('id', sh.id, 'expected_cash', v_exp, 'counted_cash', v_cnt, 'difference', v_diff);
end $$;

-- ---------------------------------------------------------------- deposits, withdrawals, transfers, cash in/out
-- Payload: {account_id, entry_type: deposit|withdrawal|transfer, amount, to_account_id? (transfer), reference?, note?}
-- Cash-only movements (cash in/out, cash to the till) are open to cashiers; anything touching bank or mobile
-- banking accounts needs accounts.manage.
create or replace function public.create_account_entry(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; v_type text := p->>'entry_type'; v_amt numeric; v_from uuid; v_to uuid; a record; b record; v_id uuid;
  v_branch uuid; v_shift uuid; v_cash_only boolean; v_ref text;
begin
  v_biz := app.current_business_id();
  if v_biz is null then raise exception 'Not signed in to a business.'; end if;
  if v_type not in ('deposit', 'withdrawal', 'transfer') then raise exception 'Invalid entry type.'; end if;
  v_amt := round(coalesce((p->>'amount')::numeric, 0), 2);
  if v_amt <= 0 then raise exception 'Enter an amount greater than zero.'; end if;
  v_from := (p->>'account_id')::uuid;
  v_to := nullif(p->>'to_account_id', '')::uuid;
  select * into a from payment_accounts where id = v_from and business_id = v_biz and is_active;
  if not found then raise exception 'Account not found.'; end if;
  if v_type = 'transfer' then
    select * into b from payment_accounts where id = v_to and business_id = v_biz and is_active;
    if not found or v_to = v_from then raise exception 'Choose a different account to transfer to.'; end if;
  end if;
  if v_type = 'transfer' then
    v_cash_only := a.account_type = 'cash' and b.account_type = 'cash';
  else
    v_cash_only := a.account_type = 'cash';
  end if;
  if v_cash_only then
    if not (app.has_perm('cash.shift') or app.has_perm('accounts.manage')) then
      raise exception 'You do not have permission to record cash movements.';
    end if;
  elsif not app.has_perm('accounts.manage') then
    raise exception 'You do not have permission to move money in bank or mobile banking accounts.';
  end if;
  -- Bank and mobile banking accounts cannot go below zero. Cash can: shops often start without an opening balance.
  if v_type in ('withdrawal', 'transfer') and a.account_type <> 'cash' and app.account_balance(v_from) < v_amt then
    raise exception 'Not enough balance in % (available %).', a.name, app.account_balance(v_from);
  end if;
  if nullif(trim(coalesce(p->>'note', '')), '') is null and v_type <> 'transfer' then
    raise exception 'Write a short note for this entry.';
  end if;

  v_branch := app.resolve_branch(v_biz, null);
  select id into v_shift from register_shifts where business_id = v_biz and opened_by = auth.uid() and status = 'open';
  v_ref := nullif(trim(coalesce(p->>'reference', '')), '');
  insert into account_entries(business_id, branch_id, account_id, to_account_id, entry_type, amount, reference, note, shift_id, created_by)
  values (v_biz, v_branch, v_from, v_to, v_type, v_amt, v_ref, nullif(p->>'note', ''), v_shift, auth.uid())
  returning id into v_id;

  if v_type = 'deposit' then
    perform app.acct_txn(v_biz, v_branch, v_from, 'in', v_amt, 'account_deposit', v_id,
                         'Deposit' || coalesce(': ' || nullif(p->>'note', ''), ''));
  elsif v_type = 'withdrawal' then
    perform app.acct_txn(v_biz, v_branch, v_from, 'out', v_amt, 'account_withdrawal', v_id,
                         'Withdrawal' || coalesce(': ' || nullif(p->>'note', ''), ''));
  else
    perform app.acct_txn(v_biz, v_branch, v_from, 'out', v_amt, 'account_transfer', v_id, 'Transfer to ' || b.name);
    perform app.acct_txn(v_biz, v_branch, v_to, 'in', v_amt, 'account_transfer', v_id, 'Transfer from ' || a.name);
  end if;
  perform app.log(v_biz, 'account.' || v_type, 'account_entry', v_id, jsonb_build_object('amount', v_amt, 'account', a.name));
  return jsonb_build_object('id', v_id);
end $$;

-- Every active account with its current balance.
create or replace function public.account_balances() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_biz uuid; v jsonb;
begin
  v_biz := app.current_business_id();
  if not (app.has_perm('accounts.view') or app.has_perm('cash.view') or app.has_perm('reports.view')) then
    raise exception 'You do not have permission to view accounts.';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'account_type', a.account_type,
           'account_no', a.account_no, 'opening_balance', a.opening_balance, 'balance', app.account_balance(a.id),
           'is_active', a.is_active) order by a.sort_order, a.name), '[]'::jsonb) into v
  from payment_accounts a where a.business_id = v_biz and a.is_active;
  return v;
end $$;

create or replace function public.account_statement(p_account uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_biz uuid; a record; v_tz text; v_from timestamptz; v_to timestamptz; v_open numeric; v_rows jsonb; v_in numeric; v_out numeric;
begin
  v_biz := app.require_perm('accounts.view');
  select * into a from payment_accounts where id = p_account and business_id = v_biz;
  if not found then raise exception 'Account not found.'; end if;
  if p_to - p_from > 400 then raise exception 'Date range is too long.'; end if;
  v_tz := app.tz(v_biz);
  v_from := p_from::timestamp at time zone v_tz;
  v_to := (p_to + 1)::timestamp at time zone v_tz;
  select a.opening_balance + coalesce(sum(case direction when 'in' then amount else -amount end), 0) into v_open
  from account_transactions where account_id = a.id and txn_date < v_from;
  v_open := coalesce(v_open, a.opening_balance);

  select coalesce(jsonb_agg(jsonb_build_object('date', txn_date, 'direction', direction, 'amount', amount,
           'source_type', source_type, 'description', description, 'balance', v_open + running) order by txn_date, created_at), '[]'::jsonb),
         coalesce(sum(amount) filter (where direction = 'in'), 0), coalesce(sum(amount) filter (where direction = 'out'), 0)
  into v_rows, v_in, v_out
  from (
    select t.*, sum(case t.direction when 'in' then t.amount else -t.amount end)
                  over (order by t.txn_date, t.created_at, t.id) as running
    from account_transactions t
    where t.account_id = a.id and t.txn_date >= v_from and t.txn_date < v_to) x;

  return jsonb_build_object('account', jsonb_build_object('id', a.id, 'name', a.name, 'account_type', a.account_type,
           'account_no', a.account_no), 'opening', v_open, 'total_in', v_in, 'total_out', v_out,
           'closing', v_open + v_in - v_out, 'rows', v_rows);
end $$;

-- ---------------------------------------------------------------- day closing
create or replace function app.day_summary(p_biz uuid, p_branch uuid, p_date date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_tz text; v_from timestamptz; v_to timestamptz; v_default boolean; v_open numeric; v_w jsonb;
  v_sales jsonb; v_collect jsonb; v_returns numeric; v_inst numeric; v_cust numeric; v_exp numeric; v_supp numeric;
  v_bal jsonb; v_credit numeric; v_refund numeric;
begin
  v_tz := app.tz(p_biz);
  v_from := p_date::timestamp at time zone v_tz;
  v_to := (p_date + 1)::timestamp at time zone v_tz;
  select is_default into v_default from branches where id = p_branch;

  select coalesce(sum(a.opening_balance), 0)
         + coalesce((select sum(case t.direction when 'in' then t.amount else -t.amount end)
                     from account_transactions t join payment_accounts c on c.id = t.account_id
                     where t.business_id = p_biz and c.account_type = 'cash' and t.branch_id = p_branch and t.txn_date < v_from), 0)
  into v_open
  from payment_accounts a
  where a.business_id = p_biz and a.account_type = 'cash' and (a.branch_id = p_branch or (a.branch_id is null and v_default));

  v_w := app.cash_window(p_biz, p_branch, v_from, v_to, null);

  select jsonb_build_object('count', count(*), 'gross', coalesce(sum(subtotal), 0), 'discount', coalesce(sum(item_discount + invoice_discount), 0),
                            'tax', coalesce(sum(tax_amount), 0), 'total', coalesce(sum(total), 0))
  into v_sales
  from sales where business_id = p_biz and branch_id = p_branch and status = 'completed'
    and sale_date >= v_from and sale_date < v_to;

  select coalesce(sum(greatest(sa.total - coalesce(pp.paid, 0) - sa.exchange_credit, 0)), 0) into v_credit
  from sales sa
  left join lateral (select sum(amount) as paid from sale_payments where sale_id = sa.id) pp on true
  where sa.business_id = p_biz and sa.branch_id = p_branch and sa.status = 'completed'
    and sa.sale_date >= v_from and sa.sale_date < v_to;

  select coalesce(sum(total), 0) into v_returns from sales_returns
  where business_id = p_biz and branch_id = p_branch and created_at >= v_from and created_at < v_to;

  select coalesce(jsonb_agg(jsonb_build_object('account', name, 'type', account_type, 'amount', amt) order by name), '[]'::jsonb)
  into v_collect
  from (
    select a.name, a.account_type, sum(t.amount) as amt
    from account_transactions t join payment_accounts a on a.id = t.account_id
    where t.business_id = p_biz and t.branch_id = p_branch and t.direction = 'in'
      and t.source_type in ('sale_payment', 'customer_payment', 'installment_payment')
      and t.txn_date >= v_from and t.txn_date < v_to
    group by a.name, a.account_type) x;

  select coalesce(sum(amount) filter (where source_type = 'installment_payment' and direction = 'in'), 0),
         coalesce(sum(amount) filter (where source_type = 'customer_payment' and direction = 'in'), 0),
         coalesce(sum(amount) filter (where source_type = 'expense' and direction = 'out')
                  - sum(amount) filter (where source_type = 'expense_void' and direction = 'in'), 0),
         coalesce(sum(amount) filter (where source_type in ('supplier_payment', 'purchase_payment') and direction = 'out'), 0),
         coalesce(sum(amount) filter (where source_type in ('sales_return_refund', 'sale_void') and direction = 'out'), 0)
  into v_inst, v_cust, v_exp, v_supp, v_refund
  from account_transactions
  where business_id = p_biz and branch_id = p_branch and txn_date >= v_from and txn_date < v_to;

  select coalesce(jsonb_agg(jsonb_build_object('account', a.name, 'type', a.account_type, 'balance',
                    app.account_balance(a.id)) order by a.sort_order, a.name), '[]'::jsonb) into v_bal
  from payment_accounts a where a.business_id = p_biz and a.is_active and a.account_type <> 'cash';

  return jsonb_build_object(
    'date', p_date, 'branch_id', p_branch, 'opening_cash', round(v_open, 2),
    'cash_in', v_w->'cash_in', 'cash_out', v_w->'cash_out', 'by_source', v_w->'by_source',
    'expected_cash', round(v_open + (v_w->>'net_cash')::numeric, 2),
    'sales', v_sales, 'credit_sales', v_credit, 'sales_returns', v_returns, 'collections', v_collect,
    'installment_collected', v_inst, 'customer_collected', v_cust, 'expenses', v_exp, 'supplier_paid', v_supp,
    'refunds', v_refund, 'other_balances', v_bal,
    'open_shifts', (select count(*) from register_shifts where business_id = p_biz and branch_id = p_branch
                    and status = 'open' and opened_at < v_to),
    'shift_difference', coalesce((select sum(difference) from register_shifts where business_id = p_biz and branch_id = p_branch
                    and status = 'closed' and opened_at >= v_from and opened_at < v_to), 0));
end $$;

create or replace function public.day_closing_preview(p_branch uuid default null, p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_biz uuid; v_branch uuid; v_date date; c record; v jsonb;
begin
  v_biz := app.require_perm('cash.view');
  v_branch := app.resolve_branch(v_biz, p_branch);
  v_date := coalesce(p_date, app.today(v_biz));
  v := app.day_summary(v_biz, v_branch, v_date);
  select id, counted_cash, difference, closed_at into c from day_closings
  where business_id = v_biz and branch_id = v_branch and closing_date = v_date and status = 'closed';
  return v || jsonb_build_object('closed', found, 'closing_id', c.id, 'closed_counted_cash', c.counted_cash,
                                 'closed_difference', c.difference, 'closed_at', c.closed_at,
                                 'branch_name', (select name from branches where id = v_branch));
end $$;

-- Payload: {branch_id?, closing_date?, counted_cash, difference_reason?, denominations?, note?}
create or replace function public.close_day(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; v_branch uuid; v_date date; v_sum jsonb; v_cnt numeric; v_exp numeric; v_diff numeric; v_id uuid;
  v_acc uuid; v_name text; v_end timestamptz;
begin
  v_biz := app.require_perm('cash.close_day');
  v_branch := app.resolve_branch(v_biz, nullif(p->>'branch_id', '')::uuid);
  v_date := coalesce(nullif(p->>'closing_date', '')::date, app.today(v_biz));
  if v_date > app.today(v_biz) then raise exception 'You cannot close a future date.'; end if;
  if exists (select 1 from day_closings where business_id = v_biz and branch_id = v_branch and closing_date = v_date and status = 'closed') then
    raise exception 'This day is already closed.';
  end if;
  v_sum := app.day_summary(v_biz, v_branch, v_date);
  if (v_sum->>'open_shifts')::integer > 0 then
    raise exception 'Close all open cashier shifts first (% still open).', v_sum->>'open_shifts';
  end if;
  v_cnt := round((p->>'counted_cash')::numeric, 2);
  if v_cnt is null or v_cnt < 0 then raise exception 'Enter the counted cash.'; end if;
  v_exp := (v_sum->>'expected_cash')::numeric;
  v_diff := round(v_cnt - v_exp, 2);
  if abs(v_diff) >= 0.005 and nullif(trim(coalesce(p->>'difference_reason', '')), '') is null then
    raise exception 'The counted cash differs from the system cash by %. Write the reason.', v_diff;
  end if;

  if abs(v_diff) >= 0.005 then
    select a.id into v_acc from payment_accounts a
    where a.business_id = v_biz and a.account_type = 'cash' and a.is_active
      and (a.branch_id = v_branch or a.branch_id is null)
    order by (a.branch_id = v_branch) desc nulls last, a.sort_order, a.created_at limit 1;
    if v_acc is null then raise exception 'No cash account exists to record the difference.'; end if;
    v_end := ((v_date + 1)::timestamp at time zone app.tz(v_biz)) - interval '1 millisecond';
  end if;

  select full_name into v_name from business_members where business_id = v_biz and user_id = auth.uid();
  insert into day_closings(business_id, branch_id, closing_date, opening_cash, expected_cash, counted_cash, difference,
                           difference_reason, denominations, summary, note, closed_by, closed_by_name)
  values (v_biz, v_branch, v_date, (v_sum->>'opening_cash')::numeric, v_exp, v_cnt, v_diff,
          nullif(trim(coalesce(p->>'difference_reason', '')), ''), p->'denominations',
          v_sum || jsonb_build_object('counted_cash', v_cnt, 'difference', v_diff), nullif(p->>'note', ''), auth.uid(), v_name)
  returning id into v_id;

  if abs(v_diff) >= 0.005 then
    perform app.acct_txn(v_biz, v_branch, v_acc, case when v_diff > 0 then 'in' else 'out' end, abs(v_diff),
                         'cash_difference', v_id, 'Day closing ' || v_date::text || ': ' || trim(p->>'difference_reason'), v_end);
  end if;
  perform app.log(v_biz, 'day.close', 'day_closing', v_id,
                  jsonb_build_object('date', v_date, 'expected', v_exp, 'counted', v_cnt, 'difference', v_diff));
  return jsonb_build_object('id', v_id, 'expected_cash', v_exp, 'counted_cash', v_cnt, 'difference', v_diff);
end $$;

-- Reopening keeps the old record as history and reverses the posted difference; the day can then be closed again.
create or replace function public.reopen_day_closing(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; d record; t record;
begin
  v_biz := app.require_perm('cash.reopen');
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'A reason is required to reopen a closed day.'; end if;
  select * into d from day_closings where id = p_id and business_id = v_biz and status = 'closed' for update;
  if not found then raise exception 'Closed day not found.'; end if;
  for t in select * from account_transactions where business_id = v_biz and source_type = 'cash_difference' and source_id = d.id loop
    perform app.acct_txn(v_biz, t.branch_id, t.account_id, case t.direction when 'in' then 'out' else 'in' end, t.amount,
                         'cash_difference', d.id, 'Reopened ' || d.closing_date::text, t.txn_date);
  end loop;
  update day_closings set status = 'reopened', reopened_by = auth.uid(), reopened_at = now(), reopen_reason = trim(p_reason)
  where id = d.id;
  perform app.log(v_biz, 'day.reopen', 'day_closing', d.id, jsonb_build_object('date', d.closing_date, 'reason', p_reason));
end $$;
