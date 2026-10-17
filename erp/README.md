# ERP — Inventory & Sales

A cross-platform ERP for inventory and sales, with **one Flutter codebase** that runs on
**Web, Android and iOS**, talking to a **REST API** backed by **PostgreSQL**.

This lives in `erp/` alongside the original Java/Swing warehouse app at the repository root,
which is left untouched.

```
erp/
  backend/   Node.js + TypeScript + Express + Prisma + PostgreSQL REST API
  app/       Flutter client (web + Android + iOS)
```

---

## 1. What it does

| Area | Capabilities |
| --- | --- |
| **Identity** | Email/password login, JWT access tokens, rotating refresh tokens, 6 roles with granular permissions |
| **Catalogue** | Products (SKU, barcode, unit, cost/sale price, tax rate, reorder level), categories, multi-currency |
| **Warehousing** | Multiple warehouses and bin/shelf locations |
| **Inventory** | Stock by location, receive, dispatch, adjust, transfer, cycle count, full movement audit trail, low-stock alerts, valuation |
| **Purchasing** | Suppliers, purchase orders, approval, partial/full goods receipt (auto-updates stock + posting) |
| **Sales** | Customers (**each linked to a sales representative / مندوب**), sales orders, confirmation, partial/full fulfilment (auto-deducts stock), returns-ready movement types |
| **POS** | One-shot point-of-sale: sale → stock → invoice → payment, with change calculation |
| **Billing** | Invoices (standalone or from a sales order), issue/void, **edit drafts**, customer balances |
| **Payments** | Customer receipts (invoice-allocation or on-account) and supplier payments |
| **Accounting** | Double-entry ledger, chart of accounts, automatic postings from receiving/invoicing/payments, trial balance |
| **Reports** | Dashboard KPIs, sales over time, inventory valuation, top products, customer/supplier balances, **receivables per salesperson**, **supplier payables**, **stock balance (quantity + value)**, **per-product item movement** with date filter, **account statements** |
| **Documents** | Every report and document is **printable**: invoices, customer/supplier statements, sales, valuation, top products, receivables-by-salesperson, supplier payables, stock balance and item movement |
| **Languages** | English and **Arabic (RTL)** with an in-app **EN / العربية** switch; printed documents follow the same language (`&lang=ar` renders RTL Arabic) |
| **Settings** | Company profile, base currency, document number prefixes, default tax rate, **tax on/off switch**, and **dashboard layout** (choose which dashboard sections to show) |
| **Statements** | Dedicated statement builder: pick a customer **or** supplier (searchable), choose a date range, then view or print — reached from Reports → Statements |
| **Currencies** | Multi-currency seeded with USD, EUR, GBP, AED and **EGP (Egyptian Pound)** |
| **Salespeople** | Link each customer to a **sales representative (مندوب)** in the customer form, filter customers and the receivables report by representative |

---

## 2. Architecture

```
   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
   │  Flutter Web │   │   Android    │   │     iOS      │
   └──────┬───────┘   └──────┬───────┘   └──────┬───────┘
          │                  │                  │
          └──────────── HTTPS + JWT Bearer ─────┘
                             │
                    ┌────────▼─────────┐
                    │  REST API (Node) │  /api/v1
                    │  Express + Zod   │
                    └────────┬─────────┘
                             │  Prisma ORM
                    ┌────────▼─────────┐
                    │   PostgreSQL     │
                    └──────────────────┘
```

- The API is stateless; every request carries `Authorization: Bearer <accessToken>`.
- Access tokens are short-lived; refresh tokens are opaque, hashed at rest and rotated on use.
- Stock changes and money movements are written inside database transactions.

---

## 3. Prerequisites

| Tool | Version | Needed for |
| --- | --- | --- |
| Node.js | 18.18+ (20 LTS recommended) | backend |
| npm | 9+ | backend |
| PostgreSQL | 14+ (or Docker) | database |
| Flutter SDK | 3.29+ (Dart 3.7+) | client |

