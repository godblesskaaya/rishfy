class DriverEarningsStats {
  const DriverEarningsStats({
    required this.availableTzs,
    required this.pendingPayoutTzs,
    required this.heldTzs,
    required this.paidOutTzs,
    required this.totalEarnedTzs,
    required this.tripCount,
  });

  final int availableTzs;
  final int pendingPayoutTzs;
  final int heldTzs;
  final int paidOutTzs;
  final int totalEarnedTzs;
  final int tripCount;

  factory DriverEarningsStats.fromJson(Map<String, dynamic> json) {
    final int available = _readInt(json, <String>[
      'available_tzs',
      'pending_balance_tzs',
    ]);
    final int pending = _readInt(json, <String>['pending_payout_tzs']);
    final int held = _readInt(json, <String>['held_tzs']);
    final int paidOut = _readInt(json, <String>[
      'paid_out_tzs',
      'total_settled_tzs',
    ]);
    final int totalEarned = _readInt(json, <String>[
      'total_earned_tzs',
      'total_earnings_tzs',
    ]);

    return DriverEarningsStats(
      availableTzs: available,
      pendingPayoutTzs: pending,
      heldTzs: held,
      paidOutTzs: paidOut,
      totalEarnedTzs:
          totalEarned == 0 ? available + pending + held + paidOut : totalEarned,
      tripCount: _readInt(json, <String>['trip_count']),
    );
  }
}

class DriverPayout {
  const DriverPayout({
    required this.payoutId,
    required this.amountTzs,
    required this.status,
    required this.payoutMethod,
    required this.payoutPhone,
    required this.requestedAt,
    this.providerReference,
    this.completedAt,
  });

  final String payoutId;
  final int amountTzs;
  final String status;
  final String payoutMethod;
  final String payoutPhone;
  final DateTime requestedAt;
  final String? providerReference;
  final DateTime? completedAt;

  bool get isPending => status == 'pending_review' || status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed' || status == 'cancelled';

