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
