import pgserver, psycopg2, json, warnings, uuid, decimal
warnings.filterwarnings("ignore")
srv = pgserver.get_server('/tmp/pgt/data', cleanup_mode=None)
conn = psycopg2.connect(srv.get_uri()); conn.autocommit = True
cur = conn.cursor()
def su(): cur.execute("reset role")
def as_user(uid):
    su(); cur.execute("select set_config('request.jwt.claim.sub', %s, false)", (str(uid),)); cur.execute("set role authenticated")
def q(sql, args=None):
    cur.execute(sql, args)
    try: return cur.fetchall()
    except psycopg2.ProgrammingError: return None
def one(sql, args=None): return q(sql, args)[0][0]
def rpc(fn, payload):
    return one(f"select public.{fn}(%s::jsonb)", (json.dumps(payload),))
def expect_err(label, fn, *a):
    try:
        fn(*a); print("FAIL (no error):", label); return False
    except Exception as e:
        print("ok  err:", label, "->", str(e).split('\n')[0][:90]); return True
def chk(label, got, want):
    g = float(got) if isinstance(got,(int,float,decimal.Decimal)) else got
    w = float(want) if isinstance(want,(int,float,decimal.Decimal)) else want
    print(("ok  " if g==w else "FAIL"), label, got, "" if g==w else f"(want {want})")

su()
owner, cashier, other = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
for u,e in [(owner,'owner@x.com'),(cashier,'cash@x.com'),(other,'other@x.com')]:
    q("insert into auth.users(id,email) values (%s,%s)", (str(u), e))

as_user(owner)
biz = rpc("create_business", {"name":"Test Mart","phone":"017","address":"Dhaka","full_name":"Owner One"})
print("business", biz)
# staff membership (edge function does this with service role)
su()
q("insert into business_members(business_id,user_id,full_name,role,branch_id) select %s,%s,'Cash Ier','cashier',id from branches where business_id=%s", (biz, str(cashier), biz))
as_user(other)
biz2 = rpc("create_business", {"name":"Other Shop"})

as_user(owner)
unit = one("select id from units where short_name='pcs'")
cat = one("select id from categories limit 1")
cash = one("select id from payment_accounts where name='Cash'")
bkash = one("select id from payment_accounts where name='bKash'")
sup = rpc("create_supplier", {"name":"Alpha Traders","opening_balance":1000})
cust = rpc("create_customer", {"name":"Rahim","phone":"01711","opening_balance":500})
walk_err = expect_err("duplicate phone", rpc, "create_customer", {"name":"Dup","phone":"01711"})
pa = one("insert into products(business_id,name,unit_id,category_id,purchase_price,selling_price,low_stock_limit) values (%s,'Phone A',%s,%s,100,150,5) returning id",(biz,unit,cat))
pb = one("insert into products(business_id,name,unit_id,category_id,purchase_price,selling_price,tax_rate) values (%s,'Cable B',%s,%s,50,80,10) returning id",(biz,unit,cat))
ps = one("insert into products(business_id,name,track_stock,selling_price,product_type) values (%s,'Repair Service',false,300,'service') returning id",(biz,))
print("sku auto:", q("select sku from products where id=%s",(pa,)))
print("cust code:", q("select code from customers where id=%s",(cust,)))
chk("supplier opening payable", one("select balance from suppliers_view where id=%s",(sup,)), 1000)
chk("customer opening due", one("select balance from customers_view where id=%s",(cust,)), 500)

# purchase: 10 x 100, 20 x 50, header discount 50, tax 30, other 20 => sub 2000, adj 0 -> total 2000. pay 500 cash
pu = rpc("create_purchase", {"supplier_id":sup,"supplier_invoice_no":"S-1","items":[{"product_id":pa,"quantity":10,"unit_cost":100},{"product_id":pb,"quantity":20,"unit_cost":50}],
  "discount":50,"tax_amount":30,"other_charges":20,"payments":[{"account_id":cash,"amount":500}],"client_ref":str(uuid.uuid4())})
