"""Phase 2 completion scenario (migration 0014): customer view columns, return period, returns on installment sales,
SKU rules, password check and document records. Run after apply_migrations.py. Prints ok / FAIL per check."""
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
def rpc(fn, payload): return one(f"select public.{fn}(%s::jsonb)", (json.dumps(payload, default=str),))
def call(sql, args=None): return one(sql, args)
def expect_err(label, fn, *a, contains=None):
    try:
        fn(*a); print("FAIL (no error):", label); FAILS.append(label); return False
    except Exception as e:
        msg = str(e).split('\n')[0]
        if contains and contains.lower() not in msg.lower():
            print("FAIL (wrong error):", label, "->", msg[:120]); FAILS.append(label); return False
        print("ok  err:", label, "->", msg[:100]); return True
def chk(label, got, want):
    g = float(got) if isinstance(got, (int, float, decimal.Decimal)) and not isinstance(got, bool) else got
    w = float(want) if isinstance(want, (int, float, decimal.Decimal)) and not isinstance(want, bool) else want
    ok = (g == w) if not isinstance(g, float) else abs(g - w) < 0.006
    print(("ok  " if ok else "FAIL"), label, got, "" if ok else f"(want {want})")
    if not ok: FAILS.append(label)
def imei(base14):
    s = str(base14).zfill(14); total = 0
    for i, ch in enumerate(reversed(s)):
        d = int(ch)
        if i % 2 == 0:
            d *= 2
            if d > 9: d -= 9
        total += d
    return s + str((10 - total % 10) % 10)

# ------------------------------------------------------------- setup
su()
owner, manager, cashier, keeper = (uuid.uuid4() for _ in range(4))
for u, e in [(owner, 'o3@x.com'), (manager, 'm3@x.com'), (cashier, 'c3@x.com'), (keeper, 'k3@x.com')]:
    q("insert into auth.users(id,email) values (%s,%s)", (str(u), e))
as_user(owner)
biz = rpc("create_business", {"name": "Finish Mart", "phone": "017", "address": "Dhaka", "full_name": "Owner Three"})
su()
for uid, name, role in [(manager, 'Man Ager', 'manager'), (cashier, 'Cash Ier', 'cashier'), (keeper, 'Store Keeper', 'storekeeper')]:
    q("insert into business_members(business_id,user_id,full_name,role,branch_id) select %s,%s,%s,%s,id from branches where business_id=%s", (biz, str(uid), name, role, biz))
q("insert into role_permissions(business_id, role, permission) select %s, r.role, p from (values ('manager'),('cashier'),('storekeeper')) r(role), unnest(app.default_permissions(r.role)) p on conflict do nothing", (biz,))
q("insert into role_permissions(business_id, role, permission) values (%s,'cashier','returns.create') on conflict do nothing", (biz,))
chk("manager gets override permission by default", one("select count(*) from role_permissions where business_id=%s and role='manager' and permission='returns.override_window'", (biz,)), 1)
chk("cashier has no override permission", one("select count(*) from role_permissions where business_id=%s and role='cashier' and permission='returns.override_window'", (biz,)), 0)

as_user(owner)
unit = one("select id from units where short_name='pcs'")
cat = one("select id from categories limit 1")
cash = one("select id from payment_accounts where name='Cash'")
sup = rpc("create_supplier", {"name": "Finish Supplier"})
today = one("select app.today(%s)", (biz,))
cable = one("insert into products(business_id,name,unit_id,category_id,purchase_price,selling_price) values (%s,'Cable',%s,%s,50,80) returning id", (biz, unit, cat))
phone = one("insert into products(business_id,name,unit_id,category_id,purchase_price,selling_price,tracking_type) values (%s,'Phone Z',%s,%s,10000,15000,'imei') returning id", (biz, unit, cat))
im = [imei(36000000000001 + i) for i in range(3)]
rpc("create_purchase", {"supplier_id": sup, "items": [{"product_id": cable, "quantity": 300, "unit_cost": 50},
    {"product_id": phone, "quantity": 3, "unit_cost": 10000, "serials": im}], "payments": [{"account_id": cash, "amount": 45000}]})

