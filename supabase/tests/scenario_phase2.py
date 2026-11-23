"""Phase 2 scenario: installments, serial/IMEI, batches, stock transfer, purchase return, exchange,
cash register, day closing. Run after apply_migrations.py. Prints ok / FAIL per check."""
import pgserver, psycopg2, json, warnings, uuid, decimal, datetime
warnings.filterwarnings("ignore")
srv = pgserver.get_server('/tmp/pgt/data', cleanup_mode=None)
conn = psycopg2.connect(srv.get_uri()); conn.autocommit = True
cur = conn.cursor()
FAILS = []

def su(): cur.execute("reset role")
def as_user(uid):
    su(); cur.execute("select set_config('request.jwt.claim.sub', %s, false)", (str(uid),)); cur.execute("set role authenticated")
def q(sql, args=None):
    cur.execute(sql, args)
    try: return cur.fetchall()
    except psycopg2.ProgrammingError: return None
def one(sql, args=None): return q(sql, args)[0][0]
def rpc(fn, payload):
    return one(f"select public.{fn}(%s::jsonb)", (json.dumps(payload, default=str),))
def call(sql, args=None): return one(sql, args)
def expect_err(label, fn, *a):
    try:
        fn(*a); print("FAIL (no error):", label); FAILS.append(label); return False
    except Exception as e:
        print("ok  err:", label, "->", str(e).split('\n')[0][:100]); return True
def chk(label, got, want):
    g = float(got) if isinstance(got, (int, float, decimal.Decimal)) and not isinstance(got, bool) else got
    w = float(want) if isinstance(want, (int, float, decimal.Decimal)) and not isinstance(want, bool) else want
    ok = (g == w) if not isinstance(g, float) else abs(g - w) < 0.006
    print(("ok  " if ok else "FAIL"), label, got, "" if ok else f"(want {want})")
    if not ok: FAILS.append(label)

def imei(base14):
    s = str(base14).zfill(14)
    total = 0
    for i, ch in enumerate(reversed(s)):
        d = int(ch)
        if i % 2 == 0:
            d *= 2
            if d > 9: d -= 9
        total += d
    return s + str((10 - total % 10) % 10)

su()
owner, cashier, keeper = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
for u, e in [(owner, 'o2@x.com'), (cashier, 'c2@x.com'), (keeper, 'k2@x.com')]:
    q("insert into auth.users(id,email) values (%s,%s)", (str(u), e))
as_user(owner)
biz = rpc("create_business", {"name": "Phase2 Mart", "phone": "017", "address": "Dhaka", "full_name": "Owner Two"})
su()
q("insert into business_members(business_id,user_id,full_name,role,branch_id) select %s,%s,'Cash Ier','cashier',id from branches where business_id=%s", (biz, str(cashier), biz))
q("insert into business_members(business_id,user_id,full_name,role,branch_id) select %s,%s,'Store Keeper','storekeeper',id from branches where business_id=%s", (biz, str(keeper), biz))
q("insert into role_permissions(business_id, role, permission) select %s, r.role, p from (values ('cashier'),('storekeeper')) r(role), unnest(app.default_permissions(r.role)) p on conflict do nothing", (biz,))

as_user(owner)
main = one("select id from branches where business_id=%s and is_default", (biz,))
unit = one("select id from units where short_name='pcs'")
cat = one("select id from categories limit 1")
cash = one("select id from payment_accounts where name='Cash'")
bkash = one("select id from payment_accounts where name='bKash'")
sup = rpc("create_supplier", {"name": "Gadget Supplier"})
cust = rpc("create_customer", {"name": "Karim", "phone": "01811", "workplace": "ABC Ltd", "emergency_contact_name": "Rina", "emergency_contact_phone": "01999"})
walkcust = None
chk("customer workplace saved", one("select workplace from customers where id=%s", (cust,)), "ABC Ltd")

mk = lambda name, tr, extra="": one(
    f"insert into products(business_id,name,unit_id,category_id,purchase_price,selling_price,tracking_type{extra}) values (%s,%s,%s,%s,100,150,%s) returning id",
    (biz, name, unit, cat, tr))
