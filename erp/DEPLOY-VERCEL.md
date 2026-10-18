# ⚡ النشر على الإنترنت — Vercel + Neon (مجاني بالكامل، من غير بطاقة)

> دليل خطوة بخطوة لرفع الـ ERP كامل (تطبيق Flutter Web + الـ REST API) على **رابط واحد**.
> الخطة المجانية (Hobby) على Vercel **من غير أي بطاقة بنكية**.
> بدائل تانية: [`DEPLOY.md`](DEPLOY.md) (Render) و [`DEPLOY-DOCKER.md`](DEPLOY-DOCKER.md) (Docker/Koyeb).

**المعمارية بعد النشر**

```
              https://erp-xxxx.vercel.app
   ┌───────────────────────────────────────────────┐
   │  Vercel (مجاني)                               │
   │                                               │
   │  Flutter Web  ←  /            (ملفات ثابتة)   │
   │  Express API  ←  /api/v1/*    (Serverless)    │
   └───────────────────────┬───────────────────────┘
                           │  DATABASE_URL (SSL)
                ┌──────────▼───────────┐
                │  Neon (PostgreSQL 16)│
                │  مجاني — neon.tech   │
                └──────────────────────┘
```

| المكوّن | المنصة | التكلفة | ملاحظة |
| --- | --- | --- | --- |
| قاعدة البيانات | **Neon** | مجاني | PostgreSQL 16، بيتعطّل الـ compute بعد خمول ويرجع ببطء أول طلب |
| الويب (ملفات ثابتة) | **Vercel** | مجاني | Flutter build موجود في `erp/web` ويتنسخ لـ `public/` وقت البناء |
| الـ API | **Vercel Functions** | مجاني | كل المسارات `/api/v1/*` في Function واحد |

> 📌 **إيه اللي بيخلي البناء يشتغل من غير إعدادات معقدة؟**
> الملفات اللي في جذر الريبو: `vercel.json` + `package.json` + `api/v1/[[...path]].js`
> + سكربت البناء `erp/deploy/vercel/build.mjs` — دي اللي بتخلّي Vercel يبني الـ TypeScript
> وينسخ الويب لـ `public/` ويشغّل نفس الـ Express اللي عندك.

---

## الخطوة 0 — المتطلبات