# ------------------------------------------------------------- customer view and form fields
c1 = rpc("create_customer", {"name": "Nadia", "phone": "01700000001", "workplace": "City Bank", "emergency_contact_name": "Mother",
                              "emergency_contact_phone": "01900000001", "reminders_enabled": False})
row = q("select workplace, emergency_contact_name, emergency_contact_phone, reminders_enabled from customers_view where id=%s", (c1,))[0]
chk("view shows workplace", row[0], "City Bank")
chk("view shows emergency contact", (row[1], row[2]), ("Mother", "01900000001"))
chk("reminders off from create", row[3], False)
q("update customers set reminders_enabled = true, workplace = 'Head Office' where id=%s", (c1,))
row = q("select workplace, reminders_enabled from customers_view where id=%s", (c1,))[0]
chk("update reaches the view", row, ("Head Office", True))
chk("reminders default on", one("select reminders_enabled from customers_view where id=%s", (rpc("create_customer", {"name": "Plain", "phone": "01700000002"}),)), True)

# ------------------------------------------------------------- return period
su(); q("update businesses set settings = settings || %s::jsonb where id=%s", (json.dumps({"return_window_days": 7}), biz)); as_user(cashier)
old = rpc("create_sale", {"items": [{"product_id": cable, "quantity": 3}], "payments": [{"account_id": cash, "amount": 240}]})
su(); q("update sales set sale_date = sale_date - interval '10 days' where id=%s", (old['id'],)); as_user(cashier)
old_item = one("select id from sale_items where sale_id=%s", (old['id'],))
expect_err("cashier blocked after the return period", rpc, "create_sales_return",
           {"sale_id": old['id'], "items": [{"sale_item_id": old_item, "quantity": 1}], "refund_account_id": cash}, contains="return period")
as_user(manager)
r = rpc("create_sales_return", {"sale_id": old['id'], "items": [{"sale_item_id": old_item, "quantity": 1}], "refund_account_id": cash})
chk("manager override works", r['late_override'], True)
su(); chk("override is logged", one("select count(*) from activity_log where business_id=%s and action='sale.return_override'", (biz,)), 1)
as_user(cashier)
as_user(cashier)
fresh = rpc("create_sale", {"items": [{"product_id": cable, "quantity": 2}], "payments": [{"account_id": cash, "amount": 160}]})
fresh_item = one("select id from sale_items where sale_id=%s", (fresh['id'],))
r = rpc("create_sales_return", {"sale_id": fresh['id'], "items": [{"sale_item_id": fresh_item, "quantity": 1}], "refund_account_id": cash})
chk("cashier can return inside the period", r['late_override'], False)
su(); q("update businesses set settings = settings || %s::jsonb where id=%s", (json.dumps({"return_window_days": 0}), biz)); as_user(cashier)
r = rpc("create_sales_return", {"sale_id": old['id'], "items": [{"sale_item_id": old_item, "quantity": 1}], "refund_account_id": cash})
chk("zero means no limit", r['total'], 80)

# ------------------------------------------------------------- return on an installment sale (partial, then more)
as_user(owner)
cust = rpc("create_customer", {"name": "Karim Two", "phone": "01700000003"})
first = str(today + datetime.timedelta(days=30))
ins = rpc("create_installment_sale", {"customer_id": cust, "items": [{"product_id": cable, "quantity": 50}],
    "payments": [{"account_id": cash, "amount": 1000}],
    "installment": {"count": 4, "frequency": "monthly", "first_due_date": first, "service_charge": 400}})
chk("plan payable", ins['total_payable'], 3400)
rpc("collect_installment", {"plan_id": ins['plan_id'], "amount": 850, "account_id": cash})
item = one("select id from sale_items where sale_id=%s", (ins['id'],))
stock0 = one("select quantity from stock_levels where product_id=%s", (cable,))
r1 = rpc("create_sales_return", {"sale_id": ins['id'], "items": [{"sale_item_id": item, "quantity": 10}], "refund_account_id": cash})
chk("return 1 applied to plan", r1['due_adjusted'], 800)
chk("return 1 no refund", r1['refund'], 0)
chk("plan payable reduced", one("select total_payable from installment_plans where id=%s", (ins['plan_id'],)), 2600)
chk("plan remembers returned value", one("select returned_amount from installment_plans_view where id=%s", (ins['plan_id'],)), 800)
chk("last installment shrinks", one("select amount from installment_items where plan_id=%s and seq=4", (ins['plan_id'],)), 50)
chk("earlier installments untouched", one("select count(*) from installment_items where plan_id=%s and seq in (2,3) and amount=850", (ins['plan_id'],)), 2)
chk("unpaid schedule equals outstanding", one("select sum(amount - paid_amount) from installment_items where plan_id=%s and status in ('pending','partial')", (ins['plan_id'],)),
    one("select outstanding from installment_plans_view where id=%s", (ins['plan_id'],)))