print("purchase", pu)
chk("purchase total", pu['total'], 2000); chk("purchase due", pu['due'], 1500)
chk("stock A", one("select quantity from stock_levels where product_id=%s",(pa,)), 10)
chk("supplier payable", one("select balance from suppliers_view where id=%s",(sup,)), 2500)
chk("cash account balance", one("select balance from accounts_view where id=%s",(cash,)), -500)
dup = rpc("create_purchase", {"supplier_id":sup,"items":[{"product_id":pa,"quantity":1,"unit_cost":1}],"client_ref":"00000000-0000-0000-0000-000000000001"})
dup2 = rpc("create_purchase", {"supplier_id":sup,"items":[{"product_id":pa,"quantity":1,"unit_cost":1}],"client_ref":"00000000-0000-0000-0000-000000000001"})
chk("idempotent purchase", dup2['duplicate'], True)
# undo the extra 1 unit purchase to keep numbers clean
print("avg cost A now:", q("select avg_cost from products where id=%s",(pa,)))
q("update products set avg_cost=100 where id=%s",(pa,)) if False else None

# sale 1 walk-in: A x2 @150 disc 10 ; B x3 @80 ; invoice discount 20
cr = str(uuid.uuid4())
s1 = rpc("create_sale", {"items":[{"product_id":pa,"quantity":2,"unit_price":150,"discount":10},{"product_id":pb,"quantity":3,"unit_price":80}],
   "invoice_discount":20,"payments":[{"account_id":cash,"amount":533.09}],"client_ref":cr})
print("sale1", s1)
r = q("select subtotal,item_discount,invoice_discount,net_amount,tax_amount,total,paid_amount,due_amount from sales where id=%s",(s1['id'],))[0]
print("sale1 row", r)
# manual: lines: A gross300 disc10 => 290; B gross240 => 240; sub1=530; D=20 ratio=.0377358; A net=279.06; B net=230.94; tax B=23.09 (10% of 230.94=23.094)
chk("sale1 total", s1['total'], 279.06+230.94+23.09)
# overpay protection
expect_err("overpay", rpc, "create_sale", {"items":[{"product_id":pa,"quantity":1}],"payments":[{"account_id":cash,"amount":999}]})
expect_err("walk-in due", rpc, "create_sale", {"items":[{"product_id":pa,"quantity":1}],"payments":[]})
expect_err("insufficient stock", rpc, "create_sale", {"items":[{"product_id":pa,"quantity":100}],"payments":[{"account_id":cash,"amount":1}]})
s1b = rpc("create_sale", {"items":[{"product_id":pa,"quantity":1}],"payments":[{"account_id":cash,"amount":150}],"client_ref":cr})
chk("idempotent sale", s1b['duplicate'], True)

# sale 2: customer, service item + A x1, pay 100 bkash, rest due
s2 = rpc("create_sale", {"customer_id":cust,"items":[{"product_id":pa,"quantity":1},{"product_id":ps,"quantity":1}],"payments":[{"account_id":bkash,"amount":100}]})
print("sale2", s2)
chk("sale2 total", s2['total'], 450); chk("sale2 due", s2['due'], 350)
chk("customer balance", one("select balance from customers_view where id=%s",(cust,)), 850)
chk("stock A after sales", one("select quantity from stock_levels where product_id=%s",(pa,)), 10+1-2-1)  # +1 from dup purchase

# customer payment 600: FIFO -> sale2 due 350 fully; remaining 250 unallocated (opening due has no invoice)
pm = rpc("record_customer_payment", {"customer_id":cust,"amount":600,"account_id":cash,"note":"partial"})
print("payment", pm)
chk("allocated", pm['allocated'], 350); chk("unallocated", pm['unallocated'], 250)
chk("sale2 due after", one("select due_amount from sales where id=%s",(s2['id'],)), 0)
chk("customer balance after", one("select balance from customers_view where id=%s",(cust,)), 250)

