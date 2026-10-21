/// Permission catalog for UI (permission matrix) grouped by screen/module.
class PermissionCatalog {
  PermissionCatalog._();

  static const Map<String, List<PermItem>> groups = <String, List<PermItem>>{
    'المستخدمين': <PermItem>[
      PermItem('users.read', 'عرض المستخدمين'),
      PermItem('users.write', 'إضافة/تعديل/حذف المستخدمين'),
    ],
    'المنتجات والفئات': <PermItem>[
      PermItem('products.read', 'عرض المنتجات'),
      PermItem('products.write', 'إضافة/تعديل المنتجات'),
      PermItem('categories.read', 'عرض الفئات'),
      PermItem('categories.write', 'إضافة/تعديل الفئات'),
    ],
    'المخزون والمستودعات': <PermItem>[
      PermItem('inventory.read', 'عرض المخزون'),
      PermItem('inventory.write', 'عمليات المخزون (استلام/صرف/تحويل/تسوية)'),
      PermItem('warehouses.read', 'عرض المستودعات'),
      PermItem('warehouses.write', 'إدارة المستودعات والمواقع'),
    ],
    'المشتريات': <PermItem>[
      PermItem('purchasing.read', 'عرض أوامر الشراء'),
      PermItem('purchasing.write', 'إنشاء/اعتماد/استلام أوامر الشراء'),
      PermItem('purchases.cancel', 'إلغاء أمر شراء'),
    ],
    'العملاء': <PermItem>[
      PermItem('customers.read', 'عرض العملاء'),
      PermItem('customers.write', 'إضافة/تعديل العملاء'),
    ],
    'المبيعات ونقطة البيع': <PermItem>[
      PermItem('sales.read', 'عرض أوامر البيع'),
      PermItem('sales.write', 'إنشاء/تأكيد أوامر البيع'),
      PermItem('sales.cancel', 'إلغاء أمر بيع'),
      PermItem('pos.use', 'استخدام نقطة البيع (POS)'),
    ],
    'المردودات': <PermItem>[
      PermItem('returns.edit', 'تعديل مرتجع'),
      PermItem('returns.cancel', 'إلغاء مرتجع'),
    ],
    'الفواتير': <PermItem>[
      PermItem('invoices.read', 'عرض الفواتير'),
      PermItem('invoices.write', 'إنشاء/إصدار الفواتير'),
      PermItem('invoices.edit', 'تعديل مسودة فاتورة'),
      PermItem('invoices.cancel', 'إلغاء فاتورة'),
    ],
    'المدفوعات والخزنة': <PermItem>[
      PermItem('payments.read', 'عرض المدفوعات'),
      PermItem('payments.write', 'إنشاء المدفوعات'),
      PermItem('treasury.read', 'عرض الخزائن/الحوالات/التحصيل'),
      PermItem('treasury.write', 'إدارة الخزائن/الحوالات/التحصيل'),
      PermItem('expenses.read', 'عرض المصروفات'),
      PermItem('expenses.write', 'إدارة المصروفات'),
    ],
    'الرصيد الافتتاحى': <PermItem>[
      PermItem('openingBalances.read', 'عرض الرصيد الافتتاحى'),
      PermItem('openingBalances.write', 'إنشاء/إلغاء الرصيد الافتتاحى'),
    ],
    'الحسابات والتقارير': <PermItem>[
      PermItem('accounting.read', 'عرض الحسابات والقيود'),
      PermItem('accounting.write', 'إدارة الحسابات والقيود'),
      PermItem('reports.read', 'عرض التقارير'),
    ],
    'الإعدادات والعملات': <PermItem>[
      PermItem('settings.read', 'عرض الإعدادات'),
      PermItem('settings.write', 'تعديل الإعدادات'),
      PermItem('currency.read', 'عرض العملات'),
      PermItem('currency.write', 'إدارة العملات'),
    ],
  };

  static List<String> allKeys() {
    final out = <String>[];
    for (final list in groups.values) {
      for (final p in list) {
        out.add(p.key);
      }
    }
    return out;
  }
}

class PermItem {
  const PermItem(this.key, this.label);
  final String key;
  final String label;
}