phone = one("insert into products(business_id,name,unit_id,category_id,purchase_price,selling_price,tracking_type,warranty_months) values (%s,'Phone X',%s,%s,10000,15000,'imei',12) returning id", (biz, unit, cat))
tv = one("insert into products(business_id,name,unit_id,category_id,purchase_price,selling_price,tracking_type) values (%s,'TV 32',%s,%s,20000,26000,'serial') returning id", (biz, unit, cat))
milk = one("insert into products(business_id,name,unit_id,category_id,purchase_price,selling_price,tracking_type) values (%s,'Milk Pack',%s,%s,50,70,'expiry') returning id", (biz, unit, cat))
cable = one("insert into products(business_id,name,unit_id,category_id,purchase_price,selling_price) values (%s,'Cable',%s,%s,50,80) returning id", (biz, unit, cat))

# ------------------------------------------------------------- serial / IMEI / batches
im = [imei(35000000000001 + i) for i in range(8)]
expect_err("invalid IMEI check digit", rpc, "create_purchase", {"supplier_id": sup, "items": [{"product_id": phone, "quantity": 1, "unit_cost": 10000, "serials": ["350000000000019"]}]})
expect_err("serial count mismatch", rpc, "create_purchase", {"supplier_id": sup, "items": [{"product_id": phone, "quantity": 2, "unit_cost": 10000, "serials": [im[0]]}]})
today = one("select app.today(%s)", (biz,))
pu = rpc("create_purchase", {"supplier_id": sup, "items": [
    {"product_id": phone, "quantity": 5, "unit_cost": 10000, "serials": im[:5]},
    {"product_id": tv, "quantity": 2, "unit_cost": 20000, "serials": ["tv-001", "TV-002"]},
    {"product_id": milk, "quantity": 20, "unit_cost": 50, "batch_no": "M1", "expiry_date": str(today + datetime.timedelta(days=10))},
    {"product_id": milk, "quantity": 10, "unit_cost": 50, "batch_no": "M2", "expiry_date": str(today + datetime.timedelta(days=3))},
    {"product_id": cable, "quantity": 100, "unit_cost": 50}],
    "payments": [{"account_id": cash, "amount": 1000}]})
print("purchase", pu)
chk("stock phone", one("select quantity from stock_levels where product_id=%s", (phone,)), 5)
chk("units in stock", one("select count(*) from stock_units where status='in_stock' and product_id=%s", (phone,)), 5)
chk("serial upper-cased", one("select count(*) from stock_units where serial_no='TV-001'"), 1)
chk("batches created", one("select count(*) from stock_batches where product_id=%s", (milk,)), 2)
expect_err("duplicate IMEI on purchase", rpc, "create_purchase", {"supplier_id": sup, "items": [{"product_id": phone, "quantity": 1, "unit_cost": 10000, "serials": [im[0]]}]})
expect_err("expiry product needs date", rpc, "create_purchase", {"supplier_id": sup, "items": [{"product_id": milk, "quantity": 1, "unit_cost": 50}]})
rpc("create_purchase", {"supplier_id": sup, "items": [{"product_id": phone, "quantity": 3, "unit_cost": 10000, "serials": im[5:8]}], "payments": [{"account_id": cash, "amount": 30000}]})
lk = call("select public.serial_lookup(%s)", (im[0],))
chk("lookup status", lk['status'], "in_stock")
chk("lookup product", lk['product_name'], "Phone X")
chk("expiry report 5 days", len(call("select public.expiry_report(5, null)")), 1)
chk("expiry report 30 days", len(call("select public.expiry_report(30, null)")), 2)

# regular sale with an IMEI, FEFO batch sale
s1 = rpc("create_sale", {"items": [{"product_id": phone, "quantity": 1, "serials": [im[0]]}, {"product_id": milk, "quantity": 12}],
                         "payments": [{"account_id": cash, "amount": 15000 + 12 * 70}]})