Docker is optional but the quickest way to get PostgreSQL running.

---

## 4. Run the backend

```powershell
cd erp\backend

# 1. Install dependencies
npm install

# 2. Start PostgreSQL (skip if you already have one)
docker compose up -d

# 3. Configure environment
copy .env.example .env      # then edit secrets if you like

# 4. Create the schema and sample data
npm run prisma:push         # creates tables (use prisma:migrate for versioned migrations)
npm run seed                # loads demo products, sales, invoices, ledger

# 5. Start the API
npm run dev                 # http://localhost:4000/api/v1
```

Other useful scripts:

```powershell
npm run build               # compile TypeScript to dist/
npm start                   # run the compiled server
npm run prisma:migrate      # create a versioned migration
npm run studio              # browse the database in Prisma Studio
npm run db:reset            # drop, re-migrate and re-seed
```

### 4a. Local PostgreSQL without Docker (the setup on this machine)

Docker is not installed here, so PostgreSQL 16 runs from portable binaries that need no
admin rights. Everything lives under `%LOCALAPPDATA%\erp-tools`:

| Thing | Path |
| --- | --- |
| PostgreSQL binaries | `C:\Users\abosa\AppData\Local\erp-tools\pg-extract\pgsql` |
| Database cluster (data) | `C:\Users\abosa\AppData\Local\erp-tools\pgdata` |
| Server log | `C:\Users\abosa\AppData\Local\erp-tools\pg.log` |
| Portable Node.js | `C:\Users\abosa\AppData\Local\erp-tools\node-v24.20.0-win-x64` |

The cluster is already initialised, the `erp` role and `erp` database exist, the schema is
pushed and the demo data is seeded. **On a fresh boot, start PostgreSQL first:**

```powershell
$pg   = "C:\Users\abosa\AppData\Local\erp-tools\pg-extract\pgsql"
$data = "C:\Users\abosa\AppData\Local\erp-tools\pgdata"

# start (add this to a .cmd if you want one click)
& "$pg\bin\pg_ctl.exe" -D $data -l "C:\Users\abosa\AppData\Local\erp-tools\pg.log" -o "-p 5432" start

# check / stop
& "$pg\bin\pg_ctl.exe" -D $data status
& "$pg\bin\pg_ctl.exe" -D $data stop
```

`psql` is at `$pg\bin\psql.exe` (connect with `-h localhost -U erp -d erp`).

The portable Node also has to be on `PATH` for any `npm` command, and PowerShell blocks
`npm.ps1`, so call `npm.cmd` (or `.\node_modules\.bin\*.cmd`) directly:

```powershell
$env:Path = "C:\Users\abosa\AppData\Local\erp-tools\node-v24.20.0-win-x64;" + $env:Path
cd erp\backend
npm.cmd run dev
```

**Full start-up order:** start PostgreSQL → `cd erp\backend; npm.cmd run dev` →
`cd erp\app; flutter run -d chrome`.

### Default accounts (after `npm run seed`)

Password for **all** demo users: `Password123`

| Email | Role | Sees |
| --- | --- | --- |
| `admin@erp.local` | ADMIN | everything |
| `manager@erp.local` | MANAGER | most operations |
| `cashier@erp.local` | CASHIER | POS, sales, invoices, payments |
| `warehouse@erp.local` | WAREHOUSE | inventory, warehouses, purchasing |
| `accountant@erp.local` | ACCOUNTANT | invoices, payments, accounting, reports |

---

## 5. Run the Flutter client

The client points at `http://localhost:4000/api/v1` by default; you can change the URL on the
login screen (it is remembered on the device).

```powershell
cd erp\app
flutter pub get

flutter run -d chrome                          # web
flutter run -d <device-id>                     # Android (or iOS on macOS)
```

See `erp/app/README.md` for platform-specific notes (Android emulator uses
`10.0.2.2` instead of `localhost`, iOS builds require macOS, web needs CORS enabled).

### 5a. Language (English / العربية)