chk("customer balance follows", one("select balance from customers_view where id=%s", (cust,)), 1750)
chk("stock came back", one("select quantity from stock_levels where product_id=%s", (cable,)), float(stock0) + 10)
chk("plan still active", one("select status from installment_plans where id=%s", (ins['plan_id'],)), "active")

cash_b = one("select balance from accounts_view where id=%s", (cash,))
r2 = rpc("create_sales_return", {"sale_id": ins['id'], "items": [{"sale_item_id": item, "quantity": 30}], "refund_account_id": cash})
chk("return 2 clears the plan", r2['due_adjusted'], 1750)
chk("return 2 refunds the excess", r2['refund'], 650)
chk("refund left the cash account", one("select balance from accounts_view where id=%s", (cash,)), float(cash_b) - 650)
chk("plan completes when nothing is left", one("select status from installment_plans where id=%s", (ins['plan_id'],)), "completed")
chk("paid installment kept", one("select status from installment_items where plan_id=%s and seq=1", (ins['plan_id'],)), "paid")
chk("later installments cancelled", one("select count(*) from installment_items where plan_id=%s and status='cancelled'", (ins['plan_id'],)), 3)
chk("balance back to zero", one("select balance from customers_view where id=%s", (cust,)), 0)
r3 = rpc("create_sales_return", {"sale_id": ins['id'], "items": [{"sale_item_id": item, "quantity": 10}], "refund_account_id": cash})
chk("last units refunded in full", r3['refund'], 800)
chk("completed plan stays completed", one("select status from installment_plans where id=%s", (ins['plan_id'],)), "completed")
chk("customer ends at zero", one("select balance from customers_view where id=%s", (cust,)), 0)
chk("shop keeps the service charge paid", one("select sum(debit) - sum(credit) from customer_ledger where customer_id=%s and entry_type in ('sale','payment','return','refund','finance_charge','adjustment')", (cust,)), 0)
expect_err("cannot return more than sold", rpc, "create_sales_return", {"sale_id": ins['id'], "items": [{"sale_item_id": item, "quantity": 1}], "refund_account_id": cash}, contains="left to return")
expect_err("collect on a completed plan", rpc, "collect_installment", {"plan_id": ins['plan_id'], "amount": 10, "account_id": cash})

# full return while the plan is active: leftover balance is written off, plan is cancelled
ins2 = rpc("create_installment_sale", {"customer_id": cust, "items": [{"product_id": cable, "quantity": 10}],
    "payments": [{"account_id": cash, "amount": 100}],
    "installment": {"count": 2, "frequency": "weekly", "service_charge": 200}})
chk("plan 2 due", one("select due_amount from sales where id=%s", (ins2['id'],)), 900)
item2 = one("select id from sale_items where sale_id=%s", (ins2['id'],))
r = rpc("create_sales_return", {"sale_id": ins2['id'], "items": [{"sale_item_id": item2, "quantity": 10}], "refund_account_id": cash})
chk("goods credit", r['total'], 800)
chk("leftover written off", r['written_off'], 100)
chk("nothing refunded", r['refund'], 0)
chk("plan cancelled after full return", one("select status from installment_plans where id=%s", (ins2['plan_id'],)), "cancelled")
chk("no unpaid installments left", one("select count(*) from installment_items where plan_id=%s and status in ('pending','partial')", (ins2['plan_id'],)), 0)
chk("customer owes nothing", one("select balance from customers_view where id=%s", (cust,)), 0)
chk("sale shows nothing due", one("select due_amount from sales where id=%s", (ins2['id'],)), 0)
chk("write-off is in the ledger", one("select count(*) from customer_ledger where customer_id=%s and entry_type='adjustment'", (cust,)), 1)