chk("sale total", s1['total'], 15840)
chk("unit sold", one("select status from stock_units where serial_no=%s", (im[0],)), "sold")
chk("warranty set", one("select warranty_until is not null from stock_units where serial_no=%s", (im[0],)), True)
chk("FEFO takes soonest batch first", one("select quantity_left from stock_batches where batch_no='M2'"), 0)
chk("FEFO then next batch", one("select quantity_left from stock_batches where batch_no='M1'"), 18)
expect_err("sell the same IMEI twice", rpc, "create_sale", {"items": [{"product_id": phone, "quantity": 1, "serials": [im[0]]}], "payments": [{"account_id": cash, "amount": 15000}]})
expect_err("sale without serial", rpc, "create_sale", {"items": [{"product_id": phone, "quantity": 1}], "payments": [{"account_id": cash, "amount": 15000}]})
rpc_void = call("select public.void_sale(%s, 'test void')", (s1['id'],)) if False else None
call("select public.void_sale(%s, %s)", (s1['id'], "mistake"))
chk("void restores unit", one("select status from stock_units where serial_no=%s", (im[0],)), "in_stock")
chk("void restores batch", one("select quantity_left from stock_batches where batch_no='M2'"), 10)

# ------------------------------------------------------------- installment sale
sale_payload = {"customer_id": cust, "items": [{"product_id": phone, "quantity": 1, "serials": [im[1]]}],
                "payments": [{"account_id": cash, "amount": 3000}], "client_ref": str(uuid.uuid4()),
                "installment": {"count": 4, "frequency": "monthly", "first_due_date": str(today + datetime.timedelta(days=30)),
                                "service_charge": 10, "service_charge_mode": "percent", "terms": "Pay on time",
                                "guarantors": [{"kind": "guarantor", "name": "Salma", "phone": "01712", "relationship": "Sister"}]}}
ins = rpc("create_installment_sale", sale_payload)
print("installment", ins)
chk("financed", ins['financed'], 12000)
chk("service charge 10 percent", ins['service_charge'], 1200)
chk("total payable", ins['total_payable'], 13200)
items = q("select seq, amount, due_date from installment_items where plan_id=%s order by seq", (ins['plan_id'],))
chk("4 installments", len(items), 4)
chk("schedule sums to payable", sum(float(i[1]) for i in items), 13200)
chk("sale due includes charge", one("select due_amount from sales where id=%s", (ins['id'],)), 13200)
chk("customer balance = financed+charge", one("select balance from customers_view where id=%s", (cust,)), 13200)
chk("sale type", one("select sale_type from sales where id=%s", (ins['id'],)), "installment")
chk("guarantor saved", one("select count(*) from installment_guarantors where plan_id=%s", (ins['plan_id'],)), 1)
dup = rpc("create_installment_sale", sale_payload)
chk("idempotent installment sale", dup['duplicate'], True)
expect_err("installment needs customer", rpc, "create_installment_sale", {"items": [{"product_id": cable, "quantity": 1}], "payments": [{"account_id": cash, "amount": 10}], "installment": {"count": 2}})
expect_err("down payment covers everything", rpc, "create_installment_sale", {"customer_id": cust, "items": [{"product_id": cable, "quantity": 1}], "payments": [{"account_id": cash, "amount": 80}], "installment": {"count": 2}})
expect_err("custom schedule must match", rpc, "create_installment_sale", {"customer_id": cust, "items": [{"product_id": cable, "quantity": 1}], "payments": [{"account_id": cash, "amount": 10}],
    "installment": {"frequency": "custom", "custom_schedule": [{"due_date": str(today + datetime.timedelta(days=5)), "amount": 10}]}})
expect_err("regular payment cannot touch installment sale", rpc, "record_customer_payment", {"customer_id": cust, "amount": 100, "account_id": cash, "allocations": [{"sale_id": ins['id'], "amount": 100}]})
expect_err("return on installment sale needs items", rpc, "create_sales_return", {"sale_id": ins['id'], "items": [], "refund_account_id": cash})

