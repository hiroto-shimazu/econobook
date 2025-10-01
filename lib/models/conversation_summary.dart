class ConversationSummary {
  const ConversationSummary({
    required this.incoming,
    required this.outgoing,
    required this.currencyCode,
    required this.pendingRequestCount,
    required this.pendingTaskCount,
    this.periodLabel,
  });

  final num incoming;
  final num outgoing;
  final String currencyCode;
  final int pendingRequestCount;
  final int pendingTaskCount;
  final String? periodLabel;

  num get net => incoming - outgoing;

  ConversationSummary copyWith({
    num? incoming,
    num? outgoing,
    String? currencyCode,
    int? pendingRequestCount,
    int? pendingTaskCount,
    String? periodLabel,
  }) {
    return ConversationSummary(
      incoming: incoming ?? this.incoming,
      outgoing: outgoing ?? this.outgoing,
      currencyCode: currencyCode ?? this.currencyCode,
      pendingRequestCount: pendingRequestCount ?? this.pendingRequestCount,
      pendingTaskCount: pendingTaskCount ?? this.pendingTaskCount,
      periodLabel: periodLabel ?? this.periodLabel,
    );
  }
}