  factory DriverPayout.fromJson(Map<String, dynamic> json) {
    return DriverPayout(
      payoutId: json['payoutId'] as String? ?? '',
      amountTzs: _readInt(json, <String>['amountTzs']),
      status: json['status'] as String? ?? 'pending_review',
      payoutMethod: json['payoutMethod'] as String? ?? '',
      payoutPhone: json['payoutPhone'] as String? ?? '',
      providerReference: json['providerReference'] as String?,
      requestedAt: DateTime.tryParse(json['requestedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
    );
  }
}

class DriverWalletSnapshot {
  const DriverWalletSnapshot({
    required this.stats,
    required this.payouts,
  });

  final DriverEarningsStats stats;
  final List<DriverPayout> payouts;

  DriverPayout? payoutById(String payoutId) {
    for (final DriverPayout payout in payouts) {
      if (payout.payoutId == payoutId) return payout;
    }
    return null;
  }
}

class DriverPayoutDetail {
  const DriverPayoutDetail({
    required this.payout,
    this.items = const <PayoutItem>[],
    this.holds = const <PayoutHold>[],
    this.ledgerJournals = const <PayoutLedgerJournal>[],
    this.reconciliationRecords = const <PayoutReconciliationRecord>[],
  });

  final DriverPayout payout;
  final List<PayoutItem> items;
  final List<PayoutHold> holds;
  final List<PayoutLedgerJournal> ledgerJournals;
  final List<PayoutReconciliationRecord> reconciliationRecords;

  factory DriverPayoutDetail.fromJson(Map<String, dynamic> json) {
    return DriverPayoutDetail(
      payout: DriverPayout.fromJson(
        _readMap(json['payout']),
      ),
      items: _readList(json['items'])
          .map((Map<String, dynamic> item) => PayoutItem.fromJson(item))
          .toList(),
      holds: _readList(json['holds'])
          .map((Map<String, dynamic> item) => PayoutHold.fromJson(item))
          .toList(),
      ledgerJournals: _readList(json['ledgerJournals'])
          .map((Map<String, dynamic> item) => PayoutLedgerJournal.fromJson(item))
          .toList(),
      reconciliationRecords: _readList(json['reconciliationRecords'])
          .map((Map<String, dynamic> item) =>
              PayoutReconciliationRecord.fromJson(item))
          .toList(),
    );
  }
}

class PayoutItem {
  const PayoutItem({
    required this.itemId,
    required this.amountTzs,
    this.bookingId,
    this.ledgerEntryId,
  });

  final String itemId;
  final int amountTzs;
  final String? bookingId;
  final String? ledgerEntryId;

  factory PayoutItem.fromJson(Map<String, dynamic> json) => PayoutItem(
        itemId: json['itemId'] as String? ?? '',
        amountTzs: _readInt(json, <String>['amountTzs']),
        bookingId: json['bookingId'] as String?,
        ledgerEntryId: json['ledgerEntryId'] as String?,
      );
}

class PayoutHold {
  const PayoutHold({
    required this.holdId,
    required this.amountTzs,
    required this.reason,
    required this.createdAt,
    this.bookingId,
    this.note,
    this.releasedAt,
  });

  final String holdId;
  final int amountTzs;
  final String reason;
  final String? bookingId;
  final String? note;
  final DateTime createdAt;
  final DateTime? releasedAt;

  bool get active => releasedAt == null;

  factory PayoutHold.fromJson(Map<String, dynamic> json) => PayoutHold(
        holdId: json['holdId'] as String? ?? '',
        amountTzs: _readInt(json, <String>['amountTzs']),
        reason: json['reason'] as String? ?? 'admin_review',
        bookingId: json['bookingId'] as String?,
        note: json['note'] as String?,
        createdAt: _readDate(json['createdAt']),
        releasedAt: _readNullableDate(json['releasedAt']),
      );
}

class PayoutLedgerJournal {
  const PayoutLedgerJournal({
    required this.journalId,
    required this.journalType,
    required this.createdAt,
    this.entries = const <PayoutLedgerEntry>[],
  });

  final String journalId;
  final String journalType;
  final DateTime createdAt;
  final List<PayoutLedgerEntry> entries;

  factory PayoutLedgerJournal.fromJson(Map<String, dynamic> json) =>
      PayoutLedgerJournal(
        journalId: json['journalId'] as String? ?? '',
        journalType: json['journalType'] as String? ?? '',
        createdAt: _readDate(json['createdAt']),
        entries: _readList(json['entries'])
            .map((Map<String, dynamic> item) => PayoutLedgerEntry.fromJson(item))
            .toList(),
      );
}

class PayoutLedgerEntry {
  const PayoutLedgerEntry({
    required this.entryId,
    required this.direction,
    required this.amountTzs,
  });

  final String entryId;
  final String direction;
  final int amountTzs;

  factory PayoutLedgerEntry.fromJson(Map<String, dynamic> json) =>
      PayoutLedgerEntry(
        entryId: json['entryId'] as String? ?? '',
        direction: json['direction'] as String? ?? '',
        amountTzs: _readInt(json, <String>['amountTzs']),
      );
}

class PayoutReconciliationRecord {
  const PayoutReconciliationRecord({
    required this.recordId,
    required this.provider,
    required this.providerReference,
    required this.matchStatus,
    required this.amountTzs,
  });

  final String recordId;
  final String provider;
  final String providerReference;
  final String matchStatus;
  final int amountTzs;

  factory PayoutReconciliationRecord.fromJson(Map<String, dynamic> json) =>
      PayoutReconciliationRecord(
        recordId: json['recordId'] as String? ?? '',
        provider: json['provider'] as String? ?? '',
        providerReference: json['providerReference'] as String? ?? '',
        matchStatus: json['matchStatus'] as String? ?? 'unmatched',
        amountTzs: _readInt(json, <String>['amountTzs']),
      );
}

int _readInt(Map<String, dynamic> data, List<String> keys) {
  for (final String key in keys) {
    final Object? value = data[key];
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
  }
  return 0;
}

Map<String, dynamic> _readMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _readList(Object? value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value.map(_readMap).toList();
}

DateTime _readDate(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _readNullableDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
