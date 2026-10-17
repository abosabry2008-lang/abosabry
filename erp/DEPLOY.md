# 🚀 النشر على الإنترنت — Render + Neon

> 📌 **مسار تاني وأبسط:** صورة **Docker واحدة** فيها الـ API + موقع الويب معًا على **رابط واحد**
> (Koyeb / Hugging Face / Railway) — شوف [`DEPLOY-DOCKER.md`](DEPLOY-DOCKER.md).
> الدليل اللي تحت ده هو خيار Render، وهو بيقدم نفس الشكل: سيرفس واحد فيه كل حاجة.

دليل كامل خطوة بخطوة لرفع الـ ERP (الـ API + تطبيق الويب + قاعدة البيانات) على الإنترنت مجاناً.

**المعمارية بعد النشر**

```
   ┌────────────────────────────────────────────┐
   │  erp (Render Web Service, Node.js)         │
   │                                            │
   │  Flutter Web  ←  https://<host>/           │
   │  Express API  ←  https://<host>/api/v1     │
   └──────────────────────┬─────────────────────┘
                          │  PostgreSQL (SSL)
               ┌──────────▼───────────┐
               │  Neon (PostgreSQL 16)│
               │  مجاني — neon.tech   │
               └──────────────────────┘
```

| المكوّن | المنصة | التكلفة | ملاحظة |
| --- | --- | --- | --- |
| قاعدة البيانات | **Neon** | مجاني | PostgreSQL 16، ينام بعد ~5 دقايق خمول |
| الـ API + الويب | **Render** (Web Service واحد) | مجاني | ينام بعد 15 دقيقة خمول (أول طلب بياخد ~50 ثانية) |

> ⚠️ **مهم:** الخطة المجانية بتخلّي الـ API ينام. أول ما تفتح الموقع بعد فترة خمول، استنى من 30 لـ 60 ثانية لحد ما يصحى. بعدها كل حاجة سريعة.

---

## الخطوة 0 — المتطلبات

- حساب GitHub ✔ (عندك)
- Flutter مثبّت على جهازك (للـ Web build) ✔
- من غير أي بطاقة بنكية للمجاني

---

## الخطوة 1 — رفع الكود على GitHub

من داخل فولدر المشروع:

```powershell
cd "C:\Users\abosa\OneDrive\Documents\Default Project"

git add .
git commit -m "ERP: inventory + sales, ready for deployment"
git push -u origin master
```

هيّفتحلك **Git Credential Manager** نافذة تسجيل دخول GitHub → سجّل دخول ووافق.

> ملف `.gitignore` بيحمي الـ `.env` و`node_modules` و`build` — لكن **مهم جدًا**: `erp/backend/.env` مش بيترفع (فيه أسرار الديفيلوبمنت بس).

---

## الخطوة 2 — قاعدة بيانات Postgres على Neon

1. افتح 👉 **https://neon.tech** واضغط **Sign up** (بحساب GitHub أسهل).
2. من الداشبورد: **Create project**
   - **Name:** `erp`
   - **Postgres version:** 16 أو 17
   - **Region:** `AWS eu-central-1` (فرانكفورت — أقرب لمصر)
3. بعد الإنشاء، هتلاقي **Connection string** — اضغط **Copy**.
   شكلها كده:
   ```
   postgresql://erp_owner:AbC123xyz@ep-cool-name-123456.eu-central-1.aws.neon.tech/neondb?sslmode=require
   ```
4. **غيّر اسم قاعدة البيانات** في آخر الرابط من `neondb` إلى `erp`:
   ```
   .../ep-cool-name-123456.eu-central-1.aws.neon.tech/erp?sslmode=require
   ```
   > السطر ده بتكتبه في ملف مؤقت عندك، هنحتاجه في الخطوة 4.
   >
   > 💡 لو Neon رفض الاتصال بسبب `?sslmode=require`، استخدم الصيغة دي بدالها:
   > `...?ssl=true&sslmode=require`

---

## الخطوة 3 — ربط Render بالريبو (Blueprint)

1. افتح 👉 **https://render.com** → **Sign up / Sign in** بحساب GitHub.
2. **Dashboard → New + → Blueprint**
3. اختر ريبو **`abosabry`** → **Connect**
4. Render هيلاقي ملف `render.yaml` ويقرأ منه.
5. في شاشة الإدخال هيطلب منك قيمة **`DATABASE_URL`**
   (لأنها معلمة بـ `sync: false`) → الزق رابط Neon من الخطوة 2.
6. اضغط **Apply**.

Render هيعمل **سيرفس واحد** `erp` (Node) فيه الـ API + موقع الويب معًا.

⏳ أول نشر بياخد من 3 لـ 6 دقايق.

### استنى لحد ما يخلص وتحقق
- سيرفس `erp` → **Logs**: لازم تشوف
  ```
  Serving the web app from /opt/render/project/src/erp/web
  ERP API ready on http://localhost:10000/api/v1  (production)
  ```
- افتح `https://erp-xxxx.onrender.com/health`
  → لازم ترجع `{"status":"ok","uptime":...}`
- افتح `https://erp-xxxx.onrender.com` → لازم تشوف شاشة تسجيل الدخول (نفس الرابط بالظبط!).

> 📌 **سجّل الرابطين عندك:**
> - الموقع (والتطبيق): `https://____________.onrender.com`
> - الـ API: `https://____________.onrender.com/api/v1`

---

## الخطوة 4 — إدخال البيانات التجريبية (Seed)