The client ships with **English and Arabic** translations. Use the **translate** button in the
top app bar (or on the login screen) to switch; the choice is remembered on the device. Choosing
Arabic automatically flips the whole interface to **RTL**. Translations live in
`erp/app/lib/core/l10n.dart` (a small hand-written `AppStrings` class + `LocalizationsDelegate`,
no code generation).

### 5b. Printing from the client

Printing uses `url_launcher` to open the backend's printable HTML pages in the system browser
(`Print` actions on invoices, statements and reports). Give the client reachable API host — the
printer URL is derived from the configured base URL, so on a phone the base URL must be your
machine's LAN IP (or `10.0.2.2` on the Android emulator), not `localhost`.

---

## 6. API reference (all under `/api/v1`)

| Method & path | Purpose |
| --- | --- |
| `POST /auth/login` · `POST /auth/refresh` · `POST /auth/logout` · `GET /auth/me` | authentication |
| `GET/POST /users` · `GET/PATCH/DELETE /users/:id` · `GET /users/salespersons` | user administration; `/users/salespersons` lists the assignable sales representatives (any **active** user whose role may sell) |
| `GET/POST /products` · `GET/PATCH/DELETE /products/:id` · `GET /products/barcode/:code` | catalogue |
| `GET/POST /categories` · `PATCH/DELETE /categories/:id` | categories |
| `GET/POST /warehouses` · `GET/PATCH/DELETE /warehouses/:id` · `GET/POST /warehouses/:id/locations` | warehouses |
| `GET /locations` · `PATCH/DELETE /locations/:id` | locations |
| `GET /inventory/stock` · `GET /inventory/movements` · `GET /inventory/low-stock` | stock views |
| `POST /inventory/receive` · `/dispatch` · `/adjust` · `/transfer` · `/cycle-count` | stock operations |
| `GET/POST /suppliers` · `GET/PATCH/DELETE /suppliers/:id` | suppliers |
| `GET/POST /purchase-orders` · `GET/PATCH /purchase-orders/:id` · `POST /:id/approve` · `/receive` · `/cancel` | purchasing |
| `GET/POST /customers` · `GET/PATCH/DELETE /customers/:id` | customers (optional `salespersonId` on create/update, filter with `?salespersonId=`, payloads include `salesperson { id, name }`) |
| `GET/POST /sales-orders` · `GET/PATCH /sales-orders/:id` · `POST /:id/confirm` · `/fulfill` · `/cancel` | sales |
| `POST /pos/sale` | point of sale |
| `GET/POST /invoices` · `GET /invoices/:id` · `PATCH /invoices/:id` · `POST /:id/issue` · `/:id/void` | billing (PATCH edits a **draft**) |
| `GET/POST /payments` | payments |
| `GET/POST /currencies` · `PATCH/DELETE /currencies/:id` | currencies |
| `GET /reports/dashboard` · `/sales` · `/inventory-valuation` · `/top-products` · `/customer-balances` · `/supplier-balances` | reporting |
| `GET /reports/receivables-by-salesperson` · `/supplier-payables` | outstanding balances (`?from=&to=`, receivables also accept `?userId=`) |
| `GET /reports/stock-balance` · `/item-movement` | on-hand quantity **and** value (`?warehouseId=&categoryId=`); item movement needs `?productId=` and accepts `?from=&to=&warehouseId=` |
| `GET /reports/customers/:id/statement` · `GET /reports/suppliers/:id/statement` | account statements (`?from=&to=`) |
| `GET /print/invoices/:id` · `/print/customers/:id/statement` · `/print/suppliers/:id/statement` · `/print/reports/{sales,inventory-valuation,top-products,receivables-by-salesperson,supplier-payables,stock-balance,item-movement}` | printable HTML documents (all accept `&lang=en\|ar`) |
| `GET/POST /accounting/accounts` · `GET /accounting/journal` · `/journal/:id` · `/trial-balance` | accounting |
| `GET/PATCH /settings` | settings |

**Response shape**