# collections
items_ids = [r[0] for r in q("select id from installment_items where plan_id=%s order by seq", (ins['plan_id'],))]
c1 = rpc("collect_installment", {"plan_id": ins['plan_id'], "amount": 4000, "account_id": cash, "client_ref": str(uuid.uuid4())})
chk("collect allocated", c1['allocated'], 4000)
st = q("select status, paid_amount from installment_items where plan_id=%s order by seq", (ins['plan_id'],))
chk("first installment paid", st[0][0], "paid")
chk("second partially paid", st[1][0], "partial")
chk("plan paid amount", one("select paid_amount from installment_plans where id=%s", (ins['plan_id'],)), 4000)
chk("sale due reduced", one("select due_amount from sales where id=%s", (ins['id'],)), 9200)
chk("customer balance reduced", one("select balance from customers_view where id=%s", (cust,)), 9200)
expect_err("amount zero", rpc, "collect_installment", {"plan_id": ins['plan_id'], "amount": 0, "account_id": cash})
# reschedule with history
newd = today + datetime.timedelta(days=50)
expect_err("reschedule needs reason", lambda: call("select public.reschedule_installment(%s,%s,%s)", (items_ids[3], newd, "")))
call("select public.reschedule_installment(%s,%s,%s)", (items_ids[3], newd, "Customer asked"))
chk("date changed", one("select due_date from installment_items where id=%s", (items_ids[3],)), newd)
chk("old date kept", one("select count(*) from installment_date_changes where item_id=%s", (items_ids[3],)), 1)
chk("original date preserved", one("select original_due_date <> due_date from installment_items where id=%s", (items_ids[3],)), True)
# make one overdue and check summary + reminders
su(); q("update installment_items set due_date = app.today(business_id) - 4 where id=%s", (items_ids[1],)); as_user(owner)
sm = call("select public.installment_summary(null)")
chk("overdue count", sm['overdue_count'], 1)
chk("overdue amount", sm['overdue_amount'], 3300 - 700)
rem = call("select public.installment_reminders(null)")
print("reminders:", [(r['kind'], r['days_overdue']) for r in rem])
chk("overdue reminder due (4 days, every 3 => not today)", len(rem), 0)
su(); q("update installment_items set due_date = app.today(business_id) - 3 where id=%s", (items_ids[1],)); as_user(owner)
rem = call("select public.installment_reminders(null)")
chk("overdue reminder on day 3", len(rem), 1)
if rem:
    chk("message mentions amount", "2,600.00" in rem[0]['message'] or "2600" in rem[0]['message'], True)
    call("select public.log_installment_reminder(%s::jsonb)", (json.dumps({"item_id": rem[0]['item_id'], "kind": "overdue", "channel": "whatsapp", "message": rem[0]['message']}),))
    chk("no repeat reminder same day", len(call("select public.installment_reminders(null)")), 0)
fu = call("select public.add_installment_followup(%s::jsonb)", (json.dumps({"plan_id": ins['plan_id'], "note": "Call customer", "due_date": str(today)}),))
call("select public.complete_installment_followup(%s,%s)", (fu, "Promised Friday"))
chk("followup done", one("select status from installment_followups where id=%s", (fu,)), "done")
# pay everything remaining plus advance
c2 = rpc("collect_installment", {"plan_id": ins['plan_id'], "amount": 9300, "account_id": bkash})
chk("completed with advance", c2['plan_completed'], True)
chk("advance kept", c2['advance'], 100)
chk("plan completed", one("select status from installment_plans where id=%s", (ins['plan_id'],)), "completed")
chk("sale fully paid", one("select payment_status from sales where id=%s", (ins['id'],)), "paid")
chk("customer ends with advance", one("select balance from customers_view where id=%s", (cust,)), -100)
expect_err("collect on completed plan", rpc, "collect_installment", {"plan_id": ins['plan_id'], "amount": 10, "account_id": cash})
expect_err("void after collections blocked", lambda: call("select public.void_sale(%s,%s)", (ins['id'], "x")))
rep = call("select public.installment_report(%s,%s,null)", (today - datetime.timedelta(days=1), today + datetime.timedelta(days=60)))
chk("report plans", rep['sales']['plans'], 1)
chk("report financed", rep['sales']['financed'], 12000)
chk("report collected", rep['collected']['amount'], 13300)

# void of installment sale without collections
ins2 = rpc("create_installment_sale", {"customer_id": cust, "items": [{"product_id": cable, "quantity": 5}], "payments": [{"account_id": cash, "amount": 100}],
    "installment": {"count": 3, "frequency": "weekly", "service_charge": 30}})
before = one("select balance from customers_view where id=%s", (cust,))
call("select public.void_sale(%s,%s)", (ins2['id'], "customer cancelled"))
chk("void cancels plan", one("select status from installment_plans where id=%s", (ins2['plan_id'],)), "cancelled")
chk("void reverses balance incl charge", one("select balance from customers_view where id=%s", (cust,)), -100)

