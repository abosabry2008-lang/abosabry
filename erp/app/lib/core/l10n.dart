import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'formatters.dart';

/// Persists and exposes the user's language choice (`en` / `ar`).
///
/// The chosen language code is stored in [SharedPreferences] under the key
/// `app_locale`. English is the default when nothing has been stored yet.
class LocaleController extends ChangeNotifier {
  static const String _key = 'app_locale';

  Locale _locale = const Locale('en');

  /// The currently active locale.
  Locale get locale => _locale;

  /// True when the active locale is Arabic.
  bool get isArabic => _locale.languageCode == 'ar';

  /// Loads the persisted language (if any). Should be awaited during startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored == 'en' || stored == 'ar') {
      _locale = Locale(stored!);
      notifyListeners();
    }
  }

  /// Switches to [locale] and persists the choice.
  Future<void> setLocale(Locale locale) async {
    if (locale.languageCode == _locale.languageCode) return;
    _locale = Locale(locale.languageCode);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _locale.languageCode);
  }

  /// Toggles between English and Arabic, persisting the new choice.
  Future<void> toggle() =>
      setLocale(isArabic ? const Locale('en') : const Locale('ar'));
}

/// All user-visible strings for the app, resolved for a single [locale].
///
/// Every string is exposed as a typed getter (or parameterised method) so that
/// `flutter analyze` catches typos and missing translations.
class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  bool get isArabic => locale.languageCode == 'ar';

  /// Translates common server error messages (which are written in English by
  /// the API) into the active language so the UI never mixes the two.
  ///
  /// Falls back to the original text when there is no known translation, so
  /// unexpected messages still reach the user verbatim.
  static String translateServerMessage(Locale locale, String message) {
    if (locale.languageCode != 'ar') return message;
    final trimmed = message.trim();

    const exact = <String, String>{
      'Invalid email or password': 'البريد الإلكتروني أو كلمة المرور غير صحيحة',
      'You are not authorised': 'غير مصرّح لك',
      'Invalid token': 'جلسة غير صالحة',
      'Record not found': 'السجل غير موجود',
      'Customer not found': 'العميل غير موجود',
      'Supplier not found': 'المورد غير موجود',
      'Internal server error': 'خطأ داخلي في الخادم',
      'Validation failed': 'البيانات غير صالحة',
      'Request body is not valid JSON': 'صيغة البيانات المرسلة غير صحيحة',
      'Related record does not exist (foreign key violation)':
          'السجل المرتبط غير موجود',
      'Invalid data supplied to the database': 'البيانات المرسلة غير صالحة',
      'The request timed out. Check your connection and try again.':
          'انتهت مهلة الطلب. تحقق من الاتصال وحاول مرة أخرى.',
      'Your session has expired. Please sign in again.':
          'انتهت الجلسة. من فضلك سجّل الدخول مرة أخرى.',
      'Unable to complete the request.': 'تعذّر إتمام الطلب.',
    };
    if (exact.containsKey(trimmed)) return exact[trimmed]!;

    // "A record with the same code already exists" → fields vary, so match on
    // the stable prefix.
    final duplicate = RegExp(
      r'^A record with the same (.+) already exists$',
    ).firstMatch(trimmed);
    if (duplicate != null) {
      final fields = duplicate.group(1)!;
      final label = fields.contains('code')
          ? 'الكود'
          : fields.contains('sku')
              ? 'الرمز'
              : fields.contains('email')
                  ? 'البريد الإلكتروني'
                  : fields.contains('barcode')
                      ? 'الباركود'
                      : fields;
      return 'يوجد سجل بنفس $label بالفعل';
    }

    return message;
  }

  String _t(String en, String ar) => isArabic ? ar : en;

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ??
      const AppStrings(Locale('en'));

  // ---------------------------------------------------------------------------
  // Generic
  // ---------------------------------------------------------------------------
  String get appName => _t('ERP', 'ERP');
  String get inventorySalesTagline =>
      _t('Inventory & sales management', 'إدارة المخزون والمبيعات');
  String get save => _t('Save', 'حفظ');
  String get saving => _t('Saving…', 'جارٍ الحفظ…');
  String get saveChanges => _t('Save changes', 'حفظ التغييرات');
  String get cancel => _t('Cancel', 'إلغاء');
  String get delete => _t('Delete', 'حذف');
  String get edit => _t('Edit', 'تعديل');
  String get print => _t('Print', 'طباعة');
  String get couldNotOpenPrintPage =>
      _t('Could not open the print page.', 'تعذّر فتح صفحة الطباعة.');
  String get create => _t('Create', 'إنشاء');
  String get confirm => _t('Confirm', 'تأكيد');
  String get continueLabel => _t('Continue', 'متابعة');
  String get retry => _t('Retry', 'إعادة المحاولة');
  String get tryAgain => _t('Try again', 'إعادة المحاولة');
  String get refresh => _t('Refresh', 'تحديث');
  String get clear => _t('Clear', 'مسح');
  String get search => _t('Search', 'بحث');
  String get searchEllipsis => _t('Search…', 'بحث…');
  String get add => _t('Add', 'إضافة');
  String get remove => _t('Remove', 'إزالة');
  String get somethingWentWrong => _t('Something went wrong', 'حدث خطأ ما');
  String get nothingHereYet => _t('Nothing here yet', 'لا يوجد شيء بعد');
  String get searchToBeginTitle => _t('Search to begin', 'ابدأ بالبحث');
  String get searchToBeginMessage => _t(
        'Type a search term or apply a filter to load the records. This keeps the app fast.',
        'اكتب كلمة بحث أو طبّق فلترًا لعرض الحركات. ده بيخلي البرنامج أسرع.',
      );
  String get yes => _t('Yes', 'نعم');
  String get no => _t('No', 'لا');
  String get active => _t('Active', 'نشط');
  String get inactive => _t('Inactive', 'غير نشط');
  String get reserved => _t('reserved', 'محجوز');
  String get selectADate => _t('Select a date', 'اختر تاريخًا');
  String get name => _t('Name', 'الاسم');
  String get nameRequired => _t('Name is required', 'الاسم مطلوب');
  String get code => _t('Code', 'الرمز');
  String get codeStar => _t('Code *', 'الرمز *');
  String get codeRequired => _t('Code is required', 'الرمز مطلوب');
  String get email => _t('Email', 'البريد الإلكتروني');
  String get emailRequired => _t('Email is required', 'البريد الإلكتروني مطلوب');
  String get enterValidEmail =>
      _t('Enter a valid email', 'أدخل بريدًا إلكترونيًا صالحًا');
  String get phone => _t('Phone', 'الهاتف');
  String get address => _t('Address', 'العنوان');
  String get prefixRequired => _t('Prefix is required', 'البادئة مطلوبة');
  String get switchLanguageTooltip => isArabic ? 'English' : 'العربية';

  // ---------------------------------------------------------------------------
  // Login
  // ---------------------------------------------------------------------------
  String get signIn => _t('Sign in', 'تسجيل الدخول');
  String get signingIn => _t('Signing in…', 'جارٍ تسجيل الدخول…');
  String get signOut => _t('Sign out', 'تسجيل الخروج');
  String get password => _t('Password', 'كلمة المرور');
  String get passwordIsRequired =>
      _t('Password is required', 'كلمة المرور مطلوبة');
  String get showPassword => _t('Show password', 'إظهار كلمة المرور');
  String get hidePassword => _t('Hide password', 'إخفاء كلمة المرور');
  String get serverSettings => _t('Server settings', 'إعدادات الخادم');
  String get apiBaseUrl => _t('API base URL', 'عنوان API الأساسي');
  String get apiBaseUrlExample =>
      _t('Example: http://192.168.1.10:4000/api/v1', 'مثال: http://192.168.1.10:4000/api/v1');
  String get baseUrlIsRequired => _t('Base URL is required', 'عنوان URL مطلوب');
  String get enterValidAbsoluteUrl =>
      _t('Enter a valid absolute URL', 'أدخل عنوان URL مطلقًا صالحًا');
  String get resetToDefaultServer =>
      _t('Reset to default server', 'إعادة التعيين للسيرفر الافتراضي');
  String get serverReset => _t(
        'Server address reset to the default.',
        'تمت إعادة عنوان السيرفر للوضع الافتراضي.',
      );
  String get unableToSignIn => _t('Unable to sign in.', 'تعذّر تسجيل الدخول.');
  String get signedInAsHint => _t(
        'Signed in as an ERP user. Ask an administrator for your credentials.',
        'يتم تسجيل الدخول كمستخدم ERP. اطلب بيانات الدخول من المسؤول.',
      );

  // ---------------------------------------------------------------------------
  // Navigation / shell
  // ---------------------------------------------------------------------------
  String get dashboard => _t('Dashboard', 'لوحة التحكم');
  String get pointOfSale => _t('Point of Sale', 'نقطة البيع');
  String get products => _t('Products', 'المنتجات');
  String get categories => _t('Categories', 'الفئات');
  String get inventory => _t('Inventory', 'المخزون');
  String get movements => _t('Movements', 'الحركات');
  String get warehouses => _t('Warehouses', 'المستودعات');
  String get suppliers => _t('Suppliers', 'الموردون');
  String get purchasing => _t('Purchasing', 'المشتريات');
  String get customers => _t('Customers', 'العملاء');
  String get salesOrders => _t('Sales Orders', 'أوامر البيع');
  String get invoices => _t('Invoices', 'الفواتير');
  String get payments => _t('Payments', 'المدفوعات');
  String get reports => _t('Reports', 'التقارير');
  String get accounts => _t('Accounts', 'الحسابات');
  String get journal => _t('Journal', 'دفتر اليومية');
  String get settings => _t('Settings', 'الإعدادات');
  String get users => _t('Users', 'المستخدمون');
  String get account => _t('Account', 'الحساب');
  String get erpUser => _t('ERP user', 'مستخدم ERP');
  String roleLabel(String role) => _t('Role: $role', 'الدور: $role');
  String noAccessMessage(String role) => _t(
        'Your role ($role) does not have access to any section. '
            'Contact an administrator.',
        'دورك ($role) لا يملك صلاحية الوصول إلى أي قسم. تواصل مع المسؤول.',
      );

  // ---------------------------------------------------------------------------
  // Dashboard
  // ---------------------------------------------------------------------------
  String get quickActions => _t('Quick actions', 'إجراءات سريعة');
  String get newSale => _t('New sale', 'بيع جديد');
  String get lowStockAlerts => _t('Low stock alerts', 'تنبيهات نقص المخزون');
  String get everythingAboveReorder =>
      _t('Everything is above its reorder level', 'كل الأصناف أعلى من حد إعادة الطلب');
  String productsNeedAttention(int n) => _t(
        '$n product(s) need attention',
        '$n منتج بحاجة إلى متابعة',
      );
  String get noLowStockItems => _t('No low-stock items.', 'لا توجد أصناف منخفضة المخزون.');
  String get recentMovements => _t('Recent movements', 'الحركات الأخيرة');
  String get noRecentMovements =>
      _t('No recent inventory movements.', 'لا توجد حركات مخزون حديثة.');
  String get salesToday => _t('Sales today', 'مبيعات اليوم');
  String get salesThisMonth => _t('Sales this month', 'مبيعات هذا الشهر');
  String get receivables => _t('Receivables', 'المبالغ المستحقة');
  String get inventoryValue => _t('Inventory value', 'قيمة المخزون');
  String get lowStockItems => _t('Low stock items', 'أصناف منخفضة المخزون');
  String get openInvoices => _t('Open invoices', 'الفواتير المفتوحة');
  String reorderLevelValue(String value) =>
      _t('Reorder level $value', 'حد إعادة الطلب $value');
  String get productFallback => _t('Product', 'منتج');

  // ---------------------------------------------------------------------------
  // POS
  // ---------------------------------------------------------------------------
  String get searchProductsHint =>
      _t('Search products by name, SKU or barcode…', 'ابحث عن المنتجات بالاسم أو الرمز أو الباركود…');
  String get noProducts => _t('No products', 'لا توجد منتجات');
  String get addProductsToStartSelling =>
      _t('Add products to start selling.', 'أضف منتجات لبدء البيع.');
  String get checkout => _t('Checkout', 'إتمام البيع');
  String itemsCount(int n) => _t('$n item(s)', '$n عنصر');
  String get cart => _t('Cart', 'السلة');
  String get cartIsEmpty => _t('The cart is empty.', 'السلة فارغة.');
  String get details => _t('Details', 'التفاصيل');
  String get warehouseRequired => _t('Warehouse *', 'المستودع *');
  String get customer => _t('Customer', 'العميل');
  String get walkInCustomer => _t('Walk-in customer', 'عميل نقدي');
  String get paymentMethod => _t('Payment method', 'طريقة الدفع');
  String get amountReceived => _t('Amount received', 'المبلغ المستلم');
  String get subtotal => _t('Subtotal', 'المجموع الفرعي');
  String get total => _t('Total', 'الإجمالي');
  String get discountWord => _t('Discount', 'الخصم');
  String get unitPrice => _t('Unit price', 'سعر الوحدة');
  String get qty => _t('Qty', 'الكمية');
  String get lineTotal => _t('Line total', 'إجمالي السطر');
  String get addLine => _t('Add line', 'إضافة سطر');
  String get noLinesYet =>
      _t('No items yet — add the first one above.', 'لا توجد أصناف بعد — أضف أول صنف بالأعلى.');
  String get item => _t('Item', 'صنف');
  String get change => _t('Change', 'الباقي');
  String get processing => _t('Processing…', 'جارٍ المعالجة…');
  String get completeSale => _t('Complete sale', 'إتمام البيع');
  String get noWarehousesAvailable =>
      _t('No warehouses available for sales.', 'لا توجد مستودعات متاحة للبيع.');
  String get couldNotCompleteSale =>
      _t('Could not complete the sale.', 'تعذّر إتمام البيع.');
  String get decrease => _t('Decrease', 'إنقاص');
  String get increase => _t('Increase', 'زيادة');
  String saleComplete({String? invoiceNumber, required String change}) {
    final suffix = invoiceNumber == null
        ? ''
        : _t(' · invoice $invoiceNumber', ' · فاتورة $invoiceNumber');
    return _t(
      'Sale complete$suffix · change $change',
      'تم إتمام البيع$suffix · الباقي $change',
    );
  }

  // ---------------------------------------------------------------------------
  // Products
  // ---------------------------------------------------------------------------
  String get barcodeLookup => _t('Barcode lookup', 'البحث بالباركود');
  String get barcode => _t('Barcode', 'الباركود');
  String get searchProductsByNameSku =>
      _t('Search products by name or SKU…', 'ابحث عن المنتجات بالاسم أو الرمز…');
  String get category => _t('Category', 'الفئة');
  String get allCategories => _t('All categories', 'كل الفئات');
  String get lowStock => _t('Low stock', 'مخزون منخفض');
  String get noProductsFound => _t('No products found', 'لا توجد منتجات');
  String get adjustFiltersOrAddProduct => _t(
        'Adjust your filters or add a new product to get started.',
        'عدّل عوامل التصفية أو أضف منتجًا جديدًا للبدء.',
      );
  String get newProduct => _t('New product', 'منتج جديد');
  String get product => _t('Product', 'منتج');
  String productCount(String count) => _t('$count product(s)', '$count منتج');
  String onHandCount(String count) => _t('$count on hand', '$count في المخزون');
  String get productNotFound => _t('Product not found.', 'المنتج غير موجود.');
  String get identification => _t('Identification', 'التعريف');
  String get skuStar => _t('SKU *', 'الرمز *');
  String get skuRequired => _t('SKU is required', 'الرمز مطلوب');
  String get nameStar => _t('Name *', 'الاسم *');
  String get uncategorised => _t('Uncategorised', 'غير مصنّف');
  String get description => _t('Description', 'الوصف');
  String get pricingStock => _t('Pricing & stock', 'التسعير والمخزون');
  String get costPrice => _t('Cost price', 'سعر التكلفة');
  String get lastPurchasePrice =>
      _t('Last purchase price', 'آخر سعر شراء');
  String get lastPurchasePriceHint => _t(
        'Shown to you on screen only — never printed on the invoice.',
        'يظهر لك على الشاشة فقط — لا يُطبع في الفاتورة.',
      );
  String get salePrice => _t('Sale price', 'سعر البيع');
  String get taxRatePercent => _t('Tax rate %', 'نسبة الضريبة %');
  String get unit => _t('Unit', 'الوحدة');
  String get boxesPerCarton => _t('Boxes per carton', 'عدد العلب في الكرتونة');
  String get boxPrice => _t('Box price', 'سعر العلبة');
  String get cartonPrice => _t('Carton price', 'سعر الكرتونة');
  String get reorderLevel => _t('Reorder level', 'حد إعادة الطلب');
  String get reorderLevelHelper => _t(
        'Trigger a low-stock alert at or below this qty',
        'أطلق تنبيه نقص المخزون عند هذه الكمية أو أقل',
      );
  String get trackInventory => _t('Track inventory', 'تتبع المخزون');
  String get trackInventorySubtitle =>
      _t('Maintain stock levels for this product', 'حافظ على مستويات مخزون هذا المنتج');
  String get inactiveHiddenSubtitle =>
      _t('Inactive products are hidden from new orders', 'المنتجات غير النشطة مخفية من الطلبات الجديدة');
  String get productUpdated => _t('Product updated.', 'تم تحديث المنتج.');
  String get productCreated => _t('Product created.', 'تم إنشاء المنتج.');
  String get deleteProductQ => _t('Delete product?', 'حذف المنتج؟');
  String productWillBeRemoved(String name) =>
      _t('“$name” will be removed from the catalogue.', 'سيتم حذف «$name» من الكتالوج.');
  String productDeleted(String name) => _t('$name deleted.', 'تم حذف $name.');
  String get activateProduct => _t('Activate', 'تنشيط');
  String get deactivateProduct => _t('Deactivate product', 'إلغاء تنشيط المنتج');
  String productDeactivated(String name) =>
      _t('$name deactivated.', 'تم إلغاء تنشيط $name.');
  String productActivated(String name) =>
      _t('$name activated.', 'تم تنشيط $name.');
  String skuLabel(String sku) => _t('SKU $sku', 'الرمز $sku');
  String get deleted => _t('Deleted', 'محذوف');
  String get restore => _t('Restore', 'استرجاع');
  String get showInactive => _t('Show inactive', 'إظهار غير النشط');
  String get showDeleted => _t('Show deleted', 'إظهار المحذوف');
  String get deleteProduct => _t('Delete product', 'حذف المنتج');
  String get willBePurged =>
      _t('It will also be removed from inventory.', 'هيتشال من المخزون كمان.');
  String get restoreProductQ => _t('Restore product?', 'استرجاع المنتج؟');
  String productRestored(String name) =>
      _t('$name restored.', 'تم استرجاع $name.');

  // ---------------------------------------------------------------------------
  // Product import (استيراد الأصناف)
  // ---------------------------------------------------------------------------
  String get importProducts => _t('Import from Excel', 'استيراد من إكسل');
  String get importHowTo => _t('How to import', 'طريقة الاستيراد');
  String get importStep1 => _t(
        '1. In Excel, put the columns in this order: name, quantity, cost price, sale price (code optional).',
        '١. في إكسل رتّب الأعمدة بالترتيب: اسم الصنف، العدد، سعر التكلفة، سعر البيع (والكود اختياري).',
      );
  String get importStep2 => _t(
        '2. Leave the code empty to auto-generate one, and leave the sale price empty to add 3% over the cost price.',
        '٢. اترك الكود فارغًا ليتم توليده تلقائيًا، واترك سعر البيع فاضي ليُزاد ٣٪ على سعر التكلفة.',
      );
  String get importStep3 => _t(
        '3. Paste here (Ctrl+V) and press Import. Any empty column is filled automatically.',
        '٣. الصق هنا (Ctrl+V) واضغط استيراد. أي عمود تسيبه فاضي بيتعبّى تلقائياً.',
      );
  String get importSample => _t(
        'Example:\nاندومي\t12\t15\t\t\nشيبسي\t24\t3\t6\tCHP-1',
        'مثال:\nاندومي\t١٢\t١٥\nشيبسي\t٢٤\t٣\t٦\tCHP-1',
      );
  String get pasteHere => _t('Paste rows here', 'الصق الصفوف هنا');
  String rowsDetected(int n) => _t('$n row(s) detected', 'تم التعرف على $n صف');
  String get nothingToImport => _t('Nothing to import.', 'لا يوجد شيء للاستيراد.');
  String get importNow => _t('Import now', 'استيراد الآن');
  String get importResult => _t('Import result', 'نتيجة الاستيراد');
  String get importCreated => _t('Created', 'جديد');
  String get importUpdated => _t('Updated', 'محدّث');
  String get importSkipped => _t('Skipped', 'متجاوز');
  String get adjustStockOnImport => _t(
        'Set stock to the imported quantity',
        'ضبط المخزون على الكمية المستوردة',
      );
  String get adjustStockOnImportHint => _t(
        'Off: stock is added only for brand-new products.',
        'معطّل: المخزون بيتضاف للأصناف الجديدة فقط.',
      );
  String get taxRate => _t('Tax rate', 'نسبة الضريبة');
  String get onHand => _t('On hand', 'المتوفر');

  // ---------------------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------------------
  String get newCategory => _t('New category', 'فئة جديدة');
  String get editCategory => _t('Edit category', 'تعديل الفئة');
  String get categoryCreated => _t('Category created.', 'تم إنشاء الفئة.');
  String get categoryUpdated => _t('Category updated.', 'تم تحديث الفئة.');
  String get deleteCategoryQ => _t('Delete category?', 'حذف الفئة؟');
  String categoryWillBeRemoved(String name) => _t(
        '“$name” will be removed. Products keep their data.',
        'سيتم حذف «$name». ستحتفظ المنتجات ببياناتها.',
      );
  String categoryDeleted(String name) => _t('$name deleted.', 'تم حذف $name.');
  String get noCategories => _t('No categories', 'لا توجد فئات');
  String get createCategoryHint =>
      _t('Create a category to organise your products.', 'أنشئ فئة لتنظيم منتجاتك.');
  String get categoryWord => _t('Category', 'فئة');
  String get searchCategoriesHint => _t('Search categories…', 'ابحث في الفئات…');

  // ---------------------------------------------------------------------------
  // Inventory
  // ---------------------------------------------------------------------------
  String get searchStockHint => _t('Search stock by product…', 'ابحث في المخزون حسب المنتج…');
  String get warehouse => _t('Warehouse', 'المستودع');
  String get allWarehouses => _t('All warehouses', 'كل المستودعات');
  String get noStockRecords => _t('No stock records', 'لا توجد سجلات مخزون');
  String get receiveOrAdjustHint =>
      _t('Receive or adjust stock to populate this list.', 'استلم أو عدّل المخزون لتعبئة هذه القائمة.');
  String get stock => _t('Stock', 'المخزون');
  String get adjustStock => _t('Adjust stock', 'تعديل المخزون');
  String get transferStock => _t('Transfer stock', 'تحويل المخزون');
  String get receiveStock => _t('Receive stock', 'استلام مخزون');
  String get cycleCount => _t('Cycle count', 'الجرد الدوري');
  String get inventoryUpdated => _t('Inventory updated.', 'تم تحديث المخزون.');
  String get low => _t('Low', 'منخفض');
  String get adjust => _t('Adjust', 'تعديل');
  String get transfer => _t('Transfer', 'تحويل');
  String get receive => _t('Receive', 'استلام');
  String get quantityStar => _t('Quantity *', 'الكمية *');
  String get positiveAddsStock =>
      _t('Positive adds stock, negative removes it', 'القيمة الموجبة تضيف مخزونًا والسالية تخصم منه');
  String get enterWholeNumber => _t('Enter a whole number', 'أدخل عددًا صحيحًا');
  String get enterNonZeroQuantity => _t('Enter a non-zero quantity', 'أدخل كمية غير صفرية');
  String get reason => _t('Reason', 'السبب');
  String get posting => _t('Posting…', 'جارٍ الترحيل…');
  String get postAdjustment => _t('Post adjustment', 'ترحيل التسوية');
  String get selectProduct => _t('Select a product', 'اختر منتجًا');
  String get selectLocation => _t('Select a location', 'اختر موقعًا');
  String get from => _t('From', 'من');
  String get to => _t('To', 'إلى');
  String get enterQtyGreaterThanZero =>
      _t('Enter a quantity greater than zero', 'أدخل كمية أكبر من صفر');
  String get note => _t('Note', 'ملاحظة');
  String get countedItems => _t('Counted items', 'الأصناف المجرودة');
  String get noItemsYet =>
      _t('No items yet — add the products you counted.', 'لا توجد أصناف بعد — أضف المنتجات التي جردتها.');
  String get counted => _t('Counted', 'المجرود');
  String get submitting => _t('Submitting…', 'جارٍ الإرسال…');
  String get submitCount => _t('Submit count', 'إرسال الجرد');
  String get selectLocationToCount => _t('Select a location to count.', 'اختر موقعًا للجرد.');
  String get selectProductEveryLine =>
      _t('Select a product for every line.', 'اختر منتجًا لكل سطر.');
  String get enterCountedEveryLine =>
      _t('Enter a counted quantity for every line.', 'أدخل الكمية المجرودة لكل سطر.');
  String get addAtLeastOneProduct => _t('Add at least one product.', 'أضف منتجًا واحدًا على الأقل.');
  String get couldNotSubmitCycleCount =>
      _t('Could not submit the cycle count.', 'تعذّر إرسال الجرد الدوري.');
  String get couldNotPostAdjustment =>
      _t('Could not post the adjustment.', 'تعذّر ترحيل التسوية.');
  String get couldNotPostTransfer =>
      _t('Could not post the transfer.', 'تعذّر ترحيل التحويل.');
  String get couldNotReceiveStock => _t('Could not receive stock.', 'تعذّر استلام المخزون.');
  String get selectAProduct => _t('Select a product.', 'اختر منتجًا.');
  String get selectALocation => _t('Select a location.', 'اختر موقعًا.');
  String get selectProductAndLocation => _t('Select a product and a location.', 'اختر منتجًا وموقعًا.');
  String get selectProductSourceDestination => _t(
        'Select a product, a source and a destination.',
        'اختر منتجًا ومصدرًا ووجهة.',
      );
  String get sourceDestinationDiffer =>
      _t('Source and destination must differ.', 'يجب أن يختلف المصدر عن الوجهة.');
  String get location => _t('Location', 'الموقع');
  String get selectAWarehouse => _t('Select a warehouse', 'اختر مستودعًا');
  String get chooseWarehouseFirst => _t('Choose a warehouse first', 'اختر مستودعًا أولًا');
  String get unitCost => _t('Unit cost', 'تكلفة الوحدة');
  String get reference => _t('Reference', 'المرجع');
  String get supplierInvoiceOrDeliveryNote =>
      _t('Supplier invoice or delivery note number', 'رقم فاتورة المورد أو إشعار التسليم');
  String get searchMovementsHint => _t('Search movements…', 'ابحث في الحركات…');
  String get type => _t('Type', 'النوع');
  String get allTypes => _t('All types', 'كل الأنواع');
  String get noMovements => _t('No movements', 'لا توجد حركات');
  String get searchToViewMovements => _t('Click Search to view movements', '???? ??? ?????? ?????? ???????');
  String get movementsWillAppear =>
      _t('Inventory movements will appear here.', 'ستظهر حركات المخزون هنا.');
  String get searchByBarcodeHint =>
      _t('Search by name, SKU or barcode…', 'ابحث بالاسم أو الرمز أو الباركود…');
  String get noMatchingProducts => _t('No matching products.', 'لا توجد منتجات مطابقة.');
  String get removeLine => _t('Remove line', 'إزالة السطر');

  // ---------------------------------------------------------------------------
  // Warehouses & locations
  // ---------------------------------------------------------------------------
  String get newWarehouse => _t('New warehouse', 'مستودع جديد');
  String get editWarehouse => _t('Edit warehouse', 'تعديل المستودع');
  String get warehouseCreated => _t('Warehouse created.', 'تم إنشاء المستودع.');
  String get warehouseUpdated => _t('Warehouse updated.', 'تم تحديث المستودع.');
  String get deleteWarehouseQ => _t('Delete warehouse?', 'حذف المستودع؟');
  String warehouseAndLocationsWillBeRemoved(String name) => _t(
        '“$name” and its locations will be removed.',
        'سيتم حذف «$name» ومواقعه.',
      );
  String warehouseDeleted(String name) => _t('$name deleted.', 'تم حذف $name.');
  String get noWarehouses => _t('No warehouses', 'لا توجد مستودعات');
  String get createWarehouseHint =>
      _t('Create a warehouse to start tracking stock.', 'أنشئ مستودعًا لبدء تتبع المخزون.');
  String get warehouseWord => _t('Warehouse', 'مستودع');
  String locationCount(String count) => _t('$count location(s)', '$count موقع');
  String get searchWarehousesHint => _t('Search warehouses…', 'ابحث في المستودعات…');
  String get newLocation => _t('New location', 'موقع جديد');
  String get editLocation => _t('Edit location', 'تعديل الموقع');
  String get locationCreated => _t('Location created.', 'تم إنشاء الموقع.');
  String get locationUpdated => _t('Location updated.', 'تم تحديث الموقع.');
  String get deleteLocationQ => _t('Delete location?', 'حذف الموقع؟');
  String locationWillBeRemoved(String name) => _t(
        '“$name” will be removed from this warehouse.',
        'سيتم حذف «$name» من هذا المستودع.',
      );
  String get locationDeleted => _t('Location deleted.', 'تم حذف الموقع.');
  String get noLocations => _t('No locations', 'لا توجد مواقع');
  String get addBinHint =>
      _t('Add a bin or shelf to start tracking stock.', 'أضف رفًا أو موقعًا لبدء تتبع المخزون.');
  String get locationWord => _t('Location', 'موقع');

  // ---------------------------------------------------------------------------
  // Suppliers
  // ---------------------------------------------------------------------------
  String get noSuppliers => _t('No suppliers', 'لا يوجد موردون');
  String get addSupplierHint =>
      _t('Add a supplier to create purchase orders.', 'أضف موردًا لإنشاء أوامر الشراء.');
  String get supplier => _t('Supplier', 'مورد');
  String get fromCustomer => _t('From customer', 'من العميل');
  String get toCustomer => _t('To customer', 'إلى العميل');
  String get fromSupplier => _t('From supplier', 'من المورد');
  String get toSupplier => _t('To supplier', 'إلى المورد');
  String get cashSale => _t('Cash sale', 'بيع نقدي');
  String get allCustomers => _t('All customers', 'كل العملاء');
  String get customersWithDebt =>
      _t('Customers who owe money', 'العملاء اللي عليهم فلوس');
  String get customersWithCredit =>
      _t('Customers with credit', 'العملاء اللي لهم فلوس');
  String get showLabel => _t('Show', 'العرض');
  String get newSupplier => _t('New supplier', 'مورد جديد');
  String get deleteSupplierQ => _t('Delete supplier?', 'حذف المورد؟');
  String supplierWillBeRemoved(String name) =>
      _t('“$name” will be removed.', 'سيتم حذف «$name».');
  String supplierDeleted(String name) => _t('$name deleted.', 'تم حذف $name.');
  String get balance => _t('Balance', 'الرصيد');
  String get accountStatement => _t('Account statement', 'كشف حساب');
  String get supplierDetails => _t('Supplier details', 'بيانات المورد');
  String get supplierCode => _t('Supplier code', 'كود المورد');
  String get codeAutoHint => _t(
        'Leave empty to generate automatically',
        'اتركه فاضيًا ليُولَّد تلقائيًا',
      );
  String get contactPerson => _t('Contact person', 'الشخص المسؤول');
  String get taxId => _t('Tax ID', 'الرقم الضريبي');
  String get paymentTermDays => _t('Payment term (days)', 'مدة السداد (أيام)');
  String get supplierUpdated => _t('Supplier updated.', 'تم تحديث المورد.');
  String get supplierCreated => _t('Supplier created.', 'تم إنشاء المورد.');
  String get deleteSupplier => _t('Delete supplier', 'حذف المورد');
  String get searchSuppliersHint => _t('Search suppliers…', 'ابحث في الموردين…');

  // ---------------------------------------------------------------------------
  // Purchasing
  // ---------------------------------------------------------------------------
  String get searchPurchaseOrdersHint =>
      _t('Search purchase orders…', 'ابحث في أوامر الشراء…');
  String get statusWord => _t('Status', 'الحالة');
  String get allStatuses => _t('All statuses', 'كل الحالات');
  String get noPurchaseOrders => _t('No purchase orders', 'لا توجد أوامر شراء');
  String get createPurchaseOrderHint =>
      _t('Create a purchase order to restock inventory.', 'أنشئ أمر شراء لإعادة تعبئة المخزون.');
  String get purchaseOrder => _t('Purchase order', 'أمر شراء');
  String get newPurchaseOrder => _t('New purchase order', 'أمر شراء جديد');
  String get orderDetails => _t('Order details', 'تفاصيل الأمر');
  String get supplierStar => _t('Supplier *', 'المورد *');
  String get supplierRequired => _t('Supplier is required', 'المورد مطلوب');
  String get expectedDate => _t('Expected date', 'التاريخ المتوقع');
  String get notes => _t('Notes', 'ملاحظات');
  String get lines => _t('Lines', 'الأسطر');
  String get productsToOrder => _t('Products to order', 'المنتجات المطلوب طلبها');
  String get createOrder => _t('Create order', 'إنشاء الأمر');
  String get editOrder => _t('Edit order', 'تعديل الأمر');
  String get salesOrderCreated => _t('Sales order created.', 'تم إنشاء أمر البيع.');
  String get warehouseIsRequired => _t('Warehouse is required', 'المستودع مطلوب');
  String get selectSupplierAndWarehouse =>
      _t('Select a supplier and a warehouse.', 'اختر موردًا ومستودعًا.');
  String get addAtLeastOneCompleteLine =>
      _t('Add at least one complete line.', 'أضف سطرًا مكتملًا واحدًا على الأقل.');
  String get purchaseOrderCreated => _t('Purchase order created.', 'تم إنشاء أمر الشراء.');
  String get purchaseOrderNotFound => _t('Purchase order not found.', 'أمر الشراء غير موجود.');
  String get orderDate => _t('Order date', 'تاريخ الأمر');
  String get expected => _t('Expected', 'المتوقع');
  String get received => _t('Received', 'المستلم');
  String get noLinesOnOrder => _t('No lines on this order.', 'لا توجد أسطر في هذا الأمر.');
  String lineCount(int n) => _t('$n line(s)', '$n سطر');
  String get tax => _t('Tax', 'الضريبة');
  String get approve => _t('Approve', 'اعتماد');
  String get approvePurchaseOrderQ =>
      _t('Approve purchase order?', 'اعتماد أمر الشراء؟');
  String get approvePurchaseOrderMessage =>
      _t('The order can then be received.', 'يمكن بعد ذلك استلام الأمر.');
  String get purchaseOrderApproved => _t('Purchase order approved.', 'تم اعتماد أمر الشراء.');
  String get receiveAllOutstandingQ =>
      _t('Receive all outstanding items?', 'استلام كل الأصناف المتبقية؟');
  String get receiveAllOutstandingMessage => _t(
        'Stock levels will be increased for every outstanding line.',
        'سيتم زيادة مستويات المخزون لكل سطر متبقٍ.',
      );
  String get stockReceived => _t('Stock received.', 'تم استلام المخزون.');
  String get cancelPurchaseOrderQ => _t('Cancel purchase order?', 'إلغاء أمر الشراء؟');
  String get cannotBeUndone => _t('This cannot be undone.', 'لا يمكن التراجع عن هذا.');
  String get purchaseOrderCancelled => _t('Purchase order cancelled.', 'تم إلغاء أمر الشراء.');
  String get purchaseOrderUpdated => _t('Purchase order updated.', 'تم تحديث أمر الشراء.');
  String lineQtyReceived(int qty, int received) =>
      _t('qty $qty · received $received', 'الكمية $qty · المستلم $received');

  // ---------------------------------------------------------------------------
  // Customers
  // ---------------------------------------------------------------------------
  String get noCustomers => _t('No customers', 'لا يوجد عملاء');
  String get addCustomerHint =>
      _t('Add a customer to create sales orders.', 'أضف عميلًا لإنشاء أوامر البيع.');
  String get newCustomer => _t('New customer', 'عميل جديد');
  String get deleteCustomerQ => _t('Delete customer?', 'حذف العميل؟');
  String customerWillBeRemoved(String name) =>
      _t('“$name” will be removed.', 'سيتم حذف «$name».');
  String customerDeleted(String name) => _t('$name deleted.', 'تم حذف $name.');
  String get customerDetails => _t('Customer details', 'بيانات العميل');
  String get customerCode => _t('Customer code', 'كود العميل');
  String get creditLimit => _t('Credit limit', 'حد الائتمان');
  String get customerUpdated => _t('Customer updated.', 'تم تحديث العميل.');
  String get customerCreated => _t('Customer created.', 'تم إنشاء العميل.');
  String get deleteCustomer => _t('Delete customer', 'حذف العميل');

  // ---------------------------------------------------------------------------
  // Sales
  // ---------------------------------------------------------------------------
  String get searchSalesOrdersHint => _t('Search sales orders…', 'ابحث في أوامر البيع…');
  String get noSalesOrders => _t('No sales orders', 'لا توجد أوامر بيع');
  String get createSalesOrderHint =>
      _t('Create a sales order to start selling.', 'أنشئ أمر بيع لبدء البيع.');
  String get salesOrder => _t('Sales order', 'أمر بيع');
  String get newSalesOrder => _t('New sales order', 'أمر بيع جديد');
  String get confirmWord => _t('Confirm', 'تأكيد');
  String get fulfil => _t('Fulfil', 'تنفيذ');
  String get createInvoice => _t('Create invoice', 'إنشاء فاتورة');
  String get confirmSalesOrderQ => _t('Confirm sales order?', 'تأكيد أمر البيع؟');
  String get confirmSalesOrderMessage => _t(
        'Confirmed orders can be fulfilled and invoiced.',
        'يمكن تنفيذ الأوامر المؤكدة وإصدار فواتير لها.',
      );
  String get salesOrderConfirmed => _t('Sales order confirmed.', 'تم تأكيد أمر البيع.');
  String get fulfilAllQ => _t('Fulfil all outstanding items?', 'تنفيذ كل الأصناف المتبقية؟');
  String get fulfilAllMessage => _t(
        'Stock levels will be reduced for every outstanding line.',
        'سيتم خفض مستويات المخزون لكل سطر متبقٍ.',
      );
  String get salesOrderFulfilled => _t('Sales order fulfilled.', 'تم تنفيذ أمر البيع.');
  String get cancelSalesOrderQ => _t('Cancel sales order?', 'إلغاء أمر البيع؟');
  String get salesOrderCancelled => _t('Sales order cancelled.', 'تم إلغاء أمر البيع.');
  String get salesOrderUpdated => _t('Sales order updated.', 'تم تحديث أمر البيع.');
  String get onlyAdminEditsFulfilled => _t(
        'Only an admin can change the lines of a fulfilled order.',
        'تعديل أسطر أمر بيع منفَّذ متاح للمدير فقط.',
      );
  String get cancelFulfilledOrderMessage => _t(
        'This order was already fulfilled — its goods will be returned to stock and its ledger entry reversed.',
        'هذا الأمر مُنفَّذ بالكامل — ستُرجَع الكميات إلى المخزون وسيُعكس القيد المحاسبي.',
      );
  String get cancelReceivedOrderMessage => _t(
        'This order has received goods — they will be taken out of stock and the supplier balance and ledger entry reversed.',
        'هذا الأمر مُستلَم — ستُخصَم الكميات من المخزون ويُعدَّل رصيد المورد ويُعكس القيد المحاسبي.',
      );
  String get draftInvoiceCreated => _t(
        'Draft invoice created. Issue it from Invoices.',
        'تم إنشاء فاتورة مسودة. أصدرها من الفواتير.',
      );
  String get salesOrderNotFound => _t('Sales order not found.', 'أمر البيع غير موجود.');
  String get channel => _t('Channel', 'القناة');
  String get fulfilled => _t('Fulfilled', 'المنفذ');
  String get productsToSell => _t('Products to sell', 'المنتجات المطلوب بيعها');
  String lineQtyFulfilled(int qty, int fulfilled) =>
      _t('qty $qty · fulfilled $fulfilled', 'الكمية $qty · المنفذ $fulfilled');
  String get selectAWarehouseShort => _t('Select a warehouse.', 'اختر مستودعًا.');

  // ---------------------------------------------------------------------------
  // Invoices
  // ---------------------------------------------------------------------------
  String get searchInvoicesHint =>
      _t('Search invoices by number or customer…', 'ابحث في الفواتير بالرقم أو العميل…');
  String get noInvoices => _t('No invoices', 'لا توجد فواتير');
  String get invoicesCreatedHint => _t(
        'Invoices are created from sales orders or the POS screen.',
        'تُنشأ الفواتير من أوامر البيع أو شاشة نقطة البيع.',
      );
  String get overdue => _t('Overdue', 'متأخرة');
  String get invoiceNotFound => _t('Invoice not found.', 'الفاتورة غير موجودة.');
  String get issued => _t('Issued', 'تاريخ الإصدار');
  String get due => _t('Due', 'الاستحقاق');
  String get noLinesOnInvoice =>
      _t('No lines on this invoice.', 'لا توجد أسطر في هذه الفاتورة.');
  String get issue => _t('Issue', 'إصدار');
  String get recordPayment => _t('Record payment', 'تسجيل دفعة');
  String get voidLabel => _t('Void', 'إبطال');
  String get issueInvoiceQ => _t('Issue this invoice?', 'إصدار هذه الفاتورة؟');
  String get issueInvoiceMessage => _t(
        'Issued invoices can receive payments and cannot be edited.',
        'يمكن للفواتير الصادرة استقبال المدفوعات ولا يمكن تعديلها.',
      );
  String get invoiceIssued => _t('Invoice issued.', 'تم إصدار الفاتورة.');
  String get voidInvoiceQ => _t('Void this invoice?', 'إبطال هذه الفاتورة؟');
  String get voidInvoiceMessage => _t(
        'Voiding is permanent. Invoices with recorded payments cannot be voided.',
        'الإبطال نهائي. لا يمكن إبطال الفواتير التي لها مدفوعات مسجلة.',
      );
  String get invoiceVoided => _t('Invoice voided.', 'تم إبطال الفاتورة.');
  String get invoiceDetails => _t('Invoice details', 'تفاصيل الفاتورة');
  String get dueDate => _t('Due date', 'تاريخ الاستحقاق');
  String get productsAndServices => _t(
        'Products and services on this invoice',
        'المنتجات والخدمات في هذه الفاتورة',
      );
  String get itemFallback => _t('Item', 'صنف');
  String qtyTimesPrice(String qty, String price) =>
      _t('qty $qty × $price', 'الكمية $qty × $price');
  String get eachLineNeedsProduct =>
      _t('Each line needs a product or description and a quantity.',
          'كل سطر يحتاج إلى منتج أو وصف وكمية.');
  String get invoiceUpdated => _t('Invoice updated.', 'تم تحديث الفاتورة.');

  // ---------------------------------------------------------------------------
  // Payments
  // ---------------------------------------------------------------------------
  String get searchPaymentsHint =>
      _t('Search payments by number or reference…', 'ابحث في المدفوعات بالرقم أو المرجع…');
  String get direction => _t('Direction', 'الاتجاه');
  String get allPayments => _t('All payments', 'كل المدفوعات');
  String get inboundReceived => _t('Inbound (received)', 'وارد (مستلَم)');
  String get outboundPaid => _t('Outbound (paid)', 'صادر (مدفوع)');
  String get noPayments => _t('No payments', 'لا توجد مدفوعات');
  String get paymentsHint =>
      _t('Payments recorded against invoices appear here.', 'ستظهر هنا المدفوعات المسجلة على الفواتير.');
  String get inbound => _t('Inbound', 'وارد');
  String get outbound => _t('Outbound', 'صادر');
  String get payment => _t('Payment', 'دفعة');
  String get paymentRecorded => _t('Payment recorded.', 'تم تسجيل الدفعة.');
  String get method => _t('Method', 'الطريقة');
  String get amount => _t('Amount', 'المبلغ');
  String get paid => _t('Paid', 'المدفوع');
  String get paidOn => _t('Paid on', 'تاريخ الدفع');
  String get noInvoice => _t('No invoice', 'بدون فاتورة');
  String get chooseSupplier => _t('Choose a supplier', 'اختر موردًا');
  String get selectSupplier => _t('Select a supplier', 'اختر موردًا');
  String get selectCustomer => _t('Select a customer', 'اختر عميلًا');
  String get chequeOrTransferRef => _t('Cheque or transfer reference', 'مرجع الشيك أو التحويل');
  String get enterAmountGreaterThanZero =>
      _t('Enter an amount greater than zero', 'أدخل مبلغًا أكبر من صفر');
  String get recordAPayment => _t('Record a payment', 'تسجيل دفعة');
  String get invoice => _t('Invoice', 'فاتورة');

  // ---------------------------------------------------------------------------
  // Treasury (الخزينة)
  // ---------------------------------------------------------------------------
  String get treasury => _t('Treasury', 'الخزينة');
  String get cashBoxes => _t('Cash boxes', 'الخزائن');
  String get cashBox => _t('Cash box', 'خزنة');
  String get cashBoxesHint => _t(
        'Each cash box keeps its own balance. Sales, purchases, transfers and collections post here automatically.',
        'لكل خزنة رصيدها المستقل. تُسجَّل المبيعات والمشتريات والتحويلات والتحصيلات هنا تلقائيًا.',
      );
  String get newCashBox => _t('New cash box', 'خزنة جديدة');
  String get editCashBox => _t('Edit cash box', 'تعديل الخزنة');
  String get cashBoxName => _t('Cash box name', 'اسم الخزنة');
  String get cashBoxType => _t('Cash box type', 'نوع الخزنة');
  String get mainBox => _t('Main', 'رئيسية');
  String get subBox => _t('Sub', 'فرعية');
  String get defaultBox => _t('Default', 'افتراضية');
  String get setAsDefault => _t('Set as default', 'تعيين كافتراضية');
  String get totalInBoxes => _t('Total across boxes', 'إجمالي الخزائن');
  String get noCashBoxes => _t('No cash boxes yet', 'لا توجد خزائن بعد');
  String get boxSaved => _t('Cash box saved.', 'تم حفظ الخزنة.');
  String get boxDeleted => _t('Cash box deleted.', 'تم حذف الخزنة.');
  String get deleteBoxQ => _t('Delete this cash box?', 'حذف هذه الخزنة؟');
  String get deleteBoxMessage => _t(
        'Only boxes without any movements can be deleted. Deactivate a box instead to keep its history.',
        'لا يمكن حذف خزنة لها حركات. أوقفها بدلًا من ذلك للحفاظ على سجلها.',
      );
  String get boxHasMovements => _t(
        'This cash box has movements — deactivate it instead.',
        'هذه الخزنة لها حركات — أوقفها بدلًا من حذفها.',
      );
  String get boxStatement => _t('Cash box statement', 'كشف حساب الخزنة');
  String get totalIn => _t('Total in', 'إجمالي الوارد');
  String get totalOut => _t('Total out', 'إجمالي الصادر');
  String get newTransfer => _t('Transfer between boxes', 'تحويل بين الخزائن');
  String get transfersTitle => _t('Transfers', 'التحويلات');
  String get noTransfers => _t('No transfers yet', 'لا توجد تحويلات بعد');
  String get transfersHint => _t(
        'Movements between cash boxes appear here.',
        'تظهر هنا الحركات بين الخزائن.',
      );
  String get editTransfer => _t('Edit transfer', 'تعديل التحويل');
  String get fromBox => _t('From box', 'من خزنة');
  String get toBox => _t('To box', 'إلى خزنة');
  String get transferAmount => _t('Transfer amount', 'مبلغ التحويل');
  String get transferSaved => _t('Transfer completed.', 'تم تنفيذ التحويل.');
  String get transferUpdated => _t('Transfer updated.', 'تم تحديث التحويل.');
  String get transferCancelled => _t('Transfer cancelled.', 'تم إلغاء التحويل.');
  String get cancelTransferQ => _t('Cancel this transfer?', 'إلغاء هذا التحويل؟');
  String get cancelTransfer => _t('Cancel transfer', 'إلغاء التحويل');
  String get sameBox => _t('Choose two different boxes', 'اختر خزنتين مختلفتين');
  String get insufficientFunds => _t(
        'The selected cash box does not have enough funds.',
        'لا يوجد رصيد كافٍ في الخزنة المحددة.',
      );
  String get deposit => _t('Deposit', 'إيداع');
  String get withdraw => _t('Withdraw', 'سحب');
  String get depositIntoBox => _t('Deposit into box', 'إيداع في الخزنة');
  String get withdrawFromBox => _t('Withdraw from box', 'سحب من الخزنة');
  String get chooseBox => _t('Choose a cash box', 'اختر خزنة');
  String get box => _t('Box', 'الخزنة');
  String get paymentIn => _t('Receipt', 'وارد');
  String get paymentOut => _t('Payment', 'صادر');
  String get transferIn => _t('Transfer in', 'تحويل وارد');  String get transferOut => _t('Transfer out', 'تحويل صادر');
  String get collections => _t('Collections', 'إيصالات التحصيل');
  String get none => _t('None', 'بدون');
  String get noSalesperson => _t('No salesperson', 'بدون مندوب');
  String get collection => _t('Collection receipt', 'إيصال تحصيل');
  String get newCollection => _t('New collection receipt', 'إيصال تحصيل جديد');
  String get collectionsHint => _t(
        "Collect several customers' dues in one receipt handed in by an agent.",
        'حصّل مستحقات عدة عملاء في إيصال واحد يورده المندوب.',
      );
  String get collectionSaved => _t('Collection receipt saved.', 'تم حفظ إيصال التحصيل.');
  String get collectionCancelled =>
      _t('Collection receipt cancelled.', 'تم إلغاء إيصال التحصيل.');
  String get cancelCollectionQ => _t('Cancel this receipt?', 'إلغاء هذا الإيصال؟');
  String get cancelCollectionMessage => _t(
        'Every payment created by this receipt is cancelled and the balances are restored.',
        'سيتم إلغاء كل الدفعات الناتجة عن هذا الإيصال وإرجاع الأرصدة.',
      );
  String get noCollections => _t('No collection receipts', 'لا توجد إيصالات تحصيل');
  String get collectionLines => _t('Collection lines', 'أسطر التحصيل');
  String get voucherTotal => _t('Receipt total', 'إجمالي الإيصال');
  String get lineNeedsCustomer =>
      _t('Choose a customer for every line', 'اختر عميلًا لكل سطر');
  String get lineNeedsAmount => _t(
        'Enter an amount greater than zero for every line',
        'أدخل مبلغًا أكبر من صفر لكل سطر',
      );
  String get collectAll => _t('Collect all balances', 'تحصيل كل الأرصدة');
  String get fullBalance => _t('Full balance', 'كامل الرصيد');
  String get outstandingBalance => _t('Outstanding', 'المستحق');
  String get remainingBalance => _t('Remaining', 'المتبقي');
  String get showAllCustomers => _t('Show all customers', 'إظهار كل العملاء');
  String get customersToCollect => _t('Customers to collect', 'عملاء التحصيل');
  String get noAmountsEntered => _t(
        'Enter an amount for at least one customer',
        'أدخل مبلغًا لعميل واحد على الأقل',
      );
  String get clearAmounts => _t('Clear amounts', 'مسح المبالغ');
  String get periodBalance => _t('Period balance', 'رصيد الفترة');
  String get cancelPaymentQ => _t('Cancel this payment?', 'إلغاء هذه الدفعة؟');
  String get cancelPaymentMessage => _t(
        'The journal entry is reversed and the cash box, invoice and customer balances are restored.',
        'سيتم عكس القيد وإرجاع أرصدة الخزنة والفاتورة والعميل.',
      );
  String get paymentCancelled => _t('Payment cancelled.', 'تم إلغاء الدفعة.');
  String get paymentUpdated => _t('Payment updated.', 'تم تحديث الدفعة.');
  String get editPayment => _t('Edit payment', 'تعديل الدفعة');

  // ---------------------------------------------------------------------------
  // Reports
  // ---------------------------------------------------------------------------
  String get sales => _t('Sales', 'المبيعات');
  String get topProducts => _t('Top products', 'أفضل المنتجات');
  String get valuation => _t('Valuation', 'التقييم');
  String get customerBalances => _t('Customer balances', 'أرصدة العملاء');
  String get customerRoute => _t('Sales route', 'خط السير');
  String get noRoute => _t('No route', 'بدون خط سير');
  String get customerRoutes => _t('Sales routes', 'خطوط السير');
  String get customerRoutesHint => _t(
        'Assigning a route to a salesperson moves all its customers to them automatically.',
        'عند ربط خط السير بمندوب يتم نقل كل عملاء الخط إليه تلقائياً.',
      );
  String get dormantCustomers =>
      _t('Dormant customers', 'العملاء الراكدون');
  String get dormantCustomersHint => _t(
        'Active customers with no invoice in the selected period.',
        'العملاء النشطون بدون أي فاتورة خلال المدة المحددة.',
      );
  String get neverInvoiced => _t('Never invoiced', 'لم تُصدر له فاتورة');
  String get lastInvoice => _t('Last invoice', 'آخر فاتورة');
  String get supplierBalances => _t('Supplier balances', 'أرصدة الموردين');
  String get noSalesInPeriod => _t('No sales in this period', 'لا توجد مبيعات في هذه الفترة');
  String get salesByDay => _t('Sales by day', 'المبيعات حسب اليوم');
  String get revenuePerDay =>
      _t('Revenue per day for the current year', 'الإيرادات اليومية للسنة الحالية');
  String get noProductSalesYet => _t('No product sales yet', 'لا توجد مبيعات منتجات بعد');
  String get last30Days => _t('Last 30 days by revenue', 'آخر 30 يومًا حسب الإيرادات');
  String get noStockToValuate => _t('No stock to value', 'لا يوجد مخزون للتقييم');
  String get stockLines => _t('Stock lines', 'أسطر المخزون');
  String get units => _t('Units', 'الوحدات');
  String get costValue => _t('Cost value', 'قيمة التكلفة');
  String get retailValue => _t('Retail value', 'قيمة البيع');
  String get valuationByLine => _t('Valuation by line', 'التقييم حسب السطر');
  String get noOutstandingBalances => _t('No outstanding balances', 'لا توجد أرصدة مستحقة');
  String customerCountLabel(String count) => _t('$count customer(s)', '$count عميل');
  String supplierCountLabel(String count) => _t('$count supplier(s)', '$count مورد');
  String invoiceCountLabel(String count) => _t('$count invoice(s)', '$count فاتورة');
  String poCountLabel(String count) => _t('$count PO(s)', '$count أمر شراء');
  String get itemLower => _t('Item', 'صنف');
  String lineWithQty(String sku, String qty) =>
      _t('$sku · qty $qty', '$sku · الكمية $qty');

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------
  String get company => _t('Company', 'الشركة');
  String get currencies => _t('Currencies', 'العملات');
  String get settingsSaved => _t('Settings saved.', 'تم حفظ الإعدادات.');
  String get couldNotSave => _t('Could not save.', 'تعذّر الحفظ.');
  String get couldNotLoadSettings => _t('Could not load settings.', 'تعذّر تحميل الإعدادات.');
  String get companyName => _t('Company name', 'اسم الشركة');
  String get companyNameRequired => _t('Company name is required', 'اسم الشركة مطلوب');
  String get defaults => _t('Defaults', 'الإعدادات الافتراضية');
  String get baseCurrencyCode => _t('Base currency code', 'رمز العملة الأساسية');
  String get baseCurrencyHelper => _t('e.g. USD, EUR, NGN', 'مثال: USD، EUR، NGN');
  String get baseCurrencyRequired => _t('Base currency is required', 'العملة الأساسية مطلوبة');
  String get defaultTaxRate => _t('Default tax rate (%)', 'نسبة الضريبة الافتراضية (%)');
  String get enterRate => _t('Enter a rate between 0 and 100', 'أدخل نسبة بين 0 و100');
  String get lowStockAlertsSetting => _t('Low stock alerts', 'تنبيهات نقص المخزون');
  String get numberPrefixes => _t('Number prefixes', 'بادئات الأرقام');
  String get purchaseOrderPrefix => _t('Purchase order', 'أمر شراء');
  String get salesOrderPrefix => _t('Sales order', 'أمر بيع');
  String get journalEntry => _t('Journal entry', 'قيد اليومية');
  String get saveSettings => _t('Save settings', 'حفظ الإعدادات');
  String get noCurrencies => _t('No currencies', 'لا توجد عملات');
  String get currenciesManagedHint => _t(
        'Add currencies here and choose the base currency.',
        'أضف العملات من هنا وحدد العملة الأساسية.',
      );
  String rateValue(String value) => _t('Rate $value', 'السعر $value');
  String get baseLabel => _t('Base', 'أساسية');
  String get addCurrency => _t('Add currency', 'إضافة عملة');
  String get editCurrency => _t('Edit currency', 'تعديل العملة');
  String get symbol => _t('Symbol', 'الرمز');
  String get exchangeRateLabel =>
      _t('Exchange rate (vs base currency)', 'سعر الصـرف (مقابل العملة الأساسية)');
  String get enterPositiveRate =>
      _t('Enter a rate greater than zero', 'أدخل سعرًا أكبر من صفر');
  String get currencyCodeRequired =>
      _t('Currency code is required', 'رمز العملة مطلوب');
  String get setAsBaseLabel =>
      _t('Base currency', 'العملة الأساسية');
  String get keepBaseCurrency => _t(
        'A currency must remain the base. To switch, set another currency as the base instead.',
        'يجب أن تبقى هناك عملة أساسية. بدّلها بتحديد عملة أخرى كأساسية.',
      );
  String deleteCurrencyQ(String code) => _t('Delete $code?', 'حذف $code؟');
  String get deleteCurrencyMessage =>
      _t('This cannot be undone.', 'لا يمكن التراجع عن هذا.');
  String get currencyCreated => _t('Currency created.', 'تم إنشاء العملة.');
  String get currencyUpdated => _t('Currency updated.', 'تم تحديث العملة.');
  String get currencyDeleted => _t('Currency deleted.', 'تم حذف العملة.');
  String get baseCurrencyUpdated =>
      _t('Base currency updated.', 'تم تحديث العملة الأساسية.');

  // ---------------------------------------------------------------------------
  // Users
  // ---------------------------------------------------------------------------
  String get searchUsersHint => _t('Search users by name or email…', 'ابحث في المستخدمين بالاسم أو البريد…');
  String get role => _t('Role', 'الدور');
  String get allRoles => _t('All roles', 'كل الأدوار');
  String get noUsers => _t('No users', 'لا يوجد مستخدمون');
  String get inviteUserHint => _t('Invite a colleague to collaborate.', 'ادعُ زميلًا للتعاون.');
  String get user => _t('User', 'مستخدم');
  String get deactivate => _t('Deactivate', 'إلغاء التنشيط');
  String deactivateUserQ(String name) => _t('Deactivate $name?', 'إلغاء تنشيط $name؟');
  String get deactivateUserMessage =>
      _t('The user will no longer be able to sign in.', 'لن يتمكن المستخدم من تسجيل الدخول بعد الآن.');
  String get userDeactivated => _t('User deactivated.', 'تم إلغاء تنشيط المستخدم.');
  String get editUser => _t('Edit user', 'تعديل المستخدم');
  String get newUser => _t('New user', 'مستخدم جديد');
  String get newPasswordOptional => _t('New password (optional)', 'كلمة مرور جديدة (اختياري)');
  String get useAtLeast8 => _t('Use at least 8 characters', 'استخدم 8 أحرف على الأقل');
  String get userUpdated => _t('User updated.', 'تم تحديث المستخدم.');
  String get userCreated => _t('User created.', 'تم إنشاء المستخدم.');

  // ---------------------------------------------------------------------------
  // Accounting
  // ---------------------------------------------------------------------------
  String get accountType => _t('Account type', 'نوع الحساب');
  String get noAccounts => _t('No accounts', 'لا توجد حسابات');
  String get chartCreatedHint => _t(
        'The chart of accounts is created automatically on first use.',
        'يُنشأ دليل الحسابات تلقائيًا عند أول استخدام.',
      );
  String accountCount(int n) => _t('$n account(s)', '$n حساب');
  String get accountWord => _t('Account', 'حساب');
  String get newAccount => _t('New account', 'حساب جديد');
  String get accountCreated => _t('Account created.', 'تم إنشاء الحساب.');
  String get searchJournalHint =>
      _t('Search journal by number, memo or reference…', 'ابحث في اليومية بالرقم أو المذكرة أو المرجع…');
  String get noJournalEntries => _t('No journal entries', 'لا توجد قيود يومية');
  String get journalHint => _t(
        'Entries are posted automatically by invoices and payments.',
        'تُرحّل القيود تلقائيًا بواسطة الفواتير والمدفوعات.',
      );
  String get noLinesOnEntry => _t('No lines on this entry.', 'لا توجد أسطر في هذا القيد.');
  String get totals => _t('Totals', 'الإجماليات');
  String creditAmount(String amount) => _t('credit $amount', 'دائن $amount');
  String get debit => _t('Debit', 'مدين');
  String get credit => _t('Credit', 'دائن');
  String get dr => _t('Dr', 'مدين');
  String get cr => _t('Cr', 'دائن');
  String get bal => _t('Bal', 'رصيد');

  // ---------------------------------------------------------------------------
  // Statement
  // ---------------------------------------------------------------------------
  String get statement => _t('Statement', 'كشف حساب');
  String get currentBalance => _t('Current balance', 'الرصيد الحالي');
  String get creditLimitLabel => _t('Credit limit', 'حد الائتمان');
  String get period => _t('Period', 'الفترة');
  String get ledger => _t('Ledger', 'دفتر الأستاذ');
  String entriesCount(int n) => _t('$n entr${n == 1 ? 'y' : 'ies'}', '$n قيد');
  String get noEntriesForPeriod => _t('No entries for this period.', 'لا توجد قيود في هذه الفترة.');
  String get openingBalance => _t('Opening balance', 'الرصيد الافتتاحي');
  String get generalLedger => _t('General ledger', 'دفتر الأستاذ العام');
  String get chooseAccount => _t('Choose an account', 'اختر حساباً');
  String get totalDebit => _t('Total debit', 'إجمالي المدين');
  String get totalCredit => _t('Total credit', 'إجمالي الدائن');
  String get closingBalance => _t('Closing balance', 'الرصيد الختامي');
  String get printStatement => _t('Print statement', 'طباعة كشف الحساب');
  String get couldNotLoadStatement =>
      _t('Could not load the statement.', 'تعذّر تحميل كشف الحساب.');
  String get statementNotFound => _t('Statement not found.', 'كشف الحساب غير موجود.');

  // ---------------------------------------------------------------------------
  // Business status labels
  // ---------------------------------------------------------------------------
  static const Map<String, String> _statusAr = <String, String>{
    // Document / order statuses.
    'DRAFT': 'مسودة',
    'ISSUED': 'صادرة',
    'PAID': 'مدفوعة',
    'PARTIALLY_PAID': 'مدفوعة جزئيًا',
    'VOID': 'ملغاة',
    'PENDING': 'قيد الانتظار',
    'APPROVED': 'معتمدة',
    'RECEIVED': 'مستلمة',
    'PARTIALLY_RECEIVED': 'مستلمة جزئيًا',
    'CONFIRMED': 'مؤكدة',
    'FULFILLED': 'منفذة',
    'PARTIALLY_FULFILLED': 'منفذة جزئيًا',
    'CANCELLED': 'ملغاة',
    'POSTED': 'مرحّلة',
    'ACTIVE': 'نشط',
    'INACTIVE': 'غير نشط',
    'OVERDUE': 'متأخرة',
    'INVOICE': 'فاتورة',
    'PAYMENT': 'سداد',
    'PURCHASE_ORDER': 'أمر شراء',
    'RETURN': 'مرتجع',
    'SETTLEMENT': 'تسوية',
    // Roles.
    'ADMIN': 'مدير النظام',
    'MANAGER': 'مدير',
    'SALES': 'مبيعات',
    'CASHIER': 'أمين صندوق',
    'WAREHOUSE': 'أمين مستودع',
    'ACCOUNTANT': 'محاسب',
    // Payment methods.
    'CASH': 'نقدًا',
    'CARD': 'بطاقة',
    'BANK_TRANSFER': 'تحويل بنكي',
    'MOBILE_MONEY': 'محفظة إلكترونية',
    'CHEQUE': 'شيك',
    'OTHER': 'أخرى',
    // Directions / channels.
    'INBOUND': 'وارد',
    'OUTBOUND': 'صادر',
    'MANUAL': 'يدوي',
    'POS': 'نقطة البيع',
    // Inventory movement types.
    'OPENING': 'رصيد افتتاحي',
    'RECEIVE': 'استلام',
    'DISPATCH': 'صرف',
    'ADJUSTMENT': 'تسوية',
    'TRANSFER_IN': 'تحويل وارد',
    'TRANSFER_OUT': 'تحويل صادر',
    'SALE': 'بيع',
    'SALE_RETURN': 'مرتجع بيع',
    'PURCHASE': 'شراء',
    'PURCHASE_RETURN': 'مرتجع شراء',
    'CYCLE_COUNT': 'جرد دوري',
    // Account types.
    'ASSET': 'أصول',
    'LIABILITY': 'التزامات',
    'EQUITY': 'حقوق ملكية',
    'REVENUE': 'إيرادات',
    'EXPENSE': 'مصروفات',
  };

  /// Translates an enum-like business value (status, role, method, type) into
  /// the active language, falling back to [Formatters.label] for unknown keys.
  String status(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';
    final key = raw.trim().toUpperCase();
    final ar = _statusAr[key];
    if (ar != null) return isArabic ? ar : Formatters.label(raw);
    return Formatters.label(raw);
  }

  // ---------------------------------------------------------------------------
  // Reports, statements & settings (extended suite)
  // ---------------------------------------------------------------------------
  String get report => _t('Report', 'تقرير');
  String get receipts => _t('Receipts', 'المقبوضات');
  String get receivablesBySalesperson => _t(
        'Receivables by salesperson',
        'مديونية العملاء لكل مندوب',
      );
  String get receivablesBySalespersonHint => _t(
        'Outstanding customer balances grouped by the salesperson who sold to them.',
        'أرصدة العملاء المستحقة مجمّعة حسب المندوب الذي باع لهم.',
      );
  String get supplierPayables => _t('Supplier payables', 'مديونية الموردين');
  String get supplierPayablesHint => _t(
        'Full outstanding balance owed to every supplier.',
        'كامل الرصيد المستحق لكل مورد.',
      );
  String get stockBalance => _t('Stock balance', 'رصيد المخزون');
  String get stockBalanceHint => _t(
        'On-hand quantity and value for counting and review.',
        'الكمية والقيمة المتاحة للجرد والمراجعة.',
      );
  String get itemMovement => _t('Item movement', 'حركة صنف');
  String get itemMovementHint => _t(
        'Every movement of a single product with a running balance.',
        'كل حركات صنف واحد مع الرصيد الجاري.',
      );
  String get statements => _t('Statements', 'كشوف الحسابات');
  String get customerStatement => _t('Customer statement', 'كشف حساب عميل');
  String get supplierStatement => _t('Supplier statement', 'كشف حساب مورد');
  String get statementsHint => _t(
        'Pick a customer or supplier and a date range to build a statement.',
        'اختر عميلًا أو موردًا وفترة زمنية لإنشاء كشف الحساب.',
      );
  String get chooseCustomer => _t('Choose a customer', 'اختر عميلًا');
  String get chooseProduct => _t('Choose a product', 'اختر صنفًا');
  String get chooseSalesperson => _t('Choose a salesperson', 'اختر مندوبًا');
  String get applyFilters => _t('Apply', 'تطبيق');
  String get viewStatement => _t('View statement', 'عرض كشف الحساب');
  String get salesperson => _t('Salesperson', 'المندوب');
  String get unassigned => _t('Unassigned', 'بدون مندوب');
  String get purchases => _t('Purchases', 'المشتريات');
  String get quantity => _t('Quantity', 'الكمية');
  String get available => _t('Available', 'المتاح');
  String get allProducts => _t('All products', 'كل الأصناف');
  String get availableOnly => _t('Available only', 'المتوفر فقط');
  String get priceList => _t('Price list', 'قائمة الأسعار');
  String productCountLabel(String count) =>
      _t('$count product(s)', '$count صنف');
  String get reservedQty => _t('Reserved', 'المحجوز');
  String get date => _t('Date', 'التاريخ');
  String get openingShort => _t('Opening', 'الافتتاحي');
  String get closingShort => _t('Closing', 'الختامي');
  String get inShort => _t('In', 'وارد');
  String get outShort => _t('Out', 'منصرف');
  String get runningBalance => _t('Running balance', 'الرصيد الجاري');
  String get noDataForFilters => _t(
        'No data for the selected filters.',
        'لا توجد بيانات للفلاتر المحددة.',
      );
  String get selectProductFirst => _t(
        'Select a product first.',
        'اختر صنفًا أولًا.',
      );
  String get selectPersonFirst => _t(
        'Select a customer or supplier first.',
        'اختر عميلًا أو موردًا أولًا.',
      );
  String get allSalespeople => _t('All salespeople', 'كل المندوبين');
  String get salespeople => _t('Salespeople', 'المناديب');
  String get salespeopleReports => _t('Salespeople reports', 'تقارير المناديب');
  String get consolidatedSalesNote =>
      _t('Consolidated sales note', 'الإذن المجمع للمبيعات');
  String get consolidatedSalesNoteHint => _t(
        'Fulfilled quantities per product, grouped by salesperson, for the chosen period.',
        'الكميات المنفَّذة لكل صنف مجمّعة لكل مندوب خلال الفترة المحددة.',
      );
  String get profitBySalesperson =>
      _t('Profitability by salesperson', 'ربحية كل مندوب');
  String get profitBySalespersonHint => _t(
        'Sales revenue (net of discount) minus the cost of goods, per salesperson.',
        'إيراد المبيعات (بعد الخصم) ناقص تكلفة البضاعة المباعة، لكل مندوب.',
      );
  String get collectionsBySalesperson =>
      _t('Collections by salesperson', 'تحصيلات كل مندوب');
  String get collectionsBySalespersonHint => _t(
        'What each salesperson collected from customers in the period.',
        'ما حصّله كل مندوب من العملاء خلال الفترة.',
      );
  String get salespersonStatement =>
      _t('Salesperson statement', 'كشف حساب مندوب');
  String get pickSalespersonFirst => _t(
        'Choose a salesperson to show their statement.',
        'اختر مندوبًا لعرض كشف حسابه.',
      );
  String get soldProducts => _t('Products sold', 'الأصناف المباعة');
  String get netSales => _t('Net sales', 'صافي المبيعات');
  String get grossSales => _t('Gross sales', 'إجمالي المبيعات');
  String get collected => _t('Collected', 'المحصّل');
  String get collectionVouchers =>
      _t('Collection receipts', 'إيصالات التحصيل');
  String get dateRange => _t('Date range', 'الفترة الزمنية');
  String get taxSettings => _t('Tax', 'الضريبة');
  String get enableTax => _t('Enable tax', 'تفعيل الضريبة');
  String get enableTaxHint => _t(
        'When disabled, tax is set to zero on all new sales, purchases and invoices.',
        'عند التعطيل تُصفَّر الضريبة على كل المبيعات والمشتريات والفواتير الجديدة.',
      );
  String get dashboardLayout => _t('Dashboard sections', 'أقسام لوحة التحكم');
  String get dashboardLayoutHint => _t(
        'Choose which sections appear on the dashboard.',
        'اختر الأقسام التي تظهر في لوحة التحكم.',
      );
  String get dashKpis => _t('Key figures', 'المؤشرات');
  String get dashQuickActions => _t('Quick actions', 'إجراءات سريعة');
  String get dashLowStock => _t('Low-stock alerts', 'تنبيهات نقص المخزون');
  String get dashRecentMovements => _t('Recent movements', 'أحدث الحركات');

  // ---------------------------------------------------------------------------
  // Company details (بيانات الشركة)
  // ---------------------------------------------------------------------------
  String get logoUrl => _t('Logo URL', 'رابط اللوجو');
  String get logoUrlHint => _t(
        'Paste a link to the company logo (PNG/JPG).',
        'الصق رابط اللوجو الخاص بالشركة (PNG/JPG).',
      );
  String get commercialRegister => _t('Commercial register', 'السجل التجاري');
  String get taxCard => _t('Tax card', 'البطاقة الضريبية');
  String get companyDetails => _t('Company details', 'بيانات الشركة');
  String get companyDetailsHint => _t(
        'Shown on the app header and printed documents.',
        'تظهر في ترويسة التطبيق والوثائق المطبوعة.',
      );

  // ---------------------------------------------------------------------------
  // Returns (المرتجعات)
  // ---------------------------------------------------------------------------
  String get returns => _t('Returns', 'المرتجعات');
  String get searchReturnsHint => _t('Search returns…', 'ابحث في المرتجعات…');
  String get newReturn => _t('New return', 'مرتجع جديد');
  String get customerReturns => _t('Customer returns', 'مرتجعات العملاء');
  String get supplierReturns => _t('Supplier returns', 'مرتجعات الموردين');
  String get returnOrder => _t('Return order', 'أمر مرتجع');
  String get returnOrderCreated => _t('Return order created.', 'تم إنشاء أمر المرتجع.');
  String get returnOrderUpdated => _t('Return order updated.', 'تم تحديث أمر المرتجع.');
  String get editReturnOrder => _t('Edit return order', 'تعديل أمر المرتجع');
  String get returnPosted => _t('Return posted. Stock and balances updated.', 'تم ترحيل المرتجع. تم تحديث المخزون والأرصدة.');
  String get returnCancelled => _t('Return order cancelled.', 'تم إلغاء أمر المرتجع.');
  String get postReturn => _t('Post return', 'ترحيل المرتجع');
  String get cancelReturn => _t('Cancel return', 'إلغاء المرتجع');
  String get returnLinesHint => _t('Products returned and their quantities.', 'المنتجات المرتجعة والكميات.');
  String get returnProductsToSell => _t('Returned products', 'المنتجات المرتجعة');
  String get selectCustomerOrSupplier => _t('Select a customer or supplier first.', 'اختر عميلًا أو موردًا أولًا.');
  String get addAtLeastOneReturnLine => _t('Add at least one complete return line.', 'أضف سطر مرتجع واحدًا على الأقل.');
  String get noReturnsYet => _t('No returns yet', 'لا توجد مرتجعات بعد');
  String get noReturnsHint => _t(
        'Returns you create for customers or suppliers will appear here.',
        'ستظهر هنا المرتجعات التي تنشئها للعملاء أو الموردين.',
      );
  String get returnType => _t('Return type', 'نوع المرتجع');
  String get partner => _t('Partner', 'الطرف');
  String get postReturnQ => _t('Post this return?', 'ترحيل هذا المرتجع؟');
  String postReturnHint(String number) => _t(
        '“$number” will update stock, partner balance and the journal. It cannot be undone.',
        'سيُحدّث «$number» المخزون ورصيد الشريك والدفتر اليومي، ولا يمكن التراجع عن ذلك.',
      );
  String get cancelReturnQ => _t('Cancel this return?', 'إلغاء أمر المرتجع؟');
  String get salePriceBelowCost => _t(
        'Sale price cannot be lower than the cost price.',
        'لا يمكن أن يكون سعر البيع أقل من سعر التكلفة.',
      );
  String priceBelowCost(String name) => _t(
        'Price for “$name” is below its cost.',
        'سعر «$name» أقل من التكلفة.',
      );
  String get quickAddProduct => _t('Add new product', 'إضافة منتج جديد');
  String get quickAddProductHint => _t(
        'The product does not exist yet — create it and pick it instantly.',
        'المنتج غير موجود بعد — أنشئه واختره فورًا.',
      );

  // ---------------------------------------------------------------------------
  // Collection receipt — per-line cash box (خزنة السطر)
  // ---------------------------------------------------------------------------
  String get receiptBox => _t('Receipt box', 'خزنة الإيصال');
  String get lineCashBox => _t('Cash box (optional)', 'الخزنة (اختيارية)');
  String useBox(String name) =>
      _t('Receipt box: $name', 'خزنة الإيصال: $name');

  // ---------------------------------------------------------------------------
  // Reports tree (شجرة التقارير)
  // ---------------------------------------------------------------------------
  String get reportTreeHint => _t(
        'Open a branch, then pick the report you need.',
        'افتح فرعًا ثم اختر التقرير الذي تحتاجه.',
      );
  String get accounting => _t('Accounting', 'المحاسبة');
  String get purchasesReport => _t('Purchases report', 'تقرير المشتريات');
  String get purchasesReportHint => _t(
        'Purchase order totals grouped by day or month.',
        'إجماليات أوامر الشراء مجمّعة يوميًا أو شهريًا.',
      );
  String get salesProfit => _t('Sales profit', 'أرباح المبيعات');
  String get salesProfitHint => _t(
        'Revenue minus the cost of the goods sold.',
        'الإيرادات ناقص تكلفة البضاعة المباعة.',
      );
  String get taxReport => _t('Tax report', 'تقرير الضريبة');
  String get taxReportHint => _t(
        'Output tax on sales minus input tax on purchases.',
        'ضريبة المخرجات على المبيعات ناقص ضريبة المدخلات على المشتريات.',
      );
  String get receivablesAging => _t('Receivables aging', 'أعمار ديون العملاء');
  String get receivablesAgingHint => _t(
        'Outstanding invoices split by how overdue they are.',
        'الفواتير المستحقة مقسّمة حسب تأخر سدادها.',
      );
  String get payablesAging => _t('Payables aging', 'أعمار التزامات الموردين');
  String get payablesAgingHint => _t(
        'Balances owed to suppliers, grouped by age.',
        'الأرصدة المستحقة للموردين مجمّعة حسب الأعمار.',
      );
  String get boxBalances => _t('Cash box balances', 'أرصدة الخزائن');
  String get boxBalancesHint => _t(
        'Opening balance and movements for every cash box.',
        'الرصيد الافتتاحي والحركات لكل خزنة نقدية.',
      );
  String get trialBalance => _t('Trial balance', 'ميزان المراجعة');
  String get trialBalanceHint => _t(
        'Debit and credit totals for every account.',
        'إجمالي المدين والدائن لكل حساب.',
      );
  String get incomeStatement => _t('Income statement', 'قائمة الدخل');
  String get incomeStatementHint => _t(
        'Revenue minus expenses for a period.',
        'الإيرادات ناقص المصروفات خلال فترة.',
      );
  String get balanceSheet => _t('Balance sheet', 'الميزانية العمومية');
  String get balanceSheetHint => _t(
        'Assets, liabilities and equity as of a date.',
        'الأصول والخصوم وحقوق الملكية حتى تاريخ.',
      );
  String get revenue => _t('Revenue', 'الإيرادات');
  String get expenses => _t('Expenses', 'المصروفات');
  String get assets => _t('Assets', 'الأصول');
  String get liabilities => _t('Liabilities', 'الخصوم');
  String get equity => _t('Equity', 'حقوق الملكية');
  String get netProfit => _t('Net profit', 'صافي الربح');
  String get costOfSales => _t('Cost of sales', 'تكلفة المبيعات');
  String get lastSalePriceToCustomer => _t('Last sale price to this customer', 'آخر سعر بيع لهذا العميل');
  String get showProfit => _t('Show profit', 'إظهار الربح');
  String get hideProfit => _t('Hide profit', 'إخفاء الربح');
  String get marginPercent => _t('Margin %', 'الهامش %');
  String get outputTax => _t('Output tax (sales)', 'ضريبة المخرجات (المبيعات)');
  String get inputTax =>
      _t('Input tax (purchases)', 'ضريبة المدخلات (المشتريات)');
  String get netTax => _t('Net tax payable', 'صافي الضريبة المستحقة');
  String get taxableSales => _t('Taxable sales', 'المبيعات الخاضعة');
  String get taxablePurchases =>
      _t('Taxable purchases', 'المشتريات الخاضعة');
  String get notYetDue => _t('Not yet due', 'غير مستحق');
  String get days1To30 => _t('1–30 days', '1–30 يوم');
  String get days31To60 => _t('31–60 days', '31–60 يوم');
  String get days61To90 => _t('61–90 days', '61–90 يوم');
  String get over90Days => _t('Over 90 days', 'أكثر من 90 يوم');
  String get asOf => _t('As of', 'حتى تاريخ');
  String get balanced => _t('Balanced', 'متوازن');
  String get notBalanced => _t('Not balanced', 'غير متوازن');
  String get reportNotFound => _t('Report not found', 'التقرير غير موجود');
  String get byDay => _t('By day', 'يوميًا');
  String get byMonth => _t('By month', 'شهريًا');
  String orderCountLabel(String count) => _t('$count order(s)', '$count أمر');
  String get orders => _t('Orders', 'الأوامر');
  String boxCountLabel(String count) => _t('$count box(es)', '$count خزنة');
  String get oldestDueDate => _t('Oldest due date', 'أقدم تاريخ استحقاق');

  // ---------------------------------------------------------------------------
  // Manual journal entry (القيد المحاسبي اليدوي)
  // ---------------------------------------------------------------------------
  String get newJournalEntry => _t('New journal entry', 'قيد يومية جديد');
  String get manualEntry => _t('Manual entry', 'قيد يدوي');
  String get entryDate => _t('Entry date', 'تاريخ القيد');
  String get memo => _t('Memo', 'البيان');
  String get journalSaved => _t('Journal entry saved.', 'تم حفظ القيد.');
  String get reverseEntry => _t('Reverse entry', 'عكس القيد');
  String get reverseEntryQ => _t(
        'Reverse this journal entry? A matching opposite entry will be created.',
        'هل تريد عكس هذا القيد؟ سيُنشأ قيد معاكس مماثل.',
      );
  String get entryReversed => _t('Entry reversed.', 'تم عكس القيد.');
  String get lineNeedsAccount => _t('Choose an account', 'اختر حسابًا');
  String get loadingAccounts => _t('Loading accounts…', 'جارٍ تحميل الحسابات…');
  String get lineNeedsAmountSide => _t(
        'Enter a debit or a credit',
        'أدخل مبلغاً مديناً أو دائناً',
      );
  String get journalEntriesHint => _t(
        'Every posting of the ledger. Open an entry to review its lines.',
        'كل قيود الدفتر. افتح القيد لمراجعة سطوره.',
      );
  String get backup => _t('Backup', 'النسخة الاحتياطية');
  String get backupTitle => _t('Full data backup', 'نسخة احتياطية كاملة');
  String get backupHint => _t(
        'Downloads everything as one Excel workbook: customers and suppliers with their balances, '
            'stock quantities and values, products, orders, invoices, payments, collections, '
            'cash boxes, journal entries and stock movements — one sheet per table.',
        'يُنزِّل كل البيانات في ملف Excel واحد: العملاء والموردون بأرصدتهم، كميات المخزون وقيمته، '
            'الأصناف، الأوامر، الفواتير، المدفوعات، التحصيلات، الخزائن، القيود المحاسبية وحركات المخزون — '
            'ورقة لكل جدول.',
      );
  String get downloadBackup => _t('Download backup (Excel)', 'تنزيل النسخة (Excel)');
  String get backupDownloading => _t('Preparing the file…', 'جارٍ تحضير الملف…');
  String get backupFailed => _t(
        'Could not create the backup file.',
        'تعذّر إنشاء ملف النسخة الاحتياطية.',
      );
  String get backupAdminOnly => _t(
        'Only an administrator can download a full backup.',
        'تنزيل النسخة الاحتياطية الكاملة متاح للمدير فقط.',
      );

  // --- Maintenance (الصيانة) ------------------------------------------------
  String get maintenanceTab => _t('Maintenance', 'الصيانة');
  String get clearDataTitle =>
      _t('Clear trading data', 'مسح بيانات التعاملات');
  String get clearDataHint => _t(
        'Deletes all products, customers and suppliers together with everything '
            'that depends on them: invoices, orders, payments, collections, '
            'returns, stock movements, opening balances and journal entries.\n\n'
            'Users, settings, the chart of accounts, cash boxes, warehouses, '
            'categories and currencies are kept.',
        'يمسح كل الأصناف والعملاء والموردين وكل ما يعتمد عليهم: الفواتير، '
            'الأوامر، المدفوعات، التحصيلات، المرتجعات، حركات المخزون، الأرصدة '
            'الافتتاحية والقيود المحاسبية.\n\n'
            'يبقى كما هو: المستخدمون، الإعدادات، دليل الحسابات، الخزائن، '
            'المخازن، التصنيفات والعملات.',
      );
  String get clearDataWarning => _t(
        'This cannot be undone. Take a backup first if you need the current data.',
        'لا يمكن التراجع عن هذه العملية. خُذ نسخة احتياطية أولاً إذا كنت تحتاج البيانات الحالية.',
      );
  String get clearDataButton => _t('Clear all trading data', 'مسح كل بيانات التعاملات');
  String get clearDataConfirmTitle => _t('Confirm deletion', 'تأكيد المسح');
  String get clearDataConfirmHint => _t(
        'Type DELETE-ALL to confirm.',
        'اكتب DELETE-ALL للتأكيد.',
      );
  String get clearDataDone => _t(
        'Trading data cleared.',
        'تم مسح بيانات التعاملات.',
      );
  String get clearDataFailed => _t(
        'Could not clear the data.',
        'تعذّر مسح البيانات.',
      );

  // --- Duplicate products (الأصناف المكررة) --------------------------------
  String get dedupeTitle => _t('Merge duplicate products', 'دمج الأصناف المكررة');
  String get dedupeHint => _t(
        'Finds products that share the same name and keeps only the oldest one. '
            'Any invoice, order or stock movement that pointed at a duplicate is '
            'moved to the kept product first, so nothing is lost.',
        'يبحث عن الأصناف اللي ليها نفس الاسم ويحتفظ بالأقدم فقط. أي فاتورة أو أمر '
            'أو حركة مخزون كانت مربوطة بنسخة مكررة بتتحوّل للصنف اللي فضل، فمفيش '
            'حاجة بتضيع.',
      );
  String get dedupeScan => _t('Check for duplicates', 'افحص المكرر');
  String get dedupeButton => _t('Delete duplicates', 'امسح المكرر');
  String get dedupeConfirmHint => _t(
        'Type DELETE-DUPLICATES to confirm.',
        'اكتب DELETE-DUPLICATES للتأكيد.',
      );
  String dedupeFound(int groups, int extra) => _t(
        '$groups duplicate names — $extra extra rows',
        '$groups اسم مكرر — $extra صف زيادة',
      );
  String get dedupeNone => _t('No duplicate products found.', 'مفيش أصناف مكررة.');
  String dedupeDone(int removed) => _t(
        'Removed $removed duplicate rows.',
        'تم مسح $removed صف مكرر.',
      );
  String get dedupeFailed => _t(
        'Could not check for duplicates.',
        'تعذّر فحص المكرر.',
      );

  // --- Expenses (المصروفات) -------------------------------------------------
  String get expensesTitle => _t('Expenses', 'المصروفات');
  String get expense => _t('Expense', 'مصروف');
  String get newExpense => _t('New expense', 'مصروف جديد');
  String get editExpense => _t('Edit expense', 'تعديل مصروف');
  String get noExpenses => _t('No expenses recorded', 'لا توجد مصروفات مسجلة');
  String get expensesHint => _t(
        'Record rent, salaries, utilities and any other cash outflow that is not tied to a supplier.',
        'سجّل الإيجار والرواتب والمرافق وأي مصروف نقدي آخر غير مرتبط بمورد.',
      );
  String get expenseSaved => _t('Expense recorded', 'تم تسجيل المصروف');
  String get expenseUpdated => _t('Expense updated', 'تم تحديث المصروف');
  String get expenseCancelled => _t('Expense cancelled', 'تم إلغاء المصروف');
  String get cancelExpenseQ => _t('Cancel this expense?', 'إلغاء هذا المصروف؟');
  String get expenseCategory => _t('Expense category', 'تصنيف المصروف');
  String get expenseCategories => _t('Expense categories', 'تصنيفات المصروفات');
  String get newExpenseCategory => _t('New category', 'تصنيف جديد');
  String get editExpenseCategory => _t('Edit category', 'تعديل تصنيف');
  String get noExpenseCategories =>
      _t('No expense categories yet', 'لا توجد تصنيفات مصروفات بعد');
  String get expenseCategoriesHint => _t(
        'Categories let you group expenses (rent, salaries, …) for reporting.',
        'التصنيفات تتيح تجميع المصروفات (إيجار، رواتب…) لأغراض التقارير.',
      );
  String get uncategorized => _t('Uncategorized', 'غير مصنّف');
  String get categorySaved => _t('Category saved', 'تم حفظ التصنيف');
  String get expenseCategoryUpdated => _t('Category updated', 'تم تحديث التصنيف');
  String get expenseCategoryDeleted => _t('Category deleted', 'تم حذف التصنيف');
  String get deleteExpenseCategoryQ =>
      _t('Delete this category?', 'حذف هذا التصنيف؟');
  String get categoryInUse => _t(
        'This category is used by recorded expenses — deactivate it instead.',
        'هذا التصنيف مستخدم في مصروفات مسجلة — أوقفه بدلاً من حذفه.',
      );
  String get payee => _t('Payee', 'المستفيد');
  String get expenseAmount => _t('Amount', 'المبلغ');
  String get expenseDate => _t('Expense date', 'تاريخ المصروف');
  String get expenseReport => _t('Expense report', 'تقرير المصروفات');
  String get printCategoryStatement =>
      _t('Print category statement', 'طباعة كشف البند');
  String get categoryStatementRange =>
      _t('Statement period', 'فترة الكشف');
  String get printCollectionsByBox =>
      _t('Collections by cash box', 'إيصالات التحصيل حسب الخزنة');
  String get collectionsByBoxHint => _t(
        'Shows the cash each box received from collections within the chosen period.',
        'يوضح النقدية الواردة لكل خزنة من التحصيلات خلال الفترة المختارة.',
      );
  String get expenseReportHint => _t(
        'Expenses grouped by category, month and cash box for the chosen period.',
        'المصروفات مجمّعة حسب التصنيف والشهر والخزنة خلال الفترة المختارة.',
      );
  String get expensesByCategory => _t('By category', 'حسب التصنيف');
  String get expensesByMonth => _t('By month', 'حسب الشهر');
  String get expensesByBox => _t('By cash box', 'حسب الخزنة');
  String get allExpenseCategories => _t('All categories', 'كل التصنيفات');
  String get allBoxes => _t('All cash boxes', 'كل الخزائن');
  String get cancelled => _t('Cancelled', 'ملغى');
  String get searchExpensesHint =>
      _t('Search expenses by number, payee or note…', 'ابحث في المصروفات بالرقم أو المستفيد أو الملاحظة…');
  String get ledgerAccount => _t('Account', 'الحساب');

  // --- Settlements (التسويات) ------------------------------------------------

  String get settlements => _t('Settlements', 'التسويات');
  String get settlement => _t('Settlement', 'تسوية');
  String get newSettlement => _t('New settlement', 'تسوية جديدة');
  String get editSettlement => _t('Edit settlement', 'تعديل تسوية');
  String get noSettlements => _t('No settlements yet', 'لا توجد تسويات بعد');
  String get settlementsHint => _t(
        'A settlement adjusts the balance of a customer, a supplier or an expense category without moving cash in or out of the treasury.',
        'التسوية تعدّل رصيد عميل أو مورد أو بند مصروف دون تحريك نقدية من أو إلى الخزينة.',
      );
  String get searchSettlementsHint =>
      _t('Search settlements by number or note…', 'ابحث في التسويات بالرقم أو الملاحظة…');
  String get settlementSaved => _t('Settlement recorded', 'تم تسجيل التسوية');
  String get settlementUpdated => _t('Settlement updated', 'تم تحديث التسوية');
  String get settlementCancelled => _t('Settlement cancelled', 'تم إلغاء التسوية');
  String get cancelSettlementQ => _t('Cancel this settlement?', 'إلغاء هذه التسوية؟');
  String get cancelSettlement => _t('Cancel settlement', 'إلغاء التسوية');
  String get cancelSettlementMessage => _t(
        'The settlement will be reversed and the account balance restored.',
        'سيتم عكس التسوية وإرجاع رصيد الحساب كما كان.',
      );
  String get settlementTarget => _t('Apply to', 'يُطبَّق على');
  String get settlementTargetCustomer => _t('Customer account', 'حساب عميل');
  String get settlementTargetSupplier => _t('Supplier account', 'حساب مورد');
  String get settlementTargetExpense => _t('Expense category', 'بند مصروفات');
  String get settlementDirection => _t('Effect', 'الأثر');
  String get settlementIncrease => _t('Increase balance', 'زيادة الرصيد');
  String get settlementDecrease => _t('Decrease balance', 'خصم من الرصيد');
  String get settlementAmount => _t('Settlement amount', 'مبلغ التسوية');
  String get settlementDate => _t('Settlement date', 'تاريخ التسوية');
  String get settlementAccount => _t('Selected account', 'الحساب المختار');
  String get allSettlementTargets => _t('All types', 'كل الأنواع');
  String get settlementNoCashEffect =>
      _t('No cash movement — this only adjusts the account balance.',
          'بدون حركة نقدية — هذا يعدّل رصيد الحساب فقط.');
  String get printSettlements => _t('Print statement', 'طباعة كشف');
  String get settlementsStatementHint => _t(
        'Lists the settlements of the chosen period with the net effect.',
        'يعرض تسويات الفترة المختارة مع صافي الأثر.',
      );
  String get selectExpenseCategory =>
      _t('Select an expense category', 'اختر بند مصروفات');
  String get accountOptional => _t('Ledger account (optional)', 'حساب الدفتر (اختياري)');
  String get expenseCount => _t('Expenses', 'عدد المصروفات');

  // ---------------------------------------------------------------------------
  // Opening balances (مديونية سابقة / قيد رأس المال)
  // ---------------------------------------------------------------------------
  String get openingBalances => _t('Opening balances', 'الأرصدة الافتتاحية');
  String get openingBalancesTitle => _t('Opening balances', 'الأرصدة الافتتاحية');
  String get openingBalancesHint => _t(
        'Enter what customers owe you, what you owe suppliers and the value of '
            'stock on hand before you started using the system. One capital '
            'entry is posted for everything.',
        'سجّل ما لك على العملاء وما عليك للموردين وقيمة المخزون قبل بدء '
            'استخدام النظام. يُرحَّل قيد رأس مال واحد لكل ذلك.',
      );
  String get newOpeningBalance => _t('New opening balance', 'أرصدة افتتاحية جديدة');
  String get noOpeningBalances =>
      _t('No opening balances recorded', 'لا توجد أرصدة افتتاحية مسجلة');
  String get asOfDate => _t('As of date', 'تاريخ الاستحقاق');
  String get openingCustomers => _t('Customer debts', 'مديونية العملاء');
  String get openingCustomersHint => _t(
        'Amount each customer already owes you.',
        'المبلغ المستحق على كل عميل.',
      );
  String get openingSuppliers => _t('Supplier debts', 'مديونية الموردين');
  String get openingSuppliersHint => _t(
        'Amount you already owe each supplier.',
        'المبلغ المستحق لكل مورد عليك.',
      );
  String get openingInventory => _t('Opening stock', 'المخزون الافتتاحي');
  String get openingInventoryHint => _t(
        'Quantity and cost of each product you already have on hand.',
        'الكمية والتكلفة لكل منتج موجود لديك بالفعل.',
      );
  String get addOpeningLine => _t('Add line', 'إضافة سطر');
  String get openingCapital => _t('Opening capital', 'رأس المال الافتتاحي');
  String get openingSaved => _t('Opening balances posted', 'تم ترحيل الأرصدة الافتتاحية');
  String get openingCancelled => _t('Opening balances cancelled', 'تم إلغاء الأرصدة الافتتاحية');
  String get cancelOpeningBalanceQ =>
      _t('Cancel these opening balances?', 'إلغاء هذه الأرصدة الافتتاحية؟');
  String get cancelOpeningBalanceHint => _t(
        'The capital entry will be reversed and partner balances and stock reset.',
        'سيتم عكس قيد رأس المال وإرجاع أرصدة العملاء والموردين والمخزون.',
      );
  String get emptyOpeningBalance => _t(
        'Add at least one line before saving.',
        'أضف بندًا واحدًا على الأقل قبل الحفظ.',
      );
  String openingBalanceSaved(String number) =>
      _t('$number posted.', 'تم ترحيل $number.');
  String get openingBalanceTotals => _t('Totals', 'الإجماليات');
  String get needProduct => _t('Pick a product', 'اختر منتجًا');
  String get needWarehouse => _t('Pick a warehouse', 'اختر مستودعًا');
  String get needPartner => _t('Pick a partner', 'اختر عميلًا أو موردًا');

  // ---------------------------------------------------------------------------
  // Sales shortages (نواقص أوامر البيع)
  // ---------------------------------------------------------------------------
  String get confirmDeleteTitle => _t('Delete?', 'حذف؟');
  String get confirmDeleteMessage =>
      _t('This action cannot be undone. Are you sure?', 'هذا الإجراء لا يمكن التراجع عنه. هل أنت متأكد؟');
  String confirmDeleteItem(String name) => _t(
        'Delete "$name"? This action cannot be undone.',
        'هل تريد حذف "$name"؟ هذا الإجراء لا يمكن التراجع عنه.',
      );
  String get shortages => _t('Sales shortages', 'نواقص أوامر البيع');
  String get shortagesHint => _t(
        'Products that open sales orders still need but are not on hand — buy '
            'these to keep the orders moving.',
        'أصناف تحتاجها أوامر بيع مفتوحة وليست موجودة بالمخزون — اشترِها '
            'لمتابعة تنفيذ الأوامر.',
      );
  String get noShortages =>
      _t('Nothing is short — every open order is covered by stock.', 'لا توجد نواقص — كل الأوامر المفتوحة مغطاة بالمخزون.');
  String get requiredQty => _t('Required', 'المطلوب');
  String get onHandQty => _t('On hand', 'المتوفر');
  String get shortageQty => _t('Shortage', 'الناقص');
  String get purchaseValue => _t('Purchase value', 'قيمة الشراء');
  String get waitingOrders => _t('Waiting orders', 'أوامر في الانتظار');
  String get shortageProducts => _t('Short products', 'أصناف ناقصة');
  String get salespersonCustomerDebt =>
      _t('Salesperson customer debt', 'مديونية عملاء المندوب');
  String get previousBalance => _t('Previous', 'حساب سابق');
  String get clearField => _t('Clear', 'مسح');
  String get searchHint => _t('Type to search…', 'اكتب للبحث…');
  String get searchCustomersHint => _t('Search customers…', 'ابحث عن العملاء…');
  String get noMatches => _t('No matching results', 'لا توجد نتائج مطابقة');
  String get typeNameToSearch =>
      _t('Type a name to search', 'اكتب اسمًا للبحث');
  String get availableQuantity => _t('Available', 'المتاح');  String get availableInStock => _t('Available in stock', 'المتاح في المخزون');
  String stockOnHandHint(int quantity, String unit) =>
      _t('Available: $quantity $unit', 'المتاح بالمخزون: $quantity $unit');
  String stockShortageHint(int quantity, String unit) => _t(
        'Only $quantity $unit available in stock',
        'المتاح بالمخزون $quantity $unit فقط',
      );
  String get previousBalanceLabel =>
      _t('Previous balance', 'المديونية السابقة');
  String get totalDueLabel => _t('Total due', 'إجمالي المديونية');
  String customerPreviousBalanceHint(String name) => _t(
        'What $name already owes before this invoice.',
        'المديونية السابقة على $name قبل هذه الفاتورة.',
      );
  String get noPreviousBalance =>
      _t('No previous balance', 'لا توجد مديونية سابقة');
  String get shortageWarningTitle =>
      _t('Some items are out of stock', 'بعض الأصناف غير موجودة');
  String get shortageWarningMessage => _t(
        'A few items are not on hand. You can deliver only what is available '
            'and keep the rest pending, or cancel and buy them first.',
        'بعض الأصناف غير متوفرة بالمخزون. يمكنك تسليم المتاح فقط وترك الباقي '
            'قيد الانتظار، أو الإلغاء وشراؤها أولاً.',
      );
  String get fulfilAvailableOnly =>
      _t('Deliver available only', 'تسليم المتاح فقط');
  String get fulfilOnlyAvailableDone => _t(
        'Delivered what was on hand; the rest stays pending.',
        'تم تسليم المتاح، والباقي قيد الانتظار.',
      );
  String get shortageDetails => _t('Missing items', 'الأصناف الناقصة');
  String get invoiceShortageTitle =>
      _t('Some items are not in stock', 'في أصناف غير موجودة بالمخزون');
  String get invoiceShortageMessage => _t(
        'The following items are short on stock. You can invoice only the '
            'available items and leave the rest out, or continue and invoice '
            'everything anyway.',
        'الأصناف التالية ناقصة بالمخزون. يمكنك تحويل المتاح فقط للفاتورة '
            'وترك الباقي، أو المتابعة وتحويل الكل للفاتورة.',
      );
  String get invoiceAvailableOnly =>
      _t('Invoice available only', 'فاتورة بالمتاح فقط');
  String get invoiceEverything => _t('Invoice everything', 'فاتورة بالكل');
  String get invoiceShortageNothingLeft => _t(
        'Nothing is available to invoice. Purchase the items first.',
        'لا يوجد أي صنف متاح للفاتورة. اشترِ الأصناف أولاً.',
      );
  String get orderFulfilmentTitle =>
      _t('Available vs. needed', 'المتاح والمطلوب');
  String get orderFulfilmentHint => _t(
        'What is on hand for each open sales order, and what still has to be purchased.',
        'المتاح فعلياً لكل أمر بيع مفتوح، والمطلوب شراؤه لإكماله.',
      );
  String get fullyAvailable => _t('Ready to deliver', 'جاهز للتسليم');
  String get needsPurchasing => _t('Needs purchasing', 'يحتاج شراء');
  String get availableQty => _t('Available', 'المتاح');
  String get noOpenOrders => _t(
        'No open sales orders right now.',
        'لا توجد أوامر بيع مفتوحة حالياً.',
      );

  // ---------------------------------------------------------------------------
  // Report hub (مركز التقارير) + extra reports
  // ---------------------------------------------------------------------------
  String get customerRequired => _t('Customer is required', 'العميل مطلوب');
  String get reportSearchHint =>
      _t('Search reports…', 'ابحث في التقارير…');
  String get noReportsMatch => _t(
        'No reports match your search.',
        'لا توجد تقارير مطابقة للبحث.',
      );
  String get allReports => _t('All reports', 'كل التقارير');
  String reportCountLabel(String count) =>
      _t('$count reports', '$count تقرير');
  String get salesReportsDesc => _t(
        'Invoices, profit, best sellers and order fulfilment.',
        'الفواتير والأرباح والأصناف الأكثر بيعاً وتغطية الأوامر.',
      );
  String get salespeopleReportsDesc => _t(
        'Each salesperson’s sales, profit, collections and customer debts.',
        'مبيعات وأرباح وتحصيلات ومديونيات عملاء كل مندوب.',
      );
  String get purchasesReportsDesc => _t(
        'Purchase orders, supplier balances and what to reorder.',
        'أوامر الشراء وأرصدة الموردين والأصناف المطلوب شراؤها.',
      );
  String get customersReportsDesc => _t(
        'Balances, statements and aging for every customer.',
        'الأرصدة وكشوف الحساب وأعمار الديون لكل عميل.',
      );
  String get suppliersReportsDesc => _t(
        'Balances, statements and aging for every supplier.',
        'الأرصدة وكشوف الحساب وأعمار الالتزامات لكل مورد.',
      );
  String get inventoryReportsDesc => _t(
        'Valuation, stock balance, movement and slow-moving items.',
        'التقييم وأرصدة المخزون والحركة والأصناف الراكدة.',
      );
  String get treasuryReportsDesc => _t(
        'Cash box balances, cash flow, expenses and payment methods.',
        'أرصدة الخزائن والحركة النقدية والمصروفات وطرق الدفع.',
      );
  String get accountingReportsDesc => _t(
        'Trial balance, income statement and balance sheet.',
        'ميزان المراجعة وقائمة الدخل والميزانية العمومية.',
      );
  String get salesByCustomer => _t('Sales by customer', 'المبيعات حسب العميل');
  String get salesByCustomerHint => _t(
        'Invoiced sales, collections and outstanding balance per customer.',
        'مبيعات الفواتير والتحصيلات والرصيد المتبقي لكل عميل.',
      );
  String get salesByCategory => _t('Sales by category', 'المبيعات حسب القسم');
  String get salesByCategoryHint => _t(
        'Quantity, revenue, cost and profit for each product category.',
        'الكمية والإيراد والتكلفة والربح لكل قسم أصناف.',
      );
  String get salesBySalesperson =>
      _t('Sales by salesperson', 'المبيعات حسب المندوب');
  String get salesBySalespersonHint => _t(
        'Invoice totals and profit credited to each salesperson.',
        'إجماليات الفواتير والأرباح المسجلة لكل مندوب.',
      );
  String get purchasesBySupplier =>
      _t('Purchases by supplier', 'المشتريات حسب المورد');
  String get purchasesBySupplierHint => _t(
        'Ordered, received and outstanding amounts for each supplier.',
        'المبالغ المطلوبة والمستلمة والمتبقية لكل مورد.',
      );
  String get returnsReport => _t('Returns report', 'تقرير المرتجعات');
  String get returnsReportHint => _t(
        'Every customer and supplier return with its value and status.',
        'كل مرتجع عميل أو مورد بقيمته وحالته.',
      );
  String get cashFlow => _t('Cash flow', 'الحركة النقدية');
  String get cashFlowHint => _t(
        'Opening balance, money in, money out and closing balance per cash box.',
        'الرصيد الافتتاحي والداخل والخارج والرصيد الختامي لكل خزنة.',
      );
  String get deadStock => _t('Dead / slow stock', 'المخزون الراكد');
  String get deadStockHint => _t(
        'Items with stock on hand that have not sold recently.',
        'أصناف لديها رصيد ولم تُبع منذ فترة.',
      );
  String get paymentsByMethod =>
      _t('Payments by method', 'المدفوعات حسب طريقة الدفع');
  String get paymentsByMethodHint => _t(
        'Cash, card, transfer and cheque totals in and out.',
        'إجماليات النقد والبطاقة والتحويل والشيك داخل وخارج.',
      );
  String get lastSale => _t('Last sale', 'آخر بيع');
  String get neverSold => _t('Never sold', 'لم يُبع');
  String get daysInStock => _t('Days in stock', 'أيام في المخزون');
  String get inTotal => _t('In', 'الداخل');
  String get outTotal => _t('Out', 'الخارج');
  String get netMovement => _t('Net', 'الصافي');
  String get daysAgo => _t('Days ago', 'منذ (يوم)');
  String get days => _t('days', 'يوم');
  String get numberLabel => _t('Number', 'الرقم');
  String get countLabel => _t('Count', 'العدد');
  String get couldNotLoadReport =>
      _t('Could not load the report.', 'تعذّر تحميل التقرير.');

  // ---------------------------------------------------------------------------
  // Inventory filters + sorting
  // ---------------------------------------------------------------------------
  String get filters => _t('Filters', 'تصفية');
  String get sortBy => _t('Sort by', 'ترتيب حسب');
  String get sortName => _t('Name (A–Z)', 'الاسم (أ–ي)');
  String get sortNameDesc => _t('Name (Z–A)', 'الاسم (ي–أ)');
  String get sortSku => _t('SKU', 'كود الصنف');
  String get sortQuantityDesc =>
      _t('Quantity (high–low)', 'الكمية (الأعلى أولاً)');
  String get sortQuantityAsc =>
      _t('Quantity (low–high)', 'الكمية (الأقل أولاً)');
  String get sortNewest => _t('Recently updated', 'الأحدث تحديثاً');
  String get stockStatus => _t('Stock status', 'حالة المخزون');
  String get inStock => _t('In stock', 'متوفر');
  String get outOfStock => _t('Out of stock', 'غير متوفر');
  String get clearFilters => _t('Clear filters', 'مسح التصفية');
}

/// [LocalizationsDelegate] for [AppStrings] supporting English and Arabic.
class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'ar';

  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture<AppStrings>(AppStrings(locale));

  @override
  bool shouldReload(AppStringsDelegate old) => false;
}

/// The const delegate instance wired into [MaterialApp].
const AppStringsDelegate appStringsDelegate = AppStringsDelegate();

/// Convenience accessor: `context.s.signIn`.
extension AppStringsX on BuildContext {
  AppStrings get s => AppStrings.of(this);
}
