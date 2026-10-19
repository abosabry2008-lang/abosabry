import '../core/json_utils.dart';

/// A movement between two cash boxes (`POST /treasury/transfers`).
class CashTransfer {
  const CashTransfer({
    required this.id,
    required this.number,
    required this.fromBoxId,
    required this.toBoxId,
    this.fromBoxName = '',
    this.toBoxName = '',
    this.amount = 0,
    this.reference,
    this.note,
    this.transferDate,
    this.cancelledAt,
  });

  final String id;
  final String number;
  final String fromBoxId;
  final String toBoxId;
  final String fromBoxName;
  final String toBoxName;
  final double amount;
  final String? reference;
  final String? note;
  final DateTime? transferDate;
  final DateTime? cancelledAt;

  bool get cancelled => cancelledAt != null;

  factory CashTransfer.fromJson(Map<String, dynamic> json) {
    final fromBox = asMapOrNull(json['fromBox']);
    final toBox = asMapOrNull(json['toBox']);
    return CashTransfer(
      id: asString(json['id']),
      number: asString(json['number']),
      fromBoxId: asString(json['fromBoxId']),
      toBoxId: asString(json['toBoxId']),
      fromBoxName: fromBox == null ? '' : asString(fromBox['name']),
      toBoxName: toBox == null ? '' : asString(toBox['name']),
      amount: asDouble(json['amount']),
      reference: asStringOrNull(json['reference']),
      note: asStringOrNull(json['note']),
      transferDate: asDate(json['transferDate']),
      cancelledAt: asDate(json['cancelledAt']),
    );
  }
}