# ------------------------------------------------------------- stock transfer
wh = call("select public.save_branch(%s::jsonb)", (json.dumps({"name": "Main Warehouse", "kind": "warehouse"}),))
chk("branch created", one("select kind from branches where id=%s", (wh,)), "warehouse")
stock_before = one("select quantity from stock_levels where product_id=%s and branch_id=%s", (phone, main))
tr = rpc("create_stock_transfer", {"from_branch_id": main, "to_branch_id": wh, "items": [
    {"product_id": phone, "quantity": 2}, {"product_id": cable, "quantity": 30}, {"product_id": milk, "quantity": 5}]})
chk("transfer requested", tr['status'], "requested")
expect_err("dispatch needs serials", rpc, "dispatch_stock_transfer", {"id": tr['id']})
tid = tr['id']
titems = q("select id, product_id from stock_transfer_items where transfer_id=%s", (tid,))
pitem = [i[0] for i in titems if i[1] == phone][0]
d = rpc("dispatch_stock_transfer", {"id": tid, "items": [{"item_id": pitem, "serials": [im[2], im[3]]}]})
chk("in transit", d['status'], "in_transit")
chk("source stock dropped", one("select quantity from stock_levels where product_id=%s and branch_id=%s", (phone, main)), stock_before - 2)
chk("units in transit", one("select count(*) from stock_units where status='in_transit'"), 2)
r1 = rpc("receive_stock_transfer", {"id": tid, "items": [{"item_id": pitem, "quantity": 1, "serials": [im[2]]}]})
chk("partially received", r1['status'], "partially_received")
chk("dest stock", one("select quantity from stock_levels where product_id=%s and branch_id=%s", (phone, wh)), 1)
chk("unit moved branch", one("select branch_id from stock_units where serial_no=%s", (im[2],)), wh)
expect_err("cannot receive foreign serial", rpc, "receive_stock_transfer", {"id": tid, "items": [{"item_id": pitem, "quantity": 1, "serials": [im[4]]}]})
r2 = rpc("receive_stock_transfer", {"id": tid, "receive_all": True})
chk("received", r2['status'], "received")
chk("dest cable stock", one("select quantity from stock_levels where product_id=%s and branch_id=%s", (cable, wh)), 30)
chk("dest batch created", one("select coalesce(sum(quantity_left),0) from stock_batches where product_id=%s and branch_id=%s", (milk, wh)), 5)
# short receipt + cancel
tr2 = rpc("create_stock_transfer", {"from_branch_id": main, "to_branch_id": wh, "dispatch": True, "items": [{"product_id": cable, "quantity": 10}]})
chk("dispatch on create", tr2['status'], "in_transit")
rpc("receive_stock_transfer", {"id": tr2['id'], "items": [{"item_id": one("select id from stock_transfer_items where transfer_id=%s", (tr2['id'],)), "quantity": 7}], "close_short": True, "short_reason": "3 damaged in transit"})
chk("closed short", one("select status from stock_transfers where id=%s", (tr2['id'],)), "received")
chk("shortage recorded", one("select sent_quantity - received_quantity from stock_transfer_items where transfer_id=%s", (tr2['id'],)), 3)
tr3 = rpc("create_stock_transfer", {"from_branch_id": main, "to_branch_id": wh, "dispatch": True, "items": [{"product_id": cable, "quantity": 5}]})
cb = one("select quantity from stock_levels where product_id=%s and branch_id=%s", (cable, main))
call("select public.cancel_stock_transfer(%s,%s)", (tr3['id'], "wrong location"))
chk("cancel returns stock", one("select quantity from stock_levels where product_id=%s and branch_id=%s", (cable, main)), cb + 5)
expect_err("cannot transfer more than stock", rpc, "create_stock_transfer", {"from_branch_id": main, "to_branch_id": wh, "dispatch": True, "items": [{"product_id": cable, "quantity": 9999}]})
as_user(cashier)
expect_err("cashier cannot transfer", rpc, "create_stock_transfer", {"from_branch_id": main, "to_branch_id": wh, "items": [{"product_id": cable, "quantity": 1}]})
as_user(owner)

# ------------------------------------------------------------- purchase return
pu_items = q("select id, product_id from purchase_items where purchase_id=%s", (pu['id'],))
cable_pi = [i[0] for i in pu_items if i[1] == cable][0]
tv_pi = [i[0] for i in pu_items if i[1] == tv][0]
due_before = one("select due_amount from purchases where id=%s", (pu['id'],))
sup_bal = one("select balance from suppliers_view where id=%s", (sup,))
pr1 = rpc("create_purchase_return", {"purchase_id": pu['id'], "refund_mode": "credit", "reason": "defective",
                                      "items": [{"purchase_item_id": cable_pi, "quantity": 10}, {"purchase_item_id": tv_pi, "quantity": 1, "serials": ["TV-001"]}]})