- حساب **GitHub** ✔ (عندك)
- حساب **Vercel** (تسجيل بحساب GitHub، **من غير بطاقة بنكية**)
- حساب **Neon** (من غير بطاقة بنكية)
- ملفات الرفع موجودة أصلًا في الريبو (`vercel.json` … إلخ) — لو مش موجودة، شوف قسم
  [ملفات النشر](#ملفات-النشر-اللي-لازم-تكون-فى-الريبو) تحت.

---

## الخطوة 1 — قاعدة البيانات على Neon

1. افتح 👉 **https://neon.tech** → Sign up (بحساب GitHub) → **Create project**.
2. من صفحة المشروع انسخ **Pooled connection string** (اللي فيه `-pooler`):
   ```
   postgresql://neondb_owner:...@ep-xxxx-pooler.c-2.aws.neon.tech/neondb?sslmode=require&channel_binding=require
   ```
3. خُد مفتاحين للأمان (شغّلها مرتين):
   ```powershell
   node -p "require('crypto').randomBytes(48).toString('hex')"
   ```
   → وحدة لـ `JWT_ACCESS_SECRET` والتانية لـ `JWT_REFRESH_SECRET`.

---

## الخطوة 2 — استيراد الريبو على Vercel

1. افتح 👉 **https://vercel.com/new** → سجّل دخول **بحساب GitHub** → وافق على تفويض الريبو.
2. اختار الريبو **`abosabry2008-lang/abosabry`** → Branch `main`.
3. ⚠️ **مهم جدًا:** Vercel ممكن يكتشف المشروع تلقائيًا بوضع **Services** (لأن فيه أكتر من
   application في الريبو) — ده مش هيشتغل على الخطة المجانية. غيّر الـ **Application Preset**
   لـ **Other** (منسدلة جنب اسم المشروع).
4. الإعدادات المطلوبة في نموذج الاستيراد:

   | الحقل | القيمة |
   | --- | --- |
   | Project Name | `erp` (أو أي اسم تحبه) |
   | Root Directory | `./` |
   | Build Command | `npm run build` (بيتعبّى تلقائيًا من `vercel.json`) |
   | Output Directory | `public` |
   | Install Command | `npm install` |

5. في قسم **Environment Variables** ضيف (أو اضيفهم بعدين من إعدادات المشروع):

   | المفتاح | القيمة |
   | --- | --- |
   | `DATABASE_URL` | رابط الـ Neon اللي نسخته في الخطوة 1 |
   | `JWT_ACCESS_SECRET` | المفتاح الأول |
   | `JWT_REFRESH_SECRET` | المفتاح التاني |

6. اضغط **Deploy** واستنى البناء (دقيقة أو اتنين).

> 💡 لو ضيفت متغيرات بيئية **بعد** أول نشر لازم تعمل **Redeploy** عشان تتطبق:
> الإعدادات → Environment Variables → الإشعار «A new deployment is needed…» → **Redeploy**.

---

## الخطوة 3 — التأكد إن كل حاجة شغالة

1. افتح رابط الموقع (مثال: `https://erp-xxxx.vercel.app`) — لازم يفتح واجهة الـ Flutter.
2. افتح `/api/v1/health` — لازم يرجّع JSON بحالة `ok`.
3. لو رجّع `FUNCTION_INVOCATION_FAILED` → افتح
   **Monitoring → Logs** في لوحة Vercel وهتلاقي سبب الخطأ تحت (غالبًا متغيّر بيئي ناقص).

---

## الخطوة 4 — مزامنة الـ Schema + بيانات تجريبية

من جهازك (PowerShell) من فولدر `erp\backend`:

```powershell
$env:DATABASE_URL = "postgresql://neondb_owner:...@ep-xxxx-pooler.../neondb?sslmode=require"
npx prisma db push --skip-generate
npm run seed
```

> لو `npx` اشتغل من غير `--skip-generate` عادي، سيبها زي ما هي.
> الـ seed بيمسح البيانات القديمة وينشئ المستخدمين:

| البريد | الصلاحية |
| --- | --- |
| `admin@erp.local` | ADMIN — كل الصلاحيات |
| `manager@erp.local` | MANAGER |
| `cashier@erp.local` | CASHIER — كاشير |
| `warehouse@erp.local` | WAREHOUSE — المخزن |
| `accountant@erp.local` | ACCOUNTANT — الحسابات |

كلهم: **`Password123`**

---

## الخطوة 5 — التحديث بعدين

كل **push** لـ `main` بيتعمله deploy تلقائيًا:

```powershell
git add .
git commit -m "update"
git push origin main
```

- واجهة الويب بتتغير لو حدّثت `erp/web` (لازم تعيد بناء Flutter Web الأول).
- الـ API بيتحدّث من نفس الريبو (يعني أي تعديل في `erp/backend` + `npm run build` وقت النشر).

---

## ملفات النشر اللي لازم تكون في الريبو

| الملف | وظيفته |
| --- | --- |
| `vercel.json` | إعدادات النشر + SPA fallback لـ `index.html` |
| `package.json` (جذر الريبو) | سكربت `build` اللي Vercel بينفّذه |
| `api/v1/[[...path]].js` | Serverless entry → بيحمّل نفس `createApp()` بتاع Express |
| `erp/deploy/vercel/build.mjs` | البناء: `npm ci` → `prisma generate` → `tsc` → نسخ `erp/web` إلى `public/` |
| `erp/web/` | بناء Flutter Web (اللي بيتحمّل كملفات ثابتة) |

---

## ملاحظات وحدود

- 🔸 **Vercel Hobby مجاني للاستخدام الشخصي/غير التجاري** — لو هتستخدمه في مشروع تجاري
  هتحتاج خطة Pro (مدفوعة). للاستخدام الشخصي والتجربة: مجاني بالكامل ومن غير بطاقة.
- 🔸 Neon بيعلّق الـ compute بعد فترة خمول → أول طلب بعد الخمول بياخد ثواني (5–20 ثانية)
  وبعدها يبقى طبيعي.
- 🔸 رابط الموقع فيه رقم عشوائي (`erp-xxxx.vercel.app`) — تقدر تغيّره من **Settings → Domains**
  أو تضيف دومين خاص بيك.
- 🔸 لو حبيت ترجع لـ Render/Docker: [`DEPLOY.md`](DEPLOY.md) و [`DEPLOY-DOCKER.md`](DEPLOY-DOCKER.md).