# exchange on an installment sale: the goods credit pays down the plan, so the new items are paid in full
ins3 = rpc("create_installment_sale", {"customer_id": cust, "items": [{"product_id": cable, "quantity": 20}],
    "payments": [{"account_id": cash, "amount": 400}], "installment": {"count": 3, "frequency": "monthly", "first_due_date": first}})
item3 = one("select id from sale_items where sale_id=%s", (ins3['id'],))
ex = rpc("create_exchange", {"sale_id": ins3['id'], "return_items": [{"sale_item_id": item3, "quantity": 5, "condition": "resellable"}],
    "new_sale": {"items": [{"product_id": cable, "quantity": 3}]}, "payments": [{"account_id": cash, "amount": 240}],
    "refund_mode": "cash", "refund_account_id": cash})
chk("exchange credit goes to the plan, none left for new items", ex['credit_used'], 0)
chk("customer paid the new items in cash", ex['customer_paid'], 240)
chk("plan payable after exchange", one("select total_payable from installment_plans where id=%s", (ins3['plan_id'],)), 800)
chk("plan balance after exchange", one("select outstanding from installment_plans_view where id=%s", (ins3['plan_id'],)), 800)

# IMEI unit on an installment sale comes back with the return
ins4 = rpc("create_installment_sale", {"customer_id": cust, "items": [{"product_id": phone, "quantity": 1, "serials": [im[0]]}],
    "payments": [{"account_id": cash, "amount": 5000}], "installment": {"count": 2, "frequency": "monthly", "first_due_date": first}})
chk("unit sold", one("select status from stock_units where serial_no=%s", (im[0],)), "sold")
item4 = one("select id from sale_items where sale_id=%s", (ins4['id'],))
expect_err("serial return needs the number", rpc, "create_sales_return", {"sale_id": ins4['id'], "items": [{"sale_item_id": item4, "quantity": 1}], "refund_account_id": cash}, contains="serial")
r = rpc("create_sales_return", {"sale_id": ins4['id'], "items": [{"sale_item_id": item4, "quantity": 1, "serials": [im[0]], "condition": "resellable"}], "refund_account_id": cash})
chk("unit back in stock", one("select status from stock_units where serial_no=%s", (im[0],)), "in_stock")
chk("down payment refunded", r['refund'], 5000)
chk("phone plan cancelled", one("select status from installment_plans where id=%s", (ins4['plan_id'],)), "cancelled")

# ------------------------------------------------------------- customer reminder switch reaches the reminder list
as_user(owner)
quiet = rpc("create_customer", {"name": "Quiet Customer", "phone": "01700000009", "reminders_enabled": False})
rq = rpc("create_installment_sale", {"customer_id": quiet, "items": [{"product_id": cable, "quantity": 5}],
    "payments": [{"account_id": cash, "amount": 100}],
    "installment": {"count": 2, "frequency": "monthly", "first_due_date": str(today)}})
listed = lambda cid: [r for r in call("select public.installment_reminders()") if r['customer_id'] == cid]
chk("reminders off: customer not listed", len(listed(quiet)), 0)
q("update customers set reminders_enabled = true where id=%s", (quiet,))
chk("reminders on: customer listed", len(listed(quiet)), 1)

# ------------------------------------------------------------- SKU rules
su(); q("update businesses set settings = settings || %s::jsonb where id=%s", (json.dumps({"sku_prefix": "ez", "sku_digits": 4}), biz)); as_user(owner)
mk = lambda sku=None: one("insert into products(business_id,name,unit_id,category_id,purchase_price,selling_price,sku) values (%s,'Auto',%s,%s,1,2,%s) returning sku", (biz, unit, cat, sku))
last = int(call("select public.sku_counter()"))
chk("prefix and digits applied", mk(), f"EZ-{last + 1:04d}")
call("select public.set_sku_start(%s)", (200,))
chk("start number moves the counter", mk(), "EZ-0200")
expect_err("counter cannot go backwards", lambda: call("select public.set_sku_start(%s)", (50,)), contains="higher")
mk("EZ-0201")
chk("taken codes are skipped", mk(), "EZ-0202")
chk("typed SKU is kept", mk("MY-CODE"), "MY-CODE")
su(); q("update businesses set settings = settings || %s::jsonb where id=%s", (json.dumps({"sku_prefix": "!!", "sku_digits": 99}), biz)); as_user(owner)
chk("bad prefix falls back, digits capped at 10", mk(), "P-0000000203")
as_user(cashier)
expect_err("cashier cannot change numbering", lambda: call("select public.set_sku_start(%s)", (900,)))