```jsonc
// list
{ "data": [ /* ... */ ], "meta": { "page": 1, "pageSize": 20, "total": 42, "totalPages": 3 } }
// single
{ "data": { /* ... */ } }
// error (non-2xx)
{ "error": { "message": "…", "code": "VALIDATION_ERROR", "details": { /* … */ } } }
```

### 6a. Printing (documents & reports)

The client opens a self-contained HTML page in the system browser and the user prints it (or
saves it as PDF) from there — the same page works on web, Android and iOS. Because the browser
cannot send an `Authorization` header, these routes accept the access token as a `?token=`
query parameter (a `Bearer` header also works):

```
GET /api/v1/print/invoices/:id?token=<accessToken>
GET /api/v1/print/customers/:id/statement?token=<accessToken>&from=&to=
GET /api/v1/print/suppliers/:id/statement?token=<accessToken>&from=&to=
GET /api/v1/print/reports/sales?token=<accessToken>&from=&to=&groupBy=day|month
GET /api/v1/print/reports/inventory-valuation?token=<accessToken>&warehouseId=
GET /api/v1/print/reports/top-products?token=<accessToken>&from=&to=&limit=
GET /api/v1/print/reports/receivables-by-salesperson?token=<accessToken>&from=&to=&userId=
GET /api/v1/print/reports/supplier-payables?token=<accessToken>&from=&to=
GET /api/v1/print/reports/stock-balance?token=<accessToken>&warehouseId=&categoryId=
GET /api/v1/print/reports/item-movement?token=<accessToken>&productId=&from=&to=&warehouseId=
```

Add `&lang=ar` to any print URL to render it in Arabic (RTL). The access token may also be sent
as `Authorization: Bearer <token>` instead of `?token=`.

Every value interpolated into the HTML is escaped; the pages include `@media print` styles.

### 6b. Account statements

`GET /reports/customers/:id/statement` and `GET /reports/suppliers/:id/statement` return a
ledger for the partner:

```jsonc
{ "data": {
  "customer": { "id": "…", "name": "…", "balance": 38.62, "creditLimit": 0 },
  "from": null, "to": null, "openingBalance": 0,
  "rows": [ { "date": "…", "type": "INVOICE", "number": "INV-2026-00001",
              "description": "…", "debit": 88.62, "credit": 0, "balance": 88.62 } ],
  "totals": { "debit": 88.62, "credit": 50, "closingBalance": 38.62 }
} }
```

Customer rows: non-void invoices are **debits**, inbound payments are **credits** (outbound
refunds are debits). Supplier rows: non-cancelled purchase orders are **credits**, outbound
payments are **debits**. The running `balance` walks from `openingBalance`.

**Building a statement in the client:** Reports → *Statements* → *Customer statement* /
*Supplier statement* opens a picker (searchable list of partners) plus a date range. Choosing a
partner and a range opens the statement; the same screen has a Print button.

### 6c. Extended reports

All of these are read-only, need `reports.read`, and are printable via the URLs in §6a.

