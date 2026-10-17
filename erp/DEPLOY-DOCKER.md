# 🐳 النشر بأي منصة — Docker (بدون Render)

دليل تاني، وده اللي أسلّط ليه النشر دلوقتي: **صورة Docker واحدة** فيها الـ API + موقع Flutter،
يعني **رابط واحد بس** للتطبيق كله (مفيش CORS، ومفيش منصة تانية للموقع).

```
┌──────────────────────────────────────────────────────┐
│  صورة Docker واحدة                                   │
│                                                      │
│   Express API   ←  /api/v1/*                         │
│   Flutter Web   ←  /        (نفس الدومين)           │
│                                                      │
│  اتبنى من الـ Dockerfile اللي في جذر الريبو          │
└──────────────────────────┬───────────────────────────┘
                           │
                           │  DATABASE_URL (SSL)
                 ┌─────────▼──────────┐
                 │  PostgreSQL على    │
                 │  Neon (مجاني)      │
                 └────────────────────┘
```

> 📝 لو حابب ترجع لـ Render: [`erp/DEPLOY.md`](DEPLOY.md) — الخطوات فيه لسه شغالة.

---

## 🗄️ أولاً: قاعدة البيانات (مشتركة مع كل المنصات)

1. افتح 👉 **https://neon.tech** → Sign up (بحساب GitHub) → **Create project**
   - **Name:** `erp`
   - **Region:** `AWS eu-central-1` (أقرب لمصر)
2. انسخ **Connection string**، وغيّر آخر الرابط من `neondb` لـ `erp`:
   ```
   postgresql://erp_owner:AbC123xyz@ep-cool-name-123456.eu-central-1.aws.neon.tech/erp?sslmode=require
   ```
3. خُد **مفتاحين أسرار** لو مش متسجلين عندك:
   ```powershell
   node -p "require('crypto').randomBytes(48).toString('hex')"
   ```
   شغّلها مرتين (واحد لـ `JWT_ACCESS_SECRET` والتاني لـ `JWT_REFRESH_SECRET`).

---

## 🟢 الخيار أ — Koyeb (الأقرب لـ Render)

**الخطوات:**
1. افتح 👉 **https://app.koyeb.com** → Sign in with GitHub.
2. **Create → Web Service** → اختار ريبو **`abosabry`** → Branch `main`.
3. في قسم البناء:
   - **Build method:** Dockerfile
   - **Dockerfile path:** `Dockerfile` (جذر الريبو — معمول خصيصًا)
4. في قسم الـ Environment ضيف:
   | المفتاح | القيمة |
   | --- | --- |
   | `DATABASE_URL` | رابط Neon |
   | `JWT_ACCESS_SECRET` | قيمة عشوائية (من الأمر فوق) |
   | `JWT_REFRESH_SECRET` | قيمة عشوائية تانية |
   | `NODE_ENV` | `production` |
   > محتاج `CORS_ORIGIN`؟ لا — الموقع على نفس الدومين، فمفيش CORS خالص.
5. **Port:** `4000`
6. اضغط **Deploy** (أول بناء ~3–5 دقايق).

**ملاحظات:**
- Koyeb ممكن يطلب كارت بنكي للتأكيد (زي ما هو مكتوب في الأسعار). لو طلب منك كارت
  ومش عندك → انتقل للخيار ب (Hugging Face) تحت، الصورة نفسها هي اللي هتشتغل.
- الخطة المجانية ممكن توقف الحالة بعد فترة خمول؛ أول طلب بياخد 20–60 ثانية.

---

## 🔴 الخيار ب — Hugging Face Spaces (مجاني بدون كارت نهائيًا)

دي طريقة مجربة بدون كارت، وبتصحى لوحدها عند أول طلب (بعد ما تقعد 48 ساعة).

1. افتح 👉 **https://huggingface.co/new-space**
   - **Space name:** `erp-api`
   - **SDK:** `Docker`
   - **Hardware:** `CPU basic - free`
   - **Create Space**