# ------------------------------------------------------------- password confirmation
su(); q("update auth.users set encrypted_password = 'stub:' || md5('Secret123') where id=%s", (str(owner),)); as_user(owner)
chk("right password", call("select public.verify_password(%s)", ("Secret123",)), True)
chk("wrong password", call("select public.verify_password(%s)", ("nope",)), False)
chk("empty password", call("select public.verify_password(%s)", ("",)), False)
su(); q("update auth.users set encrypted_password = 'stub:' || md5('Cash1234') where id=%s", (str(cashier),)); as_user(cashier)
for _ in range(5): call("select public.verify_password(%s)", ("bad",))
expect_err("locked after five wrong tries", lambda: call("select public.verify_password(%s)", ("Cash1234",)), contains="too many")
as_user(owner)
chk("lock is per user", call("select public.verify_password(%s)", ("Secret123",)), True)
chk("failures are not readable by users", one("select count(*) from password_check_failures"), 0)

# ------------------------------------------------------------- document records (files themselves live in storage)
as_user(cashier)
su(); q("delete from password_check_failures"); as_user(cashier)
d1 = rpc("add_document", {"entity_type": "customer", "entity_id": cust, "doc_type": "nid_front", "storage_path": f"{biz}/customer/{cust}/nid.jpg", "file_name": "nid.jpg"})
chk("cashier lists customer documents", one("select count(*) from documents where entity_id=%s", (cust,)), 1)
expect_err("path must start with own business", rpc, "add_document", {"entity_type": "customer", "entity_id": cust, "storage_path": f"{uuid.uuid4()}/customer/{cust}/x.jpg"}, contains="path")
expect_err("cashier cannot attach supplier files", rpc, "add_document", {"entity_type": "supplier", "entity_id": sup, "storage_path": f"{biz}/supplier/{sup}/x.pdf"})
as_user(keeper)
chk("storekeeper cannot see customer documents", one("select count(*) from documents"), 0)
expect_err("storekeeper cannot add customer documents", rpc, "add_document", {"entity_type": "customer", "entity_id": cust, "storage_path": f"{biz}/customer/{cust}/y.jpg"})
as_user(owner)
d2 = rpc("add_document", {"entity_type": "supplier", "entity_id": sup, "doc_type": "bill", "storage_path": f"{biz}/supplier/{sup}/bill.pdf", "file_name": "bill.pdf"})
pur = one("select id from purchases limit 1")
rpc("add_document", {"entity_type": "purchase", "entity_id": pur, "doc_type": "bill", "storage_path": f"{biz}/purchase/{pur}/b.pdf"})
chk("owner sees all attachments", one("select count(*) from documents"), 3)
path = call("select public.delete_document(%s)", (d2,))
chk("delete returns the storage path", path, f"{biz}/supplier/{sup}/bill.pdf")
chk("delete is logged", one("select count(*) from activity_log where action='document.delete'"), 1)

# ------------------------------------------------------------- isolation
su(); other = uuid.uuid4(); q("insert into auth.users(id,email) values (%s,'z3@x.com')", (str(other),)); as_user(other)
rpc("create_business", {"name": "Other Three"})
chk("other business sees no documents", one("select count(*) from documents"), 0)
chk("other business sees no customers in the view", one("select count(*) from customers_view"), 0)
expect_err("other business cannot return my sale", rpc, "create_sales_return", {"sale_id": ins['id'], "items": [{"sale_item_id": item, "quantity": 1}], "refund_account_id": cash})

print("\nFAILURES:", FAILS if FAILS else "none")
print("ALL DONE")