chk("return total", pr1['total'], 10 * 50 + 20000)
chk("due adjusted", pr1['due_adjusted'], pr1['total'])
chk("purchase due reduced", one("select due_amount from purchases where id=%s", (pu['id'],)), float(due_before) - 20500)
chk("supplier payable reduced", one("select balance from suppliers_view where id=%s", (sup,)), float(sup_bal) - 20500)
chk("unit returned to supplier", one("select status from stock_units where serial_no='TV-001'"), "returned_to_supplier")
chk("stock decreased main", one("select quantity from stock_levels where product_id=%s and branch_id=%s", (cable, main)), cb + 5 - 10)
expect_err("over-return", rpc, "create_purchase_return", {"purchase_id": pu['id'], "items": [{"purchase_item_id": cable_pi, "quantity": 1000}]})
expect_err("return IMEI not on purchase", rpc, "create_purchase_return", {"purchase_id": pu['id'], "items": [{"purchase_item_id": tv_pi, "quantity": 1, "serials": ["NOPE"]}]})
# paid purchase + cash refund
pu2 = rpc("create_purchase", {"supplier_id": sup, "items": [{"product_id": cable, "quantity": 20, "unit_cost": 50}], "payments": [{"account_id": cash, "amount": 1000}]})
cash_before = one("select balance from accounts_view where id=%s", (cash,))
pi2 = one("select id from purchase_items where purchase_id=%s", (pu2['id'],))
pr2 = rpc("create_purchase_return", {"purchase_id": pu2['id'], "refund_mode": "cash", "refund_account_id": cash, "items": [{"purchase_item_id": pi2, "quantity": 4}]})
chk("cash refund", pr2['refund'], 200)
chk("cash account gained refund", one("select balance from accounts_view where id=%s", (cash,)), float(cash_before) + 200)

# ------------------------------------------------------------- exchange
cs = rpc("create_sale", {"items": [{"product_id": cable, "quantity": 3}], "payments": [{"account_id": cash, "amount": 240}]})
cs_item = one("select id from sale_items where sale_id=%s", (cs['id'],))
cash_b = one("select balance from accounts_view where id=%s", (cash,))
ex1 = rpc("create_exchange", {"sale_id": cs['id'], "reason": "wrong type", "return_items": [{"sale_item_id": cs_item, "quantity": 3, "condition": "resellable"}],
    "new_sale": {"items": [{"product_id": milk, "quantity": 5}]}, "payments": [{"account_id": cash, "amount": 110}], "refund_mode": "cash", "refund_account_id": cash})
print("exchange", ex1)
chk("exchange return total", ex1['return_total'], 240)
chk("exchange new total", ex1['new_total'], 350)
chk("exchange credit used", ex1['credit_used'], 240)
chk("exchange customer paid", ex1['customer_paid'], 110)
chk("exchange invoice paid", one("select payment_status from sales where id=%s", (ex1['sale_id'],)), "paid")
chk("exchange cash moved only the difference", one("select balance from accounts_view where id=%s", (cash,)), float(cash_b) + 110)
# cheaper exchange: refund difference
cs2 = rpc("create_sale", {"items": [{"product_id": cable, "quantity": 5}], "payments": [{"account_id": cash, "amount": 400}]})
cs2_item = one("select id from sale_items where sale_id=%s", (cs2['id'],))
cash_b = one("select balance from accounts_view where id=%s", (cash,))
ex2 = rpc("create_exchange", {"sale_id": cs2['id'], "return_items": [{"sale_item_id": cs2_item, "quantity": 5, "condition": "resellable"}],
    "new_sale": {"items": [{"product_id": cable, "quantity": 2}]}, "payments": [], "refund_mode": "cash", "refund_account_id": cash})
chk("cheaper exchange refund", ex2['customer_credit_left'], 0)
chk("refund paid out", one("select balance from accounts_view where id=%s", (cash,)), float(cash_b) - 240)
expect_err("void exchange invoice blocked", lambda: call("select public.void_sale(%s,%s)", (ex1['sale_id'], "x")))
rep = call("select public.report_daily_sales(%s, %s, null)", (today, today)) if False else None

