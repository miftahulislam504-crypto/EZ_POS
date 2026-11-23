-- EZ POS - Phase 2 - 0009: installment sales, collection, reschedule, follow-ups, reminders and reports.
--
-- Accounting for an installment sale (see docs/ACCOUNTING_RULES.md):
--   sales.total          = value of the goods (revenue is recognised at sale, as for any sale)
--   down payment         = payments taken at the sale (sale_payments)
--   financed amount      = total - down payment
--   service charge       = extra charged for the credit (sales.finance_charge, customer ledger "finance_charge")
--   plan total payable   = financed amount + service charge, split into the installment schedule
--   sales.due_amount     = total + finance_charge - paid_amount  (collections add to paid_amount)

-- ---------------------------------------------------------------- create installment sale
-- Payload: the create_sale payload (customer_id required, items, payments = down payment, client_ref, ...) plus
--   installment: {count, frequency: weekly|biweekly|monthly|custom, first_due_date,
--                 service_charge, service_charge_mode: flat|percent, terms, reminders_enabled,
--                 custom_schedule: [{due_date, amount}],
--                 guarantors: [{kind: guarantor|reference|emergency, name, phone, address, relationship, nid_number}]}
create or replace function public.create_installment_sale(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; v_inst jsonb; v_res jsonb; v_customer uuid; v_ref uuid; ex record; s record;
  v_settings jsonb; v_today date; v_freq text; v_first date; v_count integer; v_max integer;
  v_down numeric; v_financed numeric; v_charge numeric := 0; v_rate numeric; v_total_pay numeric;
  v_min_pct numeric; v_plan uuid; v_plan_no text; v_base numeric; v_amt numeric; v_due date; v_sum numeric := 0;
  v_custom jsonb; x jsonb; i integer;
begin
  v_biz := app.require_perm('installments.create');
  v_inst := p->'installment';
  if v_inst is null or jsonb_typeof(v_inst) <> 'object' then raise exception 'Installment details are missing.'; end if;
  v_customer := nullif(p->>'customer_id', '')::uuid;
  if v_customer is null then raise exception 'Select a customer for an installment sale.'; end if;

  v_ref := nullif(p->>'client_ref', '')::uuid;
  if v_ref is not null then
    select pl.id as plan_id, pl.plan_no, sa.id as sale_id, sa.invoice_no, sa.total, sa.paid_amount,
           pl.financed_amount, pl.service_charge, pl.total_payable into ex
    from sales sa join installment_plans pl on pl.sale_id = sa.id
    where sa.business_id = v_biz and sa.client_ref = v_ref;
    if found then
      return jsonb_build_object('id', ex.sale_id, 'invoice_no', ex.invoice_no, 'plan_id', ex.plan_id, 'plan_no', ex.plan_no,
        'total', ex.total, 'paid', ex.paid_amount, 'financed', ex.financed_amount, 'service_charge', ex.service_charge,
        'total_payable', ex.total_payable, 'duplicate', true);
    end if;
  end if;

  select settings into v_settings from businesses where id = v_biz;
  v_today := app.today(v_biz);
  v_max := coalesce((v_settings->>'installment_max_count')::integer, 60);
  v_freq := coalesce(nullif(v_inst->>'frequency', ''), 'monthly');
  if v_freq not in ('weekly', 'biweekly', 'monthly', 'custom') then raise exception 'Invalid installment frequency.'; end if;

  v_custom := case when jsonb_typeof(v_inst->'custom_schedule') = 'array' and jsonb_array_length(v_inst->'custom_schedule') > 0
                   then v_inst->'custom_schedule' end;
  if v_freq = 'custom' and v_custom is null then raise exception 'Enter the custom installment dates and amounts.'; end if;
  if v_custom is not null then
    v_count := jsonb_array_length(v_custom);
  else
    v_count := coalesce((v_inst->>'count')::integer, 0);
    v_first := coalesce(nullif(v_inst->>'first_due_date', '')::date,
                        case v_freq when 'weekly' then v_today + 7 when 'biweekly' then v_today + 14
                                    else (v_today + interval '1 month')::date end);
  end if;
  if v_count < 1 or v_count > v_max then raise exception 'The number of installments must be between 1 and %.', v_max; end if;

  -- the sale itself, taken inside this transaction with installment rules enabled
  perform set_config('app.installment_sale', '1', true);
  v_res := public.create_sale(p - 'installment');
  perform set_config('app.installment_sale', '', true);

  select * into s from sales where id = (v_res->>'id')::uuid;
  v_down := s.paid_amount;
  v_financed := round(s.total - v_down, 2);
  if v_financed <= 0.004 then raise exception 'The down payment covers the full amount. Use a regular sale instead.'; end if;
  v_min_pct := coalesce((v_settings->>'installment_min_down_percent')::numeric, 0);
  if v_down + 0.004 < round(s.total * v_min_pct / 100, 2) then
    raise exception 'A down payment of at least % (% percent) is required.', round(s.total * v_min_pct / 100, 2), v_min_pct;
  end if;

  v_rate := greatest(coalesce((v_inst->>'service_charge')::numeric, 0), 0);
  v_charge := case when coalesce(v_inst->>'service_charge_mode', 'flat') = 'percent'
                   then round(v_financed * v_rate / 100, 2) else round(v_rate, 2) end;
  v_total_pay := v_financed + v_charge;

  if v_custom is not null then
    for x in select * from jsonb_array_elements(v_custom) loop
      v_sum := v_sum + round(coalesce((x->>'amount')::numeric, 0), 2);
    end loop;
    if abs(v_sum - v_total_pay) > 0.009 then
      raise exception 'The custom schedule adds up to % but % is payable.', v_sum, v_total_pay;
    end if;
    select min((e->>'due_date')::date) into v_first from jsonb_array_elements(v_custom) e;
  end if;

  v_plan_no := app.doc_no(v_biz, 'installment', 'INS');
  insert into installment_plans(business_id, branch_id, sale_id, customer_id, plan_no, product_total, down_payment,
                                financed_amount, service_charge, total_payable, installment_count, frequency,
                                first_due_date, terms, reminders_enabled, created_by)
  values (v_biz, s.branch_id, s.id, v_customer, v_plan_no, s.total, v_down, v_financed, v_charge, v_total_pay,
          v_count, v_freq, v_first, nullif(v_inst->>'terms', ''),
          coalesce((v_inst->>'reminders_enabled')::boolean, true), auth.uid())
  returning id into v_plan;

  if v_custom is not null then
    i := 0;
    for x in select * from jsonb_array_elements(v_custom) as e order by (e->>'due_date')::date loop
      i := i + 1;
      v_amt := round((x->>'amount')::numeric, 2);
      if v_amt <= 0 then raise exception 'Every installment amount must be greater than zero.'; end if;
      v_due := (x->>'due_date')::date;
      insert into installment_items(business_id, plan_id, seq, due_date, original_due_date, amount)
      values (v_biz, v_plan, i, v_due, v_due, v_amt);
    end loop;
  else
    v_base := trunc(v_total_pay * 100 / v_count) / 100;
    if v_base <= 0 then raise exception 'The installment amount is too small. Use fewer installments.'; end if;
    for i in 1..v_count loop
      v_due := case v_freq when 'weekly' then v_first + (i - 1) * 7
                           when 'biweekly' then v_first + (i - 1) * 14
                           else (v_first + make_interval(months => i - 1))::date end;
      v_amt := case when i = v_count then round(v_total_pay - v_base * (v_count - 1), 2) else v_base end;
      insert into installment_items(business_id, plan_id, seq, due_date, original_due_date, amount)
      values (v_biz, v_plan, i, v_due, v_due, v_amt);
    end loop;
  end if;

  if jsonb_typeof(v_inst->'guarantors') = 'array' then
    for x in select * from jsonb_array_elements(v_inst->'guarantors') loop
      if nullif(trim(coalesce(x->>'name', '')), '') is null then continue; end if;
      insert into installment_guarantors(business_id, plan_id, kind, name, phone, address, relationship, nid_number)
      values (v_biz, v_plan, coalesce(nullif(x->>'kind', ''), 'guarantor'), trim(x->>'name'), nullif(x->>'phone', ''),
              nullif(x->>'address', ''), nullif(x->>'relationship', ''), nullif(x->>'nid_number', ''));
    end loop;
  end if;

  update sales set finance_charge = v_charge, due_amount = round(v_financed + v_charge, 2),
                   payment_status = case when paid_amount > 0 then 'partial' else 'due' end
  where id = s.id;
  if v_charge > 0 then
    perform app.cust_ledger(v_biz, v_customer, 'finance_charge', 'Service charge ' || v_plan_no, v_charge, 0,
                            'installment_plan', v_plan, v_plan_no);
  end if;

  perform app.log(v_biz, 'installment.create', 'installment_plan', v_plan,
    jsonb_build_object('plan_no', v_plan_no, 'invoice_no', s.invoice_no, 'financed', v_financed,
                       'service_charge', v_charge, 'count', v_count));
  return jsonb_build_object('id', s.id, 'invoice_no', s.invoice_no, 'plan_id', v_plan, 'plan_no', v_plan_no,
    'total', s.total, 'paid', v_down, 'financed', v_financed, 'service_charge', v_charge,
    'total_payable', v_total_pay, 'duplicate', false);
end $$;

-- ---------------------------------------------------------------- collect installment
-- Payload: {plan_id, amount, account_id, payment_date?, reference?, note?, client_ref?, item_ids?: [uuid]}
-- Without item_ids the money goes to the oldest unpaid installments first, so paying ahead works naturally.
-- Money beyond what the plan still needs stays on the customer account as advance.
create or replace function public.collect_installment(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_biz uuid; pl record; ex record; it record; v_ref uuid; v_amount numeric; v_acc uuid; v_id uuid; v_no text;
  v_branch uuid; v_date timestamptz; v_ids uuid[]; v_remaining numeric; v_alloc numeric; v_allocated numeric := 0;
  v_done boolean; v_new_paid numeric;
begin
  v_biz := app.require_perm('installments.collect');
  v_ref := nullif(p->>'client_ref', '')::uuid;
  if v_ref is not null then
    select id, receipt_no, amount, allocated_amount into ex from installment_payments where business_id = v_biz and client_ref = v_ref;
    if found then
      return jsonb_build_object('id', ex.id, 'receipt_no', ex.receipt_no, 'amount', ex.amount,
                                'allocated', ex.allocated_amount, 'duplicate', true);
    end if;
  end if;
  select * into pl from installment_plans where id = (p->>'plan_id')::uuid and business_id = v_biz for update;
  if not found then raise exception 'Installment plan not found.'; end if;
  if pl.status <> 'active' then raise exception 'This installment plan is %.', pl.status; end if;
  v_amount := round(coalesce((p->>'amount')::numeric, 0), 2);
  if v_amount <= 0 then raise exception 'Enter an amount greater than zero.'; end if;
  v_acc := (p->>'account_id')::uuid;
  perform app.check_account(v_biz, v_acc);
  v_branch := app.resolve_branch(v_biz, null);
  v_date := coalesce(nullif(p->>'payment_date', '')::timestamptz, clock_timestamp());
  v_no := app.doc_no(v_biz, 'installment_payment', 'IRC');

  insert into installment_payments(business_id, branch_id, plan_id, customer_id, receipt_no, amount, account_id,
                                   payment_date, reference, note, client_ref, created_by)
  values (v_biz, v_branch, pl.id, pl.customer_id, v_no, v_amount, v_acc, v_date, nullif(p->>'reference', ''),
          nullif(p->>'note', ''), v_ref, auth.uid())
  returning id into v_id;

  v_ids := case when jsonb_typeof(p->'item_ids') = 'array' and jsonb_array_length(p->'item_ids') > 0
                then array(select jsonb_array_elements_text(p->'item_ids')::uuid) end;
  v_remaining := v_amount;
  for it in
    select * from installment_items
    where plan_id = pl.id and status in ('pending', 'partial') and (v_ids is null or id = any (v_ids))
    order by due_date, seq for update
  loop
    exit when v_remaining <= 0;
    v_alloc := least(it.amount - it.paid_amount, v_remaining);
    insert into installment_payment_allocations(business_id, payment_id, item_id, amount) values (v_biz, v_id, it.id, v_alloc);
    v_new_paid := it.paid_amount + v_alloc;
    update installment_items set paid_amount = v_new_paid,
           status = case when v_new_paid >= amount - 0.004 then 'paid' else 'partial' end,
           paid_at = case when v_new_paid >= amount - 0.004 then v_date end
    where id = it.id;
    v_remaining := v_remaining - v_alloc;
    v_allocated := v_allocated + v_alloc;
  end loop;
  if v_allocated <= 0 then raise exception 'Nothing is due on the selected installments.'; end if;

  update installment_payments set allocated_amount = v_allocated where id = v_id;
  v_done := not exists (select 1 from installment_items where plan_id = pl.id and status in ('pending', 'partial'));
  update installment_plans set paid_amount = paid_amount + v_allocated,
         status = case when v_done then 'completed' else status end,
         completed_at = case when v_done then now() else completed_at end
  where id = pl.id;
  update sales set paid_amount = paid_amount + v_allocated, due_amount = greatest(due_amount - v_allocated, 0),
         payment_status = case when due_amount - v_allocated <= 0.004 then 'paid' else 'partial' end
  where id = pl.sale_id;

  perform app.cust_ledger(v_biz, pl.customer_id, 'payment', 'Installment receipt ' || v_no || ' (' || pl.plan_no || ')',
                          0, v_amount, 'installment_payment', v_id, v_no, v_date);
  perform app.acct_txn(v_biz, v_branch, v_acc, 'in', v_amount, 'installment_payment', v_id, 'Installment ' || v_no, v_date);
  perform app.log(v_biz, 'installment.collect', 'installment_payment', v_id,
    jsonb_build_object('receipt_no', v_no, 'plan_no', pl.plan_no, 'amount', v_amount, 'allocated', v_allocated));
  return jsonb_build_object('id', v_id, 'receipt_no', v_no, 'amount', v_amount, 'allocated', v_allocated,
                            'advance', v_amount - v_allocated, 'plan_completed', v_done, 'duplicate', false);
end $$;

-- ---------------------------------------------------------------- change a due date (history is kept)
create or replace function public.reschedule_installment(p_item uuid, p_new_date date, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; it record;
begin
  v_biz := app.require_perm('installments.reschedule');
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'A reason is required to change a due date.'; end if;
  if p_new_date is null then raise exception 'Select the new due date.'; end if;
  select i.*, pl.status as plan_status into it
  from installment_items i join installment_plans pl on pl.id = i.plan_id
  where i.id = p_item and i.business_id = v_biz for update of i;
  if not found then raise exception 'Installment not found.'; end if;
  if it.status not in ('pending', 'partial') or it.plan_status <> 'active' then
    raise exception 'Only unpaid installments of an active plan can be rescheduled.';
  end if;
  if it.due_date = p_new_date then raise exception 'The new date is the same as the current due date.'; end if;
  insert into installment_date_changes(business_id, plan_id, item_id, old_date, new_date, reason, changed_by)
  values (v_biz, it.plan_id, it.id, it.due_date, p_new_date, trim(p_reason), auth.uid());
  update installment_items set due_date = p_new_date where id = it.id;
  perform app.log(v_biz, 'installment.reschedule', 'installment_item', it.id,
    jsonb_build_object('old', it.due_date, 'new', p_new_date, 'reason', p_reason));
end $$;

create or replace function public.set_installment_reminders(p_plan uuid, p_enabled boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_biz uuid;
begin
  v_biz := app.require_perm('installments.manage');
  update installment_plans set reminders_enabled = coalesce(p_enabled, true) where id = p_plan and business_id = v_biz;
  if not found then raise exception 'Installment plan not found.'; end if;
end $$;

-- ---------------------------------------------------------------- follow-up tasks
-- Payload: {plan_id, item_id?, due_date, note, assigned_to?}
create or replace function public.add_installment_followup(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; pl record; v_id uuid;
begin
  v_biz := app.require_perm('installments.collect');
  select * into pl from installment_plans where id = (p->>'plan_id')::uuid and business_id = v_biz;
  if not found then raise exception 'Installment plan not found.'; end if;
  if nullif(trim(coalesce(p->>'note', '')), '') is null then raise exception 'Write a short note for the follow-up.'; end if;
  insert into installment_followups(business_id, plan_id, item_id, customer_id, due_date, note, assigned_to, created_by)
  values (v_biz, pl.id, nullif(p->>'item_id', '')::uuid, pl.customer_id,
          coalesce(nullif(p->>'due_date', '')::date, app.today(v_biz)), trim(p->>'note'),
          coalesce(nullif(p->>'assigned_to', '')::uuid, auth.uid()), auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.complete_installment_followup(p_id uuid, p_outcome text) returns void
language plpgsql security definer set search_path = public as $$
declare v_biz uuid;
begin
  v_biz := app.require_perm('installments.collect');
  update installment_followups set status = 'done', outcome = nullif(trim(coalesce(p_outcome, '')), ''),
         done_at = now(), done_by = auth.uid()
  where id = p_id and business_id = v_biz and status = 'open';
  if not found then raise exception 'Follow-up not found or already done.'; end if;
end $$;

-- ---------------------------------------------------------------- reminders
-- Who should be reminded today. Rules come from Settings, Installments:
--   installment_remind_before (days before the due date, default [2]), installment_remind_on_due (default true),
--   installment_overdue_every_days (repeat for overdue, default 3, 0 = off), installment_reminder_gap_days
--   (never remind the same customer twice within this many days, default 1) and the three message templates.
create or replace function public.installment_reminders(p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_biz uuid; v_set jsonb; v_today date; v_tz text; v_before integer[]; v_on_due boolean; v_every integer; v_gap integer;
  v_shop text; v_tpl_before text; v_tpl_due text; v_tpl_over text; v jsonb;
begin
  v_biz := app.require_perm('installments.view');
  select settings, name into v_set, v_shop from businesses where id = v_biz;
  v_tz := app.tz(v_biz);
  v_today := coalesce(p_date, app.today(v_biz));
  v_before := coalesce(array(select jsonb_array_elements_text(v_set->'installment_remind_before')::integer), '{}');
  if jsonb_typeof(v_set->'installment_remind_before') is distinct from 'array' then v_before := array[2]; end if;
  v_on_due := coalesce((v_set->>'installment_remind_on_due')::boolean, true);
  v_every := coalesce((v_set->>'installment_overdue_every_days')::integer, 3);
  v_gap := greatest(coalesce((v_set->>'installment_reminder_gap_days')::integer, 1), 1);
  v_tpl_before := coalesce(nullif(v_set->>'installment_tpl_before', ''),
    'Dear {name}, your installment of {amount} for {plan} is due on {due_date}. Please keep the payment ready. Thank you, {shop}.');
  v_tpl_due := coalesce(nullif(v_set->>'installment_tpl_due', ''),
    'Dear {name}, your installment of {amount} for {plan} is due today. Please pay at {shop}. Thank you.');
  v_tpl_over := coalesce(nullif(v_set->>'installment_tpl_overdue', ''),
    'Dear {name}, your installment of {amount} for {plan} was due on {due_date} and is {days} day(s) overdue. Please pay as soon as possible. {shop}.');

  select coalesce(jsonb_agg(r order by (r->>'due_date'), (r->>'customer_name')), '[]'::jsonb) into v from (
    select jsonb_build_object(
      'item_id', x.id, 'plan_id', x.plan_id, 'plan_no', x.plan_no, 'customer_id', x.customer_id,
      'customer_name', x.customer_name, 'phone', x.customer_phone, 'amount', x.remaining, 'due_date', x.due_date,
      'kind', x.kind, 'days_overdue', greatest(v_today - x.due_date, 0),
      'message', replace(replace(replace(replace(replace(replace(
          case x.kind when 'before' then v_tpl_before when 'due' then v_tpl_due else v_tpl_over end,
          '{name}', x.customer_name), '{amount}', to_char(x.remaining, 'FM999G999G990D00')), '{plan}', x.plan_no),
          '{due_date}', to_char(x.due_date, 'DD Mon YYYY')), '{days}', greatest(v_today - x.due_date, 0)::text),
          '{shop}', coalesce(v_shop, ''))) as r
    from (
      select i.*, case
          when i.due_date = v_today then 'due'
          when i.due_date > v_today and (i.due_date - v_today) = any (v_before) then 'before'
          when i.due_date < v_today and v_every > 0 and (v_today - i.due_date) % v_every = 0 then 'overdue'
        end as kind
      from installment_items_view i
      where i.business_id = v_biz and i.status in ('pending', 'partial') and i.plan_status = 'active'
        and i.plan_reminders and i.customer_reminders
    ) x
    where x.kind is not null and (x.kind <> 'due' or v_on_due)
      and not exists (
        select 1 from installment_reminder_log l
        where l.business_id = v_biz and l.customer_id = x.customer_id
          and (l.sent_at at time zone v_tz)::date > v_today - v_gap)
  ) t;
  return v;
end $$;

-- Payload: {item_id, kind: before|due|overdue|manual, channel: whatsapp|sms|call|in_app|other, message?}
create or replace function public.log_installment_reminder(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_biz uuid; it record; v_id uuid;
begin
  v_biz := app.require_perm('installments.collect');
  select i.id, i.plan_id, pl.customer_id into it
  from installment_items i join installment_plans pl on pl.id = i.plan_id
  where i.id = (p->>'item_id')::uuid and i.business_id = v_biz;
  if not found then raise exception 'Installment not found.'; end if;
  insert into installment_reminder_log(business_id, plan_id, item_id, customer_id, kind, channel, message, sent_by)
  values (v_biz, it.plan_id, it.id, it.customer_id, coalesce(nullif(p->>'kind', ''), 'manual'),
          coalesce(nullif(p->>'channel', ''), 'other'), nullif(p->>'message', ''), auth.uid())
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------- dashboard figures
create or replace function public.installment_summary(p_branch uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_biz uuid; v_tz text; v_today date; v_cnt integer; v_amt numeric; v_res jsonb := '{}'::jsonb;
begin
  v_biz := app.require_perm('installments.view');
  v_tz := app.tz(v_biz);
  v_today := app.today(v_biz);

  select count(*), coalesce(sum(i.amount - i.paid_amount), 0) into v_cnt, v_amt
  from installment_items i join installment_plans pl on pl.id = i.plan_id
  where i.business_id = v_biz and i.status in ('pending', 'partial') and pl.status = 'active'
    and (p_branch is null or pl.branch_id = p_branch) and i.due_date = v_today;
  v_res := v_res || jsonb_build_object('due_today_count', v_cnt, 'due_today_amount', v_amt);

  select count(*), coalesce(sum(i.amount - i.paid_amount), 0) into v_cnt, v_amt
  from installment_items i join installment_plans pl on pl.id = i.plan_id
  where i.business_id = v_biz and i.status in ('pending', 'partial') and pl.status = 'active'
    and (p_branch is null or pl.branch_id = p_branch) and i.due_date < v_today;
  v_res := v_res || jsonb_build_object('overdue_count', v_cnt, 'overdue_amount', v_amt);

  select count(*), coalesce(sum(i.amount - i.paid_amount), 0) into v_cnt, v_amt
  from installment_items i join installment_plans pl on pl.id = i.plan_id
  where i.business_id = v_biz and i.status in ('pending', 'partial') and pl.status = 'active'
    and (p_branch is null or pl.branch_id = p_branch) and i.due_date > v_today and i.due_date <= v_today + 7;
  v_res := v_res || jsonb_build_object('next7_count', v_cnt, 'next7_amount', v_amt);

  select count(*), coalesce(sum(total_payable - paid_amount), 0) into v_cnt, v_amt
  from installment_plans where business_id = v_biz and status = 'active' and (p_branch is null or branch_id = p_branch);
  v_res := v_res || jsonb_build_object('active_plans', v_cnt, 'outstanding', v_amt);

  select coalesce(sum(amount), 0) into v_amt from installment_payments
  where business_id = v_biz and (p_branch is null or branch_id = p_branch)
    and (payment_date at time zone v_tz)::date = v_today;
  v_res := v_res || jsonb_build_object('collected_today', v_amt);

  select coalesce(sum(amount), 0) into v_amt from installment_payments
  where business_id = v_biz and (p_branch is null or branch_id = p_branch)
    and date_trunc('month', payment_date at time zone v_tz) = date_trunc('month', v_today::timestamp);
  v_res := v_res || jsonb_build_object('collected_month', v_amt);

  select count(*) into v_cnt from installment_followups
  where business_id = v_biz and status = 'open' and due_date <= v_today;
  return v_res || jsonb_build_object('followups_due', v_cnt);
end $$;

-- ---------------------------------------------------------------- installment report
create or replace function public.installment_report(p_from date, p_to date, p_branch uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_biz uuid; v_tz text; v_today date; v_sales jsonb; v_collect jsonb; v_now jsonb; v_perf jsonb; v_cust jsonb; v_prod jsonb;
begin
  v_biz := app.require_perm('installments.view');
  v_tz := app.tz(v_biz);
  v_today := app.today(v_biz);
  if p_to - p_from > 400 then raise exception 'Date range is too long.'; end if;

  select jsonb_build_object('plans', count(*), 'product_total', coalesce(sum(pl.product_total), 0),
           'down_payment', coalesce(sum(pl.down_payment), 0), 'financed', coalesce(sum(pl.financed_amount), 0),
           'service_charge', coalesce(sum(pl.service_charge), 0), 'total_payable', coalesce(sum(pl.total_payable), 0))
  into v_sales
  from installment_plans pl join sales sa on sa.id = pl.sale_id
  where pl.business_id = v_biz and pl.status <> 'cancelled' and (p_branch is null or pl.branch_id = p_branch)
    and (sa.sale_date at time zone v_tz)::date between p_from and p_to;

  select jsonb_build_object('receipts', count(*), 'amount', coalesce(sum(amount), 0))
  into v_collect
  from installment_payments
  where business_id = v_biz and (p_branch is null or branch_id = p_branch)
    and (payment_date at time zone v_tz)::date between p_from and p_to;

  select jsonb_build_object(
    'active_plans', count(*) filter (where pl.status = 'active'),
    'outstanding', coalesce(sum(pl.total_payable - pl.paid_amount) filter (where pl.status = 'active'), 0),
    'overdue_amount', coalesce((select sum(i.amount - i.paid_amount) from installment_items i
        join installment_plans q on q.id = i.plan_id
        where q.business_id = v_biz and q.status = 'active' and (p_branch is null or q.branch_id = p_branch)
          and i.status in ('pending', 'partial') and i.due_date < v_today), 0),
    'overdue_count', coalesce((select count(*) from installment_items i
        join installment_plans q on q.id = i.plan_id
        where q.business_id = v_biz and q.status = 'active' and (p_branch is null or q.branch_id = p_branch)
          and i.status in ('pending', 'partial') and i.due_date < v_today), 0))
  into v_now
  from installment_plans pl where pl.business_id = v_biz and (p_branch is null or pl.branch_id = p_branch);

  -- performance: installments that fell due inside the range
  select jsonb_build_object(
    'expected', coalesce(sum(i.amount), 0), 'collected', coalesce(sum(i.paid_amount), 0),
    'installments', count(*), 'fully_paid', count(*) filter (where i.status = 'paid'),
    'on_time', coalesce(sum(a.on_time), 0))
  into v_perf
  from installment_items i
  join installment_plans pl on pl.id = i.plan_id
  left join lateral (
    select sum(al.amount) as on_time
    from installment_payment_allocations al join installment_payments ip on ip.id = al.payment_id
    where al.item_id = i.id and (ip.payment_date at time zone v_tz)::date <= i.due_date) a on true
  where i.business_id = v_biz and pl.status <> 'cancelled' and (p_branch is null or pl.branch_id = p_branch)
    and i.due_date between p_from and p_to;

  select coalesce(jsonb_agg(r order by (r->>'outstanding')::numeric desc), '[]'::jsonb) into v_cust from (
    select jsonb_build_object('customer_id', c.id, 'name', c.name, 'phone', c.phone, 'plans', count(*),
             'total_payable', sum(pl.total_payable), 'paid', sum(pl.paid_amount),
             'outstanding', sum(pl.total_payable - pl.paid_amount),
             'overdue', coalesce(sum(o.overdue), 0)) as r
    from installment_plans pl join customers c on c.id = pl.customer_id
    left join lateral (
      select sum(i.amount - i.paid_amount) as overdue from installment_items i
      where i.plan_id = pl.id and i.status in ('pending', 'partial') and i.due_date < v_today) o on true
    where pl.business_id = v_biz and pl.status = 'active' and (p_branch is null or pl.branch_id = p_branch)
    group by c.id, c.name, c.phone
    limit 100) t;

  select coalesce(jsonb_agg(r order by (r->>'revenue')::numeric desc), '[]'::jsonb) into v_prod from (
    select jsonb_build_object('name', max(si.product_name), 'quantity', sum(si.quantity),
             'revenue', sum(si.net_amount + si.tax_amount)) as r
    from sale_items si join sales sa on sa.id = si.sale_id
    join installment_plans pl on pl.sale_id = sa.id
    where sa.business_id = v_biz and pl.status <> 'cancelled' and (p_branch is null or sa.branch_id = p_branch)
      and (sa.sale_date at time zone v_tz)::date between p_from and p_to
    group by si.product_id
    limit 100) t;

  return jsonb_build_object('sales', v_sales, 'collected', v_collect, 'now', v_now, 'performance', v_perf,
                            'customers', v_cust, 'products', v_prod);
end $$;
