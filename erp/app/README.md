# ERP Flutter client

A single **Flutter** codebase that runs on **Web, Android and iOS** and talks to the
`erp/backend` REST API (`/api/v1`). It covers catalogue, inventory, purchasing, sales,
POS, billing, payments, reporting, accounting, settings and users.

- Flutter 3.29.2 · Dart 3.7.2
- Dependencies: `http`, `provider`, `intl`, `shared_preferences` (plus the generated
  `cupertino_icons`). No native-code plugins, no charts, no code generation.

---

## 1. Quick start

Make sure the backend is running first (see [`../README.md`](../README.md) section 4), then:

```powershell
cd erp\app
flutter pub get
flutter run -d chrome        # Web (Chrome)
flutter run -d <device-id>   # Android device/emulator (or iOS on macOS)
```

List the available targets with `flutter devices`.

### Default accounts (after `npm run seed` in the backend)

Password for every demo user: `Password123`

| Email | Role |
| --- | --- |
| `admin@erp.local` | ADMIN |
| `manager@erp.local` | MANAGER |
| `cashier@erp.local` | CASHIER |
| `warehouse@erp.local` | WAREHOUSE |
| `accountant@erp.local` | ACCOUNTANT |

---

## 2. Pointing the app at the backend

The API base URL defaults to `http://localhost:4000/api/v1`.

You can change it **on the login screen** (the “Server” field). The value is persisted in
`shared_preferences` under the key `api_base_url` and reused on the next launch.

Platform notes:

| Target | Base URL to use | Why |
| --- | --- | --- |
| Web (`flutter run -d chrome`) | `http://localhost:4000/api/v1` | Backend must allow the browser origin via `CORS_ORIGIN`. |
| Android emulator | `http://10.0.2.2:4000/api/v1` | `10.0.2.2` is the host machine from inside the emulator. |
| Android device (USB) | `http://<your-lan-ip>:4000/api/v1` | Use your computer's LAN IP; the phone must reach it. |
| iOS simulator (macOS) | `http://localhost:4000/api/v1` | Shares the host loopback. |
| Physical iPhone | `http://<your-lan-ip>:4000/api/v1` | Plus the cleartext/ATS notes below. |

> **Cleartext HTTP in debug:** Android and iOS block plain HTTP by default. During
> development either allow cleartext for the debug build or run the backend behind HTTPS.
> For Android, add `android:usesCleartextTraffic="true"` to the debug manifest; for iOS, an
> ATS exception in `Info.plist`. Production deployments should use HTTPS.

---

## 3. Build

```powershell
flutter build web              # -> build/web (serve as static files)
flutter build apk              # Android APK
flutter build appbundle        # Android App Bundle for Play Store
flutter build ipa              # iOS (requires macOS + Xcode)
```

---

## 4. Static analysis & tests

```powershell
flutter analyze    # should print: No issues found!
flutter test       # smoke test only (the app talks to a live API)
```

---

## 5. Project structure

```
lib/
  main.dart                 Root widget: providers + session gate (splash / login / shell)
  core/
    config.dart             API base URL (default + shared_preferences persistence)
    api_client.dart         HTTP wrapper: JWT header, envelope decoding, 401 refresh+retry
    api_exception.dart      Typed errors surfaced to the UI
    session.dart            Tokens, current user, roles → permissions
    theme.dart              Material 3 light/dark themes
    formatters.dart         Money / number / date / status helpers (intl)
    json_utils.dart         Defensive JSON coercion helpers
  models/                   Plain Dart models (fromJson / toJson) incl. paginated.dart
  state/                    One ChangeNotifier per feature + ProductCatalog
  features/
    auth/                   login_screen.dart
    shell/                  app_shell.dart (role-filtered nav), navigation.dart
    dashboard/ products/ categories/ inventory/ warehouses/ suppliers/
    purchasing/ customers/ sales/ pos/ invoices/ payments/ reports/
    settings/ accounting/
  widgets/                  async_list_view, money_text, status_chip, empty_state,
                            error_view, confirm_dialog, form_fields, section_card,
                            order_lines_editor
```

### Conventions

- **Auth:** `Authorization: Bearer <token>`. On HTTP 401 the client refreshes once and
  retries; if the refresh fails the session is cleared and the login screen is shown.
- **Envelopes:** lists → `{ data: [...], meta: { page, pageSize, total, totalPages } }`;
  objects → `{ data: { ... } }`; errors → `{ error: { message, code, details } }`.
  `error.message` is always surfaced in the UI.
- **Lists:** every list screen has loading / empty / error states, a debounced search box
  and infinite pagination (pull-to-refresh + “load more”).
- **Forms:** validated client-side, API errors shown in a snackbar, submit disabled while
  saving, success snackbar afterwards.
- **Money & dates:** formatted with `intl`; each document uses its own currency code when
  present, otherwise the settings base currency.
- **Roles:** the shell only shows destinations the signed-in role can access
  (`ADMIN`, `MANAGER`, `SALES`, `CASHIER`, `WAREHOUSE`, `ACCOUNTANT`).

---

## 6. Notes & known gaps

- The client is intentionally dependency-light: there is **no chart package**, so report
  series and the POS cart are rendered as lists/rows; there is no camera/barcode scanner
  plugin (barcode entry is manual).
- Screens render a bare `Scaffold` body; the `AppShell` owns the `AppBar`/drawer/rail, and
  standalone routes are pushed with a title via `pushScreen(...)`.
- Accounting (chart of accounts, trial balance, journal) and the reports/settings areas are
  read-oriented and fetch the endpoints, but are deliberately simpler than the
  sales/POS/inventory flows.