```jsonc
// GET /reports/receivables-by-salesperson?from=&to=&userId=
// Attribution: the customer's assigned salesperson (مندوب) wins; when the
// customer has none, the creator of the sales order is used instead.
{ "data": {
  "rows": [ { "salespersonId": "…", "salesperson": "…" /* null → unassigned */,
              "customerId": "…", "customer": "…", "invoices": 2,
              "total": 88.62, "paid": 50, "balance": 38.62 } ],
  "totals": { "invoices": 2, "total": 88.62, "paid": 50, "balance": 38.62 } } }

// GET /reports/supplier-payables?from=&to=
{ "data": {
  "rows": [ { "supplierId": "…", "supplier": "…", "phone": "…",
              "purchaseOrders": 1, "purchases": 120, "paid": 24.48, "balance": 95.52 } ],
  "totals": { "purchaseOrders": 1, "purchases": 120, "paid": 24.48, "balance": 95.52 } } }

// GET /reports/stock-balance?warehouseId=&categoryId=
{ "data": {
  "rows": [ { "productId": "…", "sku": "STA-001", "name": "…", "unit": "pc",
              "category": "…", "warehouseId": "…", "warehouse": "Main Warehouse",
              "quantity": 40, "reserved": 0, "available": 40,
              "unitCost": 0.5, "costValue": 20, "salePrice": 2.2, "retailValue": 88 } ],
  "totals": { "quantity": 604, "reserved": 0, "available": 604,
              "costValue": 680.4, "retailValue": 1400 } } }

// GET /reports/item-movement?productId=&from=&to=&warehouseId=
{ "data": {
  "product": { "id": "…", "sku": "STA-001", "name": "…", "unit": "pc", "unitCost": 0.5 },
  "warehouseId": null, "from": null, "to": null,
  "opening": { "quantity": 0, "value": 0 },
  "rows": [ { "date": "…", "type": "RECEIVE", "reference": "OPENING",
              "warehouse": "Main Warehouse", "location": "Aisle 1",
              "quantity": 40, "dir": "IN", "in": 40, "out": 0,
              "balance": 40, "unitCost": 0, "value": 0 } ],
  "totals": { "in":    { "quantity": 40, "value": 0 },
              "out":   { "quantity": 0,  "value": 0 },
              "closing": { "quantity": 40, "value": 0 },
              "inQty": 40, "outQty": 0, "inValue": 0, "outValue": 0,
              "closingQty": 40, "closingValue": 0 } } }
```

### 6d. Tax switch and dashboard layout

`GET/PATCH /settings` now also carries:

| Field | Type | Meaning |
| --- | --- | --- |
| `taxEnabled` | `boolean` (default `true`) | When `false`, **every** new/edited sales order, purchase order and invoice line has an effective `taxRate` of `0`, so `taxTotal` is `0`. Already-issued documents are untouched. |
| `dashboardWidgets` | `string \| null` | JSON array of the dashboard section keys to show: `["kpis","quickActions","lowStock","recentMovements"]`. `null`/blank/invalid → show all; an explicit `[]` → show none. |

Both are editable in the client under **Settings → Company** (the tax switch and a *Dashboard
layout* card with one switch per section). Toggling a dashboard section off immediately changes
the dashboard.

### 6e. Linking a customer to a salesperson (المندوب)

A customer can be assigned to **one sales representative**:

| Where | How |
| --- | --- |
| **Customers → open a customer** | Pick a *Salesperson* in the form (the list is `GET /users/salespersons`). Leave it at *Unassigned* to clear the link. |
| **Customers list** | The tile shows `Salesperson: <name>`; the *Salesperson* dropdown above the list filters with `GET /customers?salespersonId=…`. |
| **Reports → Receivables by salesperson** | Each receivable is attributed to **the customer's assigned representative**, falling back to the creator of the sales order when the customer has none. The tab has a *Salesperson* filter (sent as `?userId=`, also honoured by the printable version). |

Who counts as a salesperson: any **active** user whose role may sell (`sales.write`) — that is
ADMIN, MANAGER, SALES and CASHIER. The candidates come from `GET /users/salespersons`:

```jsonc
// GET /users/salespersons   (requires customers.read)
{ "data": [ { "id": "…", "name": "Mona Manager", "email": "manager@erp.local", "role": "MANAGER" } ] }

// POST /customers  ·  PATCH /customers/:id
{ "name": "احمد سعد", "salespersonId": "…" }        // null clears the assignment

// GET /customers      → each record gains:  "salesperson": { "id": "…", "name": "Mona Manager" } | null
```

---

## 7. Roles and permissions

Permission strings are grouped per role in `backend/src/lib/permissions.ts`; the API enforces
them per route and the client hides navigation the user cannot access.