2. Space ده هو برضه repo على هينجنج فيس. نزّل ملفين جاهزين من عندك:
   [`erp/deploy/hf-space/Dockerfile`](deploy/hf-space/Dockerfile) و
   [`erp/deploy/hf-space/README.md`](deploy/hf-space/README.md)
   وارفعهم على الـ Space (أو بالسطور دي من الـ CMD):
   ```powershell
   git clone https://huggingface.co/spaces/<اسمك>/erp-api
   Copy-Item erp\deploy\hf-space\* erp-api\
   cd erp-api
   git add . ; git commit -m "ERP API" ; git push
   ```
3. في صفحة الـ Space: **Settings → Variables and secrets** → ضيف:
   `DATABASE_URL` و `JWT_ACCESS_SECRET` و `JWT_REFRESH_SECRET` و `NODE_ENV=production`
4. المستخدم: `https://<اسمك>-erp-api.hf.space` (التطبيق كامل على الرابط ده).

> لو صلاحية الـ Space العامة مزعجتك، خصوصية الـ Space المتاحة على الخطط المدفوعة.

---

## 🔵 الخيار ج — Railway (لو عندك كارت، الأسهل والأثبت)

1. **https://railway.app** → Login with GitHub → **New Project → Deploy from GitHub repo**.
2. Settings → Build: طريقة البناء **Dockerfile**، الـ Root Directory = جذر الريبو.
3. **+ New → Database → PostgreSQL** (بينشئ قاعدة مجانية لحد 5$ شهريًا).
4. انسخ `DATABASE_URL` بتاعها، واضيف `JWT_ACCESS_SECRET` / `JWT_REFRESH_SECRET`.
5. Settings → Networking: **Generate Domain**.

---

## 🌱 البيانات التجريبية (مرة واحدة بعد النشر)

الـ API بيعمل `prisma db push` تلقائيًا أول ما الحالة تشغّل، فالمخطط موجود. عايز بس تحمّل بيانات.
أبسط طريقة: من جهازك (عندك Flutter + Node أصلًا):

```powershell
cd "C:\Users\abosa\OneDrive\Documents\Default Project\erp\backend"
$env:DATABASE_URL = "postgresql://...الرابط-بتاع-Neon...?sslmode=require"
npm run seed
```

> لو حصل `ECONNRESET` أو مؤقت، ركّب قاعدة الاتصال بالصيغة المعطّلة للـ pooler:
> `postgres://...@ep-xxx.aws.neon.tech/erp?sslmode=require`  
> أو ببساطة شغّل الأمر تاني — الـ seed آمن للتكرار.

**الحسابات** (الباسورد للكل `Password123`):
`admin@erp.local` · `manager@erp.local` · `cashier@erp.local` · `warehouse@erp.local` · `accountant@erp.local`

---

## 🧩 استكشاف الأخطاء

| المشكلة | السبب / الحل |
| --- | --- |
| الصفحة بتفتح فاضية | لوج البناء/التشغيل — أكيد مشكلة في `DATABASE_URL` أو الـ Prisma. |
| `Error: Environment variable not found: DATABASE_URL` | مكتوب صح في المتغيرات؟ متأكد إنك ضفتها على الـ Service مش على Workspace تاني؟ |
| `ECONNREFUSED` / `ECONNRESET` على Neon | رابط Neon ناقص `?sslmode=require` أو قاعدة البيانات نامت (عادي، بتولع تاني). |
| أول طلب بياخد وقت | الـ Instance نايم (مجاني). طبيعي، بيرجع يشتغل تاني. |
| `prisma db push` فشل | شوف اللوج — أغلب السبب السطر فيه `sslmode`. |
| الموقع قديم بعد تعديل Flutter | لازم تعيد البناء: `.\erp\deploy\build_web.ps1 -ApiUrl /api/v1` وترفع `erp/web`. |
| عايز أشوف اللوجز | Koyeb → Service → Deployments → Logs · HF → المكان فوق · Railway → Deployments |

---

## 🔁 التحديث

```powershell
git add . ; git commit -m "..." ; git push
```
- تغييرات في `erp/backend/**` → المنصة تعمل deploy تلقائي.
- تغييرات في `erp/app/**` → لازم تعمل:
  ```powershell
  .\erp\deploy\build_web.ps1 -ApiUrl /api/v1
  git add erp/web ; git commit -m "web" ; git push
  ```
  **ملاحظة:** `-ApiUrl /api/v1` يعني نفس الدومين — ده اللي بيخلي الموقع والـ API على رابط واحد.
