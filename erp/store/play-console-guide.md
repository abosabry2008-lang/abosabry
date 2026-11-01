# Google Play — دليل الرفع (Closed testing)

## الملفات الجاهزة
- حزمة التطبيق (AAB): `D:/Default Project/backups/abosabry-erp-1.0.0.aab`
- نسخة APK للتثبيت المباشر: `D:/Default Project/backups/abosabry-erp-1.0.0.apk`
- أيقونة المتجر 512×512: `store/icon-512.png`
- صورة الغلاف 1024×500: `store/feature-graphic-1024x500.png`
- لقطات الشاشة 1080×1920: `store/screenshots/01-login-1080x1920.png` و`02-reports-1080x1920.png`
- نص المتجر: `store/listing-ar.md` و`store/listing-en.md`
- سياسة الخصوصية: `https://abosabry-f7vm.vercel.app/privacy.html`

## 1) إنشاء حساب Google Play Console
1. افتح https://play.google.com/console وسجّل الدخول بحساب Google.
2. اختر **Create developer account** وادفع رسم التسجيل لمرة واحدة (25 دولارًا).
3. أكمل توثيق الهوية والعنوان (قد يستغرق من ساعات إلى أيام).
4. اقبل اتفاقيات المطور.

> لا يمكن لأي شخص آخر إنشاء الحساب أو توثيقه بدلًا منك.

## 2) إنشاء التطبيق
1. من Play Console اختر **Create app**.
2. App name: **Abosabry ERP**
3. Default language: **العربية**
4. App or game: **App**
5. Free or paid: **Free**
6. أكد الإقرارات ثم **Create app**.

## 3) بيانات المتجر (Store listing)
- Short description وFull description: من `store/listing-ar.md`.
- App icon: `store/icon-512.png`.
- Feature graphic: `store/feature-graphic-1024x500.png`.
- Phone screenshots: ارفع `01-login-1080x1920.png` و`02-reports-1080x1920.png` (يمكن إضافة المزيد لاحقًا).
- Privacy policy: `https://abosabry-f7vm.vercel.app/privacy.html`
- Contact email: استخدم البريد الذي تريد ظهوره (يجب أن يكون بريدًا حقيقيًا).
- Category: **Business**.

## 4) App access (وصول المراجعين)
التطبيق يتطلب تسجيل دخول، لذلك اختر **All or some functionality is restricted** ثم **Add instructions**:

- Email: `review@erp.local`
- Password: موجود في `D:/Default Project/backups/google-play-review-account.txt` (لا تضعه في أي ملف عام).
- Instructions: "Sign in with the provided reviewer account. The account has read-only access to products, customers, sales orders, invoices and reports."

هذا الحساب مخصص لمراجعي Google فقط، وصلاحياته للقراءة فقط.

## 5) Data safety
أجب تقريبًا كالتالي:
- Does your app collect or share user data? **Yes**
- Data types: **Email address, Name, User IDs, Other business information**.
- Purpose: **App functionality, Account management, Security**.
- Is data encrypted in transit? **Yes**
- Can users request data deletion? **Yes** — عبر البريد/الهاتف في سياسة الخصوصية.
- Shared with third parties? **No** (مزودو الاستضافة يعالجون البيانات نيابة عنك، وليسوا جهات تسويق).
- No ads, no analytics SDKs.

## 6) Content rating
- Category: **Utility / Business**.
- لا يوجد عنف أو محتوى جنسي أو مخدرات أو مقامرة.
- التطبيق لا يستهدف الأطفال: **18+**.
- لا إعلانات.

## 7) Target audience & ads
- Age: **18 and over**.
- Designed for children? **No**.
- Contains ads? **No**.

## 8) Government / financial features
- Government app? **No**.
- Financial features? التطبيق نظام محاسبة وإدارة أعمال، ولا يقدم خدمات بنكية أو يعالج مدفوعات حقيقية. أجب **No** للخدمات المالية/البنكية، واشرح في الوصف أنه ERP مؤسسي.
- Health, news, COVID: **No**.

## 9) إنشاء إصدار Closed testing
1. من القائمة: **Testing → Closed testing → Create track**.
2. **Create new release**.
3. ارفع `abosabry-erp-1.0.0.aab`.
4. Release name: `1.0.0`.
5. Release notes: من `store/listing-ar.md` (قسم Release notes).
6. **Save → Review release → Start rollout to Closed testing**.
7. أضف بريدك وبريد المختبرين في **Testers**.
8. انسخ **Opt-in URL** وشاركه مع المختبرين لتثبيت التطبيق.

> للحسابات الشخصية الجديدة، قد تطلب Google **12 مختبرًا لمدة 14 يومًا** قبل السماح بالإنتاج. ابدأ بهم من الآن.

## 10) بعد الموافقة
- يمكنك ترقية الإصدار إلى **Production** لاحقًا.
- التطبيق حاليًا **Closed testing**، وهذا هو الأنسب لنظام ERP داخلي.

## ملاحظات مهمة
- **Package ID** نهائي: `com.abosabry.erp`. لا يمكن تغييره بعد النشر.
- **مفتاح التوقيع**: `D:/Default Project/backups/abosabry-erp-upload.jks` + بياناته في `backups/android-signing-credentials.txt`. احتفظ بنسخة احتياطية آمنة؛ بدونه يصعب تحديث التطبيق.
- أي تحديث لاحق: زِد `versionCode` في `app/pubspec.yaml` (مثال: `1.0.1+2`) ثم أعد البناء.
- لا ترفع ملف `key.properties` أو `.jks` إلى GitHub.
- إذا احتجت نشرًا عامًا لاحقًا، راجع سياسة الخصوصية وبيانات الأمان أولًا.