قاعدة بيانات Neon جديدة = فاضية. عايز تحمّل بيانات تجريبية (منتجات، عملاء، فواتير، مستخدمين):

1. Render → سيرفس **`erp`** → تاب **Shell** (فوق على اليمين).
2. اكتب:
   ```bash
   npm run seed
   ```
3. استنى لحد ما يخلص (30–60 ثانية).

**حسابات الدخول بعد الـ seed** (الباسورد للكل: `Password123`):

| الإيميل | الصلاحية |
| --- | --- |
| `admin@erp.local` | كل حاجة |
| `manager@erp.local` | معظم العمليات |
| `cashier@erp.local` | كاشير / POS / فواتير |
| `warehouse@erp.local` | مخازن / مشتريات |
| `accountant@erp.local` | فواتير / حسابات / تقارير |

> 🔐 **في الإنتاج: غيّر الباسورات دي فورًا** من صفحة Users، أو عدّل `erp/backend/prisma/seed.ts`.

---

## الخطوة 5 — مفيش حاجة تظبطها (نفس الدومين)

موقع الويب دلوقتي جزء من نفس السيرفس: `erp/web` بيتحمّل في نفس الديبلايمنت، والتطبيق
بيكلّم `/api/v1` **على نفس الدومين** (عنوان الـ API المدمج في النسخة المنشورة هو `/api/v1`).

- موقعك: `https://erp-xxxx.onrender.com`
- الـ API: `https://erp-xxxx.onrender.com/api/v1`
- **مفيش CORS** ولا محتاج تعمل deploy تاني ولا تظبط روابط.

> ⚠️ بس لازم تكون رافع **`erp/web` مبني بـ `-ApiUrl /api/v1`** — اللي هو وضعه الحالي في الريبو.
> لو رجعت تبنيه بعنوان `https://...` هيبقى مربوط بعنوان تاني ومحتاج يرجّع تاني.
>
> عايز تدير الموقع من دومين تاني (مثلاً Netlify/Cloudflare Pages)؟ ساعتها بنّيه بعنوان مطلق:
> ```powershell
> .\erp\deploy\build_web.ps1 -ApiUrl https://erp-xxxx.onrender.com/api/v1
> git add erp/web ; git commit -m "web" ; git push
> ```
> أو اكتب الرابط في خانة **API URL** في شاشة تسجيل الدخول مرة واحدة.

---

## 🧩 استكشاف الأخطاء

| المشكلة | السبب / الحل |
| --- | --- |
| الموقع بيفضل "loading" أول مرة | الـ API نايم (خطة مجانية). استنى ~50 ثانية وحدّث الصفحة. |
| `Failed to fetch` | الموقع والـ API على نفس الدومين (مفيش CORS) — لو ده حصل شوف لوج التشغيل. |
| `Missing required environment variable "DATABASE_URL"` | متغيّر `DATABASE_URL` مش متسجّل في `erp` → Environment → أضفه. |
| API بيرجع 500 وكله على قاعدة البيانات | رابط Neon غلط أو نام. راجع الاتصال من Neon Console. |
| `prisma db push` فشل في الـ build | تأكد إن رابط Neon فيه `?sslmode=require` وإن الـ DB موجودة. |
| تسجيل الدخول يقول invalid credentials | معملتش `npm run seed` (الخطوة 4). |
| تحديث الأسعار/الجلسة بتضيع | دي طبيعة الخطة المجانية؛ الصعود لخطة مدفوعة بيحل الموضوع. |
| عايز أشوف لوجز الـ API | Render → `erp` → **Logs**. |

---

## 🔁 التحديثات بعد النشر (Continuous Deploy)

Render بيعمل deploy تلقائي مع كل `git push` على نفس الفرع:

```powershell
git add .
git commit -m "…"
git push
```

- تغييرات في `erp/backend/**` أو `erp/web/**` → يعيد بناء السيرفس تلقائي.
- تغييرات في كود Flutter (`erp/app/**`) → **لازم** تعيد
  `.\erp\deploy\build_web.ps1 -ApiUrl /api/v1` وترفع `erp/web`
  (لأن البناء بيحصل على جهازك، مش على المنصة).

---

## 🌐 دومين خاص (اختياري)

Render → الخدمة → **Settings → Custom Domains** → **Add Custom Domain** → حط
`erp.yourdomain.com` → Render يديك سجل `CNAME` تحطه عند مزوّد الدومين.

للـ HTTPS: Render بيعمل شهادة SSL مجانية أوتوماتيك.

---

## 📱 تطبيق أندرويد / iOS

نفس الـ API يخدم الموبايل كذلك. عدّل العنوان في `erp/app` أو أدخله من شاشة
تسجيل الدخول، وبعدين:

```powershell
cd erp\app
flutter build apk --release --dart-define=API_BASE=https://erp-xxxx.onrender.com/api/v1
```

> ملاحظة: أندرويد إيميوليتر بيستخدم `10.0.2.2` بدل `localhost` في التطوير المحلي.

---

## 💰 التكاليف

| السيناريو | التكلفة |
| --- | --- |
| Render Free (API نايم بعد 15 دقيقة) | **0$** |
| Neon Free (0.5 GB تخزين) | **0$** |
| Render Starter للـ API (من غير نوم) | ~7$ / شهر |
| Render Postgres مدفوع (بدل Neon) | من ~6$ / شهر |

للإنتاج الحقيقي: ارفع `erp` لخطة Starter (من غير خمول) + Neon أو Render Postgres مدفوع، وخُد نسخ احتياطية دورية.
