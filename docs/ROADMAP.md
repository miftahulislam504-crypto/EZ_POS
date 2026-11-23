# Roadmap and feature coverage

Every feature in the EZ POS feature plan (EZ_POS_Feature_Plan_BN.md) appears below with the phase it ships in.
Status: **Done** = in this release, otherwise the target phase.

Phase 1 Core POS (done) | Phase 2 Installments and advanced inventory (complete in code, see Progress.md) | Phase 3 Intelligence and multi-branch | Phase 4 Advanced retail

## 3. Dashboard
| Feature | Phase |
|---|---|
| Cards: sales, purchases, profit, expenses, collected, customer due, supplier payable, stock value, products and low stock, invoices | Done |
| Cards: installment collection and overdue | 2 |
| Sales chart 7 and 30 days | Done (monthly and yearly views: 3) |
| Top products, top categories, recent sales, recent collections, low stock alerts | Done |
| Recent purchases, recent expenses, branch comparison | 3 |
| Quick actions | Done (collect installment: 2, stock transfer: 2) |
| Widget customization | 3 |

## 4. POS sales
| Feature | Phase |
|---|---|
| Search by name, SKU, barcode; camera and keyboard scanners; categories; image, price, stock | Done |
| Quantity, decimal units (kg, litre), item and invoice discount, VAT, customer select or create, note | Done |
| Hold and resume multiple carts | Done |
| Negative stock block with business setting | Done |
| Payments: cash, bKash, Nagad, Rocket, bank, card, custom, split, partial, credit, change | Done |
| Invoice: unique number, shop details, customer, lines, VAT, payments, due, cashier, QR with invoice number | Done |
| 58 mm, 80 mm thermal and A4 PDF via the system print dialog; share; reprint | Done |
| Shop logo on printed invoice | 2 |
| Direct Bluetooth, USB, network ESC/POS printing | 2 |
| Installment sale type | 2 |

## 5. Customers
| Feature | Phase |
|---|---|
| Profile: name, phones, email, addresses, NID number, birth date, occupation, group, notes, code | Done |
| Photo and NID document upload with restricted access | 2 |
| Ledger with debit, credit, running balance, references | Done |
| Totals, last purchase and payment dates, aging buckets | Done |
| Receive payment: oldest first or chosen invoices, advance, receipt print and share | Done |
| Payment correction with approval | 2 |
| SMS and WhatsApp confirmations | 3 |
| Groups, wholesale price applied automatically | Done |
| Group price lists, group discounts | 4 |
| Top customer report | 3 |

## 6. Installment sales (all of section 6)
Down payment, schedules, custom schedule, guarantor and reference details, collection, partial and early payment, reminders, reports, settings: **Phase 2**.

## 7. Purchases
| Feature | Phase |
|---|---|
| Purchase entry: supplier, items, discounts, VAT, other charges, date, supplier invoice number, note | Done |
| Full, partial or no payment (credit), landed cost, average cost | Done |
| Purchase list, detail, print | Done |
| Attachment of supplier bill | 2 |
| Batch, serial, IMEI at purchase | 2 |
| Purchase return | 2 |
| Draft, ordered, partial receive, cancel (purchase orders) | 4 |

## 8. Suppliers
| Feature | Phase |
|---|---|
| Profile, ledger, payables, aging, payment with allocation, voucher | Done |
| Supplier documents | 2 |
| Payable list and payment reminders | 3 |

## 9. Products
| Feature | Phase |
|---|---|
| Name, image, SKU, barcode, category and subcategory, brand, model, unit, purchase, selling, wholesale, minimum price, VAT, warranty, supplier, low stock limit, status | Done |
| Standard and service items | Done |
| Serial, IMEI, batch, expiry tracking | 2 |
| Variable (size, colour) and combo products | 4 |
| Special, group, branch, promotional prices, price history, discount limits with approval | 3 and 4 |
| Barcode generate, scan, label print | Done |