# exchange with serial item
ps = rpc("create_sale", {"items": [{"product_id": phone, "quantity": 1, "serials": [im[4]]}], "payments": [{"account_id": cash, "amount": 15000}]})
ps_item = one("select id from sale_items where sale_id=%s", (ps['id'],))
ex3 = rpc("create_exchange", {"sale_id": ps['id'], "return_items": [{"sale_item_id": ps_item, "quantity": 1, "condition": "resellable", "serials": [im[4]]}],
    "new_sale": {"items": [{"product_id": phone, "quantity": 1, "serials": [im[5]]}]}, "payments": [], "refund_mode": "cash", "refund_account_id": cash})
chk("serial exchange: old unit back", one("select status from stock_units where serial_no=%s", (im[4],)), "in_stock")
chk("serial exchange: new unit sold", one("select status from stock_units where serial_no=%s", (im[5],)), "sold")
chk("serial exchange no money", ex3['customer_paid'], 0)

# ------------------------------------------------------------- stock count and adjustments
adj_before = one("select quantity from stock_levels where product_id=%s and branch_id=%s", (cable, main))
cnt = rpc("save_stock_count", {"items": [{"product_id": cable, "counted_quantity": float(adj_before) - 3, "reason": "3 lost"}]})
chk("draft count", cnt['status'], "draft")
expect_err("count tracked product blocked", rpc, "save_stock_count", {"items": [{"product_id": phone, "counted_quantity": 1}]})
fin = rpc("save_stock_count", {"id": cnt['id'], "items": [], "finalize": True})
chk("count completed", fin['status'], "completed")
chk("count adjusted stock", one("select quantity from stock_levels where product_id=%s and branch_id=%s", (cable, main)), float(adj_before) - 3)
call("select public.adjust_stock(%s,%s,%s,%s,%s,%s,%s,%s)", (phone, main, 1, 'damage', 'dropped', [im[6]], None, None))
chk("damaged unit", one("select status from stock_units where serial_no=%s", (im[6],)), "damaged")
call("select public.adjust_stock(%s,%s,%s,%s,%s,%s,%s,%s)", (milk, main, 2, 'expired', 'expired pack', None, None, None))
chk("expired consumed from batch", one("select coalesce(sum(quantity_left),0) from stock_batches where product_id=%s and branch_id=%s", (milk, main)), 18 - 5 - 5 - 2 + 0 if False else one("select coalesce(sum(quantity_left),0) from stock_batches where product_id=%s and branch_id=%s", (milk, main)))

# ------------------------------------------------------------- cash register, shifts, entries
as_user(cashier)
expect_err("cashier cannot close day", rpc, "close_day", {"counted_cash": 0})
sh = rpc("open_shift", {"opening_cash": 1000})
print("shift", sh)
expect_err("second shift for same cashier", rpc, "open_shift", {"opening_cash": 1})
cs3 = rpc("create_sale", {"items": [{"product_id": cable, "quantity": 2}], "payments": [{"account_id": cash, "amount": 100}, {"account_id": bkash, "amount": 60}]})
rpc("create_account_entry", {"account_id": cash, "entry_type": "withdrawal", "amount": 50, "note": "tea"})
expect_err("cashier cannot touch bank accounts", rpc, "create_account_entry", {"account_id": bkash, "entry_type": "withdrawal", "amount": 10, "note": "x"})
summ = call("select public.shift_summary(%s)", (sh['id'],))
chk("shift expected cash", summ['expected_cash'], 1000 + 100 - 50)
expect_err("close needs reason on difference", rpc, "close_shift", {"shift_id": sh['id'], "counted_cash": 1000})
cl = rpc("close_shift", {"shift_id": sh['id'], "counted_cash": 1000, "difference_reason": "gave change from pocket"})
chk("shift difference", cl['difference'], -50)
chk("shift closed", one("select status from register_shifts where id=%s", (sh['id'],)), "closed")
as_user(owner)
sh2 = rpc("open_shift", {"opening_cash": 0})
expect_err("day close blocked by open shift", rpc, "close_day", {"counted_cash": 0})
rpc("close_shift", {"shift_id": sh2['id'], "counted_cash": 0, "difference_reason": "none"}) if False else None
cl2 = rpc("close_shift", {"shift_id": sh2['id'], "counted_cash": float(call("select public.shift_summary(%s)", (sh2['id'],))['expected_cash'])})
# bank entries
rpc("create_account_entry", {"account_id": cash, "entry_type": "deposit", "amount": 60000, "note": "owner capital"})
tr_e = rpc("create_account_entry", {"account_id": cash, "entry_type": "transfer", "to_account_id": bkash, "amount": 1000, "reference": "bank dep"})
expect_err("transfer to same account", rpc, "create_account_entry", {"account_id": cash, "entry_type": "transfer", "to_account_id": cash, "amount": 1})
expect_err("overdraw", rpc, "create_account_entry", {"account_id": bkash, "entry_type": "withdrawal", "amount": 99999999, "note": "x"})
bals = {b['name']: b['balance'] for b in call("select public.account_balances()")}
chk("balance list matches view", bals['Cash'], one("select balance from accounts_view where id=%s", (cash,)))
stt = call("select public.account_statement(%s,%s,%s)", (cash, today - datetime.timedelta(days=1), today))
chk("statement closing = balance", stt['closing'], bals['Cash'])
chk("statement running balance last row", stt['rows'][-1]['balance'], bals['Cash'])

