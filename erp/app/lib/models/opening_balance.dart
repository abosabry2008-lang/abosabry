/// A posted opening-balance entry (مديونية سابقة / قيد رأس المال).
class OpeningBalance {
  const OpeningBalance({
    required this.id,
    required this.number,
    required this.asOfDate,
    required this.customerTotal,
    required this.supplierTotal,
    required this.inventoryTotal,
    this.note,
    this.userName,
    this.cancelledAt,
  });

  final String id;
  final String number;
  final DateTime asOfDate;
  final double customerTotal;
  final double supplierTotal;
  final double inventoryTotal;
  final String? note;
  final String? userName;
  final DateTime? cancelledAt;

  bool get isCancelled => cancelledAt != null;

  /// Equity (opening capital) = receivables + inventory − payables.
  double get capital => customerTotal + inventoryTotal - supplierTotal;

  factory OpeningBalance.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return OpeningBalance(
      id: json['id'] as String,
      number: json['number'] as String,
      asOfDate:
          DateTime.tryParse('${json['asOfDate']}')?.toLocal() ?? DateTime.now(),
      customerTotal: _toDouble(json['customerTotal']),
      supplierTotal: _toDouble(json['supplierTotal']),
      inventoryTotal: _toDouble(json['inventoryTotal']),
      note: json['note'] as String?,
      userName: user?['name'] as String?,
      cancelledAt: json['cancelledAt'] == null
          ? null
          : DateTime.tryParse('${json['cancelledAt']}')?.toLocal(),
    );
  }

  static double _toDouble(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}
