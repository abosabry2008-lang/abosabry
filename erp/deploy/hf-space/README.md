---
title: ERP API
emoji: 📦
colorFrom: indigo
colorTo: blue
sdk: docker
app_port: 7860
pinned: false
license: mit
---

# ERP — Inventory & Sales API

نفس تطبيق الـ ERP بالكامل (REST API + موقع Flutter Web) على رابط واحد.
الكود بيتحمّل من الريبو على GitHub وقت البناء، فمفيش حاجة تتغيّر هنا غير
متغيّرات البيئة.

## متغيرات البيئة (Settings → Variables and secrets)

| المفتاح | مطلوب | الوصف |
| --- | --- | --- |
| `DATABASE_URL` | ✅ | رابط PostgreSQL (Neon) بـ `?sslmode=require` |
| `JWT_ACCESS_SECRET` | ✅ | سر عشوائي |
| `JWT_REFRESH_SECRET` | ✅ | سر عشوائي تاني |
| `NODE_ENV` | ✅ | `production` |
| `PORT` | ⛔ متركّب | `7860` (نفس `app_port` في الأعلى) |

## بعد النشر

- الواجهة: `https://<user>-<space>.hf.space`
- الـ API: `https://<user>-<space>.hf.space/api/v1`
- السيلف تيست: `https://<user>-<space>.hf.space/api/v1/health`
- البيانات التجريبية (مرة واحدة من جهازك):
  ```powershell
  cd erp\backend
  $env:DATABASE_URL = "postgres://...?sslmode=require"
  npm run seed
  ```

> الـ Space العمومي ممكن يهدى بعد 48 ساعة خمول ويرجع يشتغل أول ما حد يفتح الموقع.