# sale 3 to customer fully due: B x2
s3 = rpc("create_sale", {"customer_id":cust,"items":[{"product_id":pb,"quantity":2}],"payments":[]})
chk("s3 total", s3['total'], 176)
# return 1 B from s3, credit mode: reduces due by 88
item3 = one("select id from sale_items where sale_id=%s",(s3['id'],))
rt = rpc("create_sales_return", {"sale_id":s3['id'],"refund_mode":"credit","reason":"faulty","items":[{"sale_item_id":item3,"quantity":1,"condition":"damaged"}]})
print("return", rt)
chk("return total", rt['total'], 88); chk("due adjusted", rt['due_adjusted'], 88)
chk("s3 due", one("select due_amount from sales where id=%s",(s3['id'],)), 88)
chk("damaged bucket B", one("select damaged_quantity from stock_levels where product_id=%s",(pb,)), 1)
expect_err("over-return", rpc, "create_sales_return", {"sale_id":s3['id'],"refund_mode":"credit","items":[{"sale_item_id":item3,"quantity":5}]})
# cash refund on s1 (walk-in) of 1 A
item1 = q("select id from sale_items where sale_id=%s and product_name='Phone A'",(s1['id'],))[0][0]
rt2 = rpc("create_sales_return", {"sale_id":s1['id'],"refund_mode":"cash","refund_account_id":cash,"items":[{"sale_item_id":item1,"quantity":1,"condition":"resellable"}]})
print("return2", rt2); chk("refund = total", rt2['refund'], rt2['total'])
expect_err("void with returns", lambda: q("select public.void_sale(%s,'x')",(s1['id'],)))

# void sale 2? has later payment allocation -> allowed; customer ends with advance
q("select public.void_sale(%s,'wrong entry')",(s2['id'],))
print("customer balance after void s2:", one("select balance from customers_view where id=%s",(cust,)))

# adjust stock, expense
q("select public.adjust_stock(%s,null,5,'opening','Opening')",(pb,))
expect_err("adjust no reason", lambda: q("select public.adjust_stock(%s,null,1,'loss',null)",(pb,)))
q("select public.adjust_stock(%s,null,2,'damage','dropped')",(pb,))
ex = rpc("create_expense", {"title":"Shop rent","amount":2000,"account_id":cash,"category_id":one("select id from expense_categories where name='Shop Rent'")})

print("--- reports")
dash = rpc("dashboard_summary", {}) if False else one("select public.dashboard_summary(null)")
print(json.dumps(dash))
print(json.dumps(one("select public.sales_trend(current_date-2,current_date,null)")))
print(json.dumps(one("select public.top_products(current_date-30,current_date,null,5)")))
print(json.dumps(one("select public.top_categories(current_date-30,current_date,null,5)")))
rep = one("select public.report_daily_sales(current_date-1,current_date,null)")
print(json.dumps(rep))
print(json.dumps(one("select public.stock_report(null,'all',null,50,0)"))[:600])
print(json.dumps(one("select public.stock_report(null,'attention',null,50,0)"))[:300])
print(json.dumps(one("select public.customer_summary(%s)",(cust,))))
print(json.dumps(one("select public.supplier_summary(%s)",(sup,))))
sp = rpc("record_supplier_payment", {"supplier_id":sup,"amount":2000,"account_id":cash})
print("supplier payment", sp); chk("supplier payable after", one("select balance from suppliers_view where id=%s",(sup,)), 501)

print("--- permissions / RLS")
as_user(cashier)
expect_err("cashier void", lambda: q("select public.void_sale(%s,'x')",(s3['id'],)))
expect_err("cashier purchase", rpc, "create_purchase", {"supplier_id":sup,"items":[{"product_id":pa,"quantity":1,"unit_cost":1}]})
expect_err("cashier discount", rpc, "create_sale", {"items":[{"product_id":pa,"quantity":1,"discount":5}],"payments":[{"account_id":cash,"amount":145}]})
cs = rpc("create_sale", {"items":[{"product_id":pa,"quantity":1}],"payments":[{"account_id":cash,"amount":150}]})
print("cashier sale ok", cs['invoice_no'])
expect_err("cashier direct insert sale", lambda: q("insert into sales(business_id,branch_id,invoice_no) select business_id, branch_id,'X' from business_members where user_id=auth.uid()"))
expect_err("cashier insert product", lambda: q("insert into products(business_id,name) select business_id,'x' from business_members where user_id=auth.uid()"))
print("cashier dashboard profit visible:", one("select public.dashboard_summary(null)")['profit'])
as_user(other)
chk("other sees 0 sales", one("select count(*) from sales"), 0)
chk("other sees own products 0", one("select count(*) from products"), 0)
expect_err("other void foreign sale", lambda: q("select public.void_sale(%s,'x')",(s3['id'],)))
as_user(owner)
chk("owner sees products", one("select count(*) from products"), 3)
print("activity log rows:", one("select count(*) from activity_log"))
print("ALL DONE")