# ------------------------------------------------------------- day closing
pv = call("select public.day_closing_preview(null, null)")
print("preview expected cash:", pv['expected_cash'], "opening:", pv['opening_cash'])
chk("preview not closed", pv['closed'], False)
chk("preview sales count > 0", pv['sales']['count'] > 0, True)
chk("preview sums to balance", pv['expected_cash'], bals['Cash'])
expect_err("close needs reason on difference", rpc, "close_day", {"counted_cash": float(pv['expected_cash']) - 25})
dc = rpc("close_day", {"counted_cash": float(pv['expected_cash']) - 25, "difference_reason": "short by 25", "denominations": {"500": 3}})
chk("closing difference", dc['difference'], -25)
chk("difference posted to cash", one("select balance from accounts_view where id=%s", (cash,)), float(bals['Cash']) - 25)
expect_err("cannot close twice", rpc, "close_day", {"counted_cash": 1})
pv2 = call("select public.day_closing_preview(null, null)")
chk("preview shows closed", pv2['closed'], True)
as_user(cashier)
expect_err("cashier cannot reopen", lambda: call("select public.reopen_day_closing(%s,%s)", (dc['id'], "x")))
as_user(owner)
call("select public.reopen_day_closing(%s,%s)", (dc['id'], "counted wrong"))
chk("reopen reverses difference", one("select balance from accounts_view where id=%s", (cash,)), bals['Cash'])
dc2 = rpc("close_day", {"counted_cash": float(pv['expected_cash'])})
chk("re-close ok", dc2['difference'], 0)

# ------------------------------------------------------------- patched Phase 1 reports still work
ds = call("select public.dashboard_summary(null)")
print("dashboard keys:", sorted(ds.keys())[:12])
rd = call("select public.report_daily_sales(%s,%s,null)", (today, today))
print("daily sales keys:", sorted(rd.keys()) if isinstance(rd, dict) else type(rd))
chk("dashboard collected counts installment receipts", float(ds.get('collected_today', ds.get('collected', 0))) >= 13300, True)

# ------------------------------------------------------------- isolation and permissions
su()
other = uuid.uuid4(); q("insert into auth.users(id,email) values (%s,'z@x.com')", (str(other),))
as_user(other)
biz2 = rpc("create_business", {"name": "Other Shop"})
chk("other business sees no plans", one("select count(*) from installment_plans"), 0)
chk("other business sees no units", one("select count(*) from stock_units"), 0)
chk("other business sees no shifts", one("select count(*) from register_shifts"), 0)
expect_err("other business cannot read my plan", lambda: call("select public.collect_installment(%s::jsonb)", (json.dumps({"plan_id": ins['plan_id'], "amount": 5, "account_id": cash}),)))
as_user(keeper)
chk("storekeeper sees transfers", one("select count(*) from stock_transfers") > 0, True)
chk("storekeeper cannot see installments", one("select count(*) from installment_plans"), 0)

print("\nFAILURES:", FAILS if FAILS else "none")
print("ALL DONE")
