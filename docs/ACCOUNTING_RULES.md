# Accounting rules (single source of truth)

Every report, dashboard figure and printed document follows these rules. Change them here and in `supabase/migrations/0004_reports.sql` together.

## Sale

- Line gross = quantity x unit price.
- Line net before invoice discount = gross - line discount.
- The invoice discount is spread across lines in proportion to their net value.
- Tax per line = line net after discounts x product tax rate. Tax is added on top (tax exclusive prices).
- Invoice total = sum of line net + sum of line tax.
- All amounts are rounded half up to the paisa at line level. The app uses integer paisa to match.
- Cost snapshot: each sale line stores the product's average cost at that moment. History does not change when costs change later.

## Payments and dues

- Paid = sum of payments taken at the sale. Due = total - paid. A due needs a customer and the "sell on credit" permission.
- Later collections are allocated to invoices oldest first, or to invoices the user chooses. Any excess stays as customer advance.
- A payment's reference is unique per payment record, so one payment is never counted twice.

## Returns

- Return value = the line's net and tax in proportion to the quantity returned.
- Item condition decides where stock goes: resellable adds to available stock, damaged to damaged stock, needs inspection to inspection stock.
- The return first reduces the invoice's due. The rest is refunded in money or kept as customer credit.

## Void

- Voiding restores stock, reverses payments taken at the sale and removes the sale from reports. A sale with returns cannot be voided.

## Purchase

- Items total = sum of (quantity x unit cost - line discount).
- Total = items total - purchase discount + VAT + other charges.
- Landed cost per unit = line value + that line's share of (VAT + other charges - discount), divided by quantity.
- Average cost after a purchase = (on-hand quantity x current average + received quantity x landed unit cost) / (on-hand + received).

## Reports

| Figure | Definition |
|---|---|
| Sales | Sum of completed sale totals (tax included). Returns are shown separately. |
| Net sales | Sales - sales returns |
| Revenue ex tax | Sale line net - returned line net |
| Cost of goods sold | Sale line cost snapshot - returned cost snapshot |
| Gross profit | Revenue ex tax - cost of goods sold |
| Net profit (Phase 3) | Gross profit - approved expenses |
| Collected | Receipts at sale + due collections - payments refunded by voided sales |
| Customer due | Sum of positive customer balances |
| Supplier payable | Sum of positive supplier balances |
| Stock value | Positive on-hand quantity x average cost |

Dates use the business time zone (default Asia/Dhaka). A day runs midnight to midnight in that zone.


## Phase 2 rules

### Installment sales (business rules 3, 4 and 14)
- The invoice total is the value of the goods. Revenue is recognised at the sale, like any sale.
- Down payment = payments taken at the sale. Financed amount = total - down payment.
- Service charge is extra on top of the goods. It is stored on the sale (`finance_charge`) and posted to the customer
  ledger as `finance_charge`. Plan total payable = financed amount + service charge, split into the schedule.
- `sales.due_amount` = total + service charge - paid. Collections add to `paid_amount`.
- The schedule is equal parts rounded down to the paisa, with the remainder on the last installment, or a custom list that
  must add up exactly to the total payable.
- A collection pays the oldest unpaid installments first (or the ones chosen). Money beyond the plan stays on the customer
  account as advance.
- Changing a due date needs a reason and keeps the old date. The original date is never overwritten.
- Generic customer payments never allocate to installment invoices.
- An installment sale can be voided only while no installment has been collected.

### Returns on installment sales
- The returned value (price after discount, plus tax, pro-rata per unit) is credited to the customer. The part up to the
  sale's remaining due (`min(due, returned value)`) is taken off the unpaid schedule: unpaid installments are reduced
  starting from the last due date, a fully covered installment with nothing paid is cancelled, one with a part paid is
  closed at the amount paid. Installments already paid are never changed.
- The plan's total payable drops by that amount and `returned_amount` records it, so outstanding = total payable - paid
  stays correct everywhere (lists, reports, customer ledger).
- Anything the customer has already paid beyond the new total is refunded (cash, from the chosen account) or kept as
  customer credit, exactly like a normal return.
- The service charge is not reduced by a return. It is part of what the customer agreed to pay.
- When every unit on the sale is back and the plan still asks for more than the goods credit covered (the service charge
  is larger than what the customer paid), the rest is written off as an `adjustment` entry in the customer ledger, so a
  returned product never leaves a debt. The shop therefore keeps the service charge only up to what the customer paid.
- When the schedule has nothing left to pay: the plan is `completed` after a partial return, `cancelled` after a full
  return. Collecting on either is blocked.
- Exchange on an installment sale uses the same rule; only credit beyond the plan's remaining due is available for the new
  items.

### Return period
- Business setting `return_window_days` (0 = no limit) counts calendar days in the business time zone from the invoice
  date, for returns and exchanges. After it, the return needs the permission `returns.override_window` (managers have it
  by default). A return made under the override is logged as `sale.return_override`.

### SKU rules
- Business settings `sku_prefix` (letters and digits, up to 8, default P) and `sku_digits` (3 to 10, default 6) shape the
  SKU made for a product saved without one: `PREFIX-000001`. A SKU that is already taken is skipped, so saving never
  fails on a clash. The counter can only be moved forward (`set_sku_start`), so a number is never issued twice.
- `barcode_prefix` (2 to 6 digits, default 20) is the start of generated EAN-13 barcodes. Codes starting with 2 are
  reserved for in-store use and cannot clash with manufacturer barcodes.

### Serial, IMEI and batches
- IMEI = 15 digits with a valid check digit, unique across the business. A serial is unique per product.
- Quantity of a serial or IMEI product always equals the number of units. Every sale, return, void, transfer and
  adjustment moves the same units, and each move is kept as a history event.
- Batches are consumed earliest expiry first. Stock that pre-dates batch tracking has no batch and is consumed last.
- Cost of goods sold still uses the product average cost snapshot, also for IMEI products.

### Transfers, purchase return, exchange
- Stock leaves the sending location when the transfer is sent and arrives when it is received. Missing quantity is written
  off with a reason when a transfer is closed short.
- Purchase return credit = line total pro-rata. Header discount, tax and other charges are not credited. The credit first
  reduces the purchase due; the rest is refunded in cash or kept as supplier credit.
- Exchange: the returned value becomes `exchange_credit` on the new invoice, so only the difference moves money.
  Any leftover is refunded or kept as customer credit. Exchange invoices cannot be voided.

### Cash register and day closing (business rule 15)
- Shift expected cash = opening cash + all cash movements by that cashier in that branch during the shift. A shift
  difference is recorded for review and is not posted.
- A day cannot be closed while a shift of that branch is open. The cash figure is final only after closing.
- Closing compares counted cash with the system cash balance and posts the difference as a `cash_difference` movement at
  the end of that day. Reopening reverses that movement and keeps the old record.
- Cash accounts may go negative (shops often start without an opening balance). Bank and mobile banking accounts cannot.