## 10. Inventory
| Feature | Phase |
|---|---|
| Current, available, damaged, low, out of stock, valuation, movements | Done |
| Adjustments: opening, add, remove, damaged, lost, expired, with reason and history | Done |
| Physical count and system vs actual comparison | 2 |
| Stock transfer between branches and warehouses | 2 (branches UI: 3) |
| Adjustment approval | 3 |
| Expiry alerts, IMEI duplicate warning | 2 |
| Reorder suggestion, min and max levels | 4 |
| Reserved stock | 4 |

## 11. Returns and refunds
| Feature | Phase |
|---|---|
| Sales return: partial or full, reason, condition, stock, refund or credit | Done |
| Exchange, return policy window | 2 |
| Return approval | 3 |
| Purchase return | 2 |
| Refund receipt | 2 |

## 12. Expenses
| Feature | Phase |
|---|---|
| Categories, entry, payment method, spent by, note, recurring flag, void with reason, totals by category | Done |
| Receipt attachment | 2 |
| Automatic recurring entries, approval flow | 3 |
| Reports by branch and employee | 3 |

## 13. Cash and bank
| Feature | Phase |
|---|---|
| Payment accounts with live balances, every payment recorded per account | Done |
| Cash register, shifts, expected vs actual, day closing | 2 |
| Bank and MFS deposit, withdrawal, transfer, statement | 2 |

## 14. Reports
| Feature | Phase |
|---|---|
| Daily sales and profit, payment method breakdown | Done |
| Stock valuation and low stock | Done |
| Weekly, monthly, yearly; product, category, brand, customer, cashier, branch sales | 3 |
| Profit and loss, purchase, due aging, collection reports | 3 |
| Export to PDF, Excel, CSV; saved reports | 3 |

## 15. Multi-branch and warehouse
Schema is ready (branch on every record). Branch management, warehouses, branch POS and stock, consolidated dashboard: **Phase 3**.

## 16. Employees, roles, permissions
| Feature | Phase |
|---|---|
| Team members, role, status, employee ID, create and deactivate accounts, reset password | Done |
| Editable permission matrix per role | Done |
| Activity log recorded for sales, payments, stock, voids | Done (viewer: 3) |
| Branch restriction per user | 3 |

## 17. Notifications
In-app low stock list is Done. Push, SMS, WhatsApp, email, templates, customer reminders: **Phase 3**.

## 18 and 19. Mobile and web experience
| Feature | Phase |
|---|---|
| Bottom navigation, mobile POS, customer, inventory flows, camera scanner, PDF share | Done |
| Responsive tablet and desktop layout with sidebar, web POS with scanner | Done |
| Keyboard shortcuts | 2 |
| Offline draft and sync queue | 3 |
| Bulk import and export, report builder, template settings for notifications | 3 |

## 20. Settings
| Feature | Phase |
|---|---|
| Business profile, logo, currency BDT, time zone | Done |
| Invoice prefixes, negative stock, credit sales, customer required, default VAT, footer and terms | Done |
| Units, categories, brands, payment methods | Done |
| Receipt paper size and auto print | Done |
| SKU and barcode rules, warehouse settings | 2 and 3 |
| Installment settings | 2 |

## 21. Security and audit
| Feature | Phase |
|---|---|
| Row level security, role based access, void instead of delete, audit entries, deactivation | Done |
| PIN or password confirmation for sensitive actions | 2 (done) |
| Restricted access to NID documents | 2 (done) |
| Export permission, retention and account closure policy | 3 |
| Backups | Supabase Point in Time Recovery (see README) |

## 22. Business rules
Rules 1 to 15 are enforced as of Phase 2 (3, 4, 14 installments, 9 purchase return, 15 day closing). Rule 10 approval for corrections beyond void is part of the Phase 3 approval workflow.

## 24 and Phase 4
Customer portal, online payment links, e-commerce and accounting integrations, warranty and repair tickets, purchase suggestions, smart insights, credit limits and approval, commissions, loyalty, coupons, gift cards, membership, wholesale price lists, supplier catalogs, CRM: **Phase 3 and 4** as listed in the plan.