| Permission group | ADMIN | MANAGER | SALES | CASHIER | WAREHOUSE | ACCOUNTANT |
| --- | :-: | :-: | :-: | :-: | :-: | :-: |
| catalogue | ✔ | ✔ | read | read | read | read |
| inventory ops | ✔ | ✔ | – | – | ✔ | – |
| purchasing | ✔ | ✔ | – | – | ✔ | read |
| sales / POS | ✔ | ✔ | ✔ | ✔ | – | read |
| invoices | ✔ | ✔ | read | ✔ | – | ✔ |
| payments | ✔ | ✔ | – | ✔ | – | ✔ |
| accounting | ✔ | read | – | – | – | ✔ |
| reports | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| users / settings write | ✔ | – | – | – | – | – |

---

## 8. Data model (Prisma)

`User`, `RefreshToken`, `Currency`, `Category`, `Product`, `Warehouse`, `Location`,
`StockLevel`, `StockMovement`, `Supplier`, `PurchaseOrder(+Line)`, `Customer`,
`SalesOrder(+Line)`, `Invoice(+Line)`, `Payment`, `Account`, `JournalEntry(+Line)`,
`Sequence`, `Setting`.

Key invariants:

- `StockMovement.quantity` is a **signed delta**; `StockLevel.quantity` is the running total.
- Every stock change and every ledger posting is inside a transaction.
- Document numbers come from a `Sequence` row (`SO-2026-00001`, `INV-…`, `PO-…`, `PAY-…`, `JE-…`).
- `Customer.salespersonId` → `User` (nullable, `ON DELETE SET NULL`); when a customer is assigned a
  representative their outstanding receivables are reported under that representative.
- Receiving posts *Debit Inventory / Credit Accounts Payable*; issuing an invoice posts
  *Debit Receivable, Credit Revenue, Credit Tax Payable* (+ *Debit COGS / Credit Inventory*);
  payments post against Cash/Bank.

---

## 9. Deploying

> 🚀 **المسار الموصى به:** [`erp/DEPLOY-DOCKER.md`](DEPLOY-DOCKER.md) — صورة **Docker واحدة** فيها
> الـ API + موقع Flutter معًا (**رابط واحد**، من غير CORS) على Koyeb / Hugging Face / Railway،
> مع قاعدة بيانات مجانية على Neon. خطوات بالعربي + استكشاف أخطاء.
>
> 🔙 [`erp/DEPLOY.md`](DEPLOY.md) — البديل: Render + Neon (ملف `render.yaml` في جذر الريبو).

Whatever the host, it is one Docker image built from the **repository root** `Dockerfile`:
it contains the compiled API **and** the Flutter web bundle (`erp/web`), served from the same
origin — so `https://<host>` is the app and `https://<host>/api/v1` is the API.

Environment the container expects: `DATABASE_URL`, `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`,
`NODE_ENV=production`. It runs `prisma db push` on boot, then starts the server on `$PORT` (4000).

### Manual / any other host

- **API**: `npm run build` then run `dist/server.js` (Dockerfile included). Set `DATABASE_URL`,
  `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `CORS_ORIGIN` and `NODE_ENV=production`.
  On boot/warm-up the platform sets `PORT` — the server binds to it automatically.
- **Database**: for a brand-new database use `npx prisma db push`; for versioned migrations run
  `npm run prisma:deploy` on release.
- **Web client**: `flutter build web --release --dart-define=API_BASE=https://api.example.com/api/v1`
  then serve the output folder as static files. The committed `erp/web/` is exactly that output.
- **Android**: `flutter build apk --release --dart-define=API_BASE=…` (or `appbundle` for Play Store).
- **iOS**: `flutter build ipa` on macOS with Xcode.

---

## 10. Known limitations (v1)

- Quantities are whole numbers (no fractional units such as 0.5 kg yet).
- Multi-currency stores the document currency and an exchange rate; consolidated reporting
  converts at the stored rate but there is no realised/unrealised FX gain handling.
- No file uploads/images storage backend yet (`Product.imageUrl` is a plain URL).
- No barcode-scanner plugin wired into the Flutter app yet (manual barcode entry and
  `/products/barcode/:code` lookup exist).
- Reports aggregate in the API; very large datasets will want SQL-level aggregation/pagination.
