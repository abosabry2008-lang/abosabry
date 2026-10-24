import '../core/json_utils.dart';

/// A single debit/credit line of a [JournalEntry].
class JournalLine {
  const JournalLine({
    required this.id,
    this.journalEntryId = '',
    required this.accountId,
    this.debit = 0,
    this.credit = 0,
    this.description,
    this.accountCode,
    this.accountName,
  });

  final String id;
  final String journalEntryId;
  final String accountId;
  final double debit;
  final double credit;
  final String? description;
  final String? accountCode;
  final String? accountName;

  factory JournalLine.fromJson(Map<String, dynamic> json) {
    final account = asMap(json['account']);
    return JournalLine(
      id: asString(json['id']),
      journalEntryId: asString(json['journalEntryId']),
      accountId:
          asStringOrNull(json['accountId']) ?? asString(account['id']),
      debit: asDouble(json['debit']),
      credit: asDouble(json['credit']),
      description: asStringOrNull(json['description']),
      accountCode: asStringOrNull(account['code']) ??
          asStringOrNull(json['accountCode']),
      accountName: asStringOrNull(account['name']) ??
          asStringOrNull(json['accountName']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'accountId': accountId,
        'debit': debit,
        'credit': credit,
        'description': description,
      };
}

/// A double-entry journal entry.
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.number,
    this.entryDate,
    this.memo,
    this.reference,
    this.sourceType,
    this.sourceId,
    this.lines = const <JournalLine>[],
  });

  final String id;
  final String number;
  final DateTime? entryDate;
  final String? memo;
  final String? reference;
  final String? sourceType;
  final String? sourceId;
  final List<JournalLine> lines;

  double get debitTotal =>
      lines.fold<double>(0, (sum, line) => sum + line.debit);

  double get creditTotal =>
      lines.fold<double>(0, (sum, line) => sum + line.credit);

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
        id: asString(json['id']),
        number: asString(json['number']),
        entryDate: asDate(json['entryDate']),
        memo: asStringOrNull(json['memo']),
        reference: asStringOrNull(json['reference']),
        sourceType: asStringOrNull(json['sourceType']),
        sourceId: asStringOrNull(json['sourceId']),
        lines: asMapList(json['lines']).map(JournalLine.fromJson).toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'number': number,
        'entryDate': entryDate?.toUtc().toIso8601String(),
        'memo': memo,
        'reference': reference,
        'lines': lines.map((line) => line.toJson()).toList(),
      };
}
