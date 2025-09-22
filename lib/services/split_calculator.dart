import 'dart:math';

import '../models/split_rounding_mode.dart';

class SplitCalculation {
  const SplitCalculation({required this.amounts, required this.remainder});

  final List<double> amounts;
  final double remainder;

  double get billedTotal => amounts.fold<double>(
      0, (previousValue, element) => previousValue + element);
}

SplitCalculation calculateSplitAllocations({
  required num totalAmount,
  required int participantCount,
  required int precision,
  required SplitRoundingMode roundingMode,
}) {
  if (participantCount <= 0) {
    throw ArgumentError('participantCount must be greater than zero');
  }
  final factor = pow(10, precision).round();
  final totalUnits = (totalAmount * factor).round();

  final List<int> allocationsUnits;
  int remainderUnits;

  switch (roundingMode) {
    case SplitRoundingMode.even:
      final base = totalUnits ~/ participantCount;
      final remainder = totalUnits % participantCount;
      allocationsUnits = List.generate(
        participantCount,
        (index) => base + (index < remainder ? 1 : 0),
      );
      remainderUnits = 0;
      break;
    case SplitRoundingMode.floor:
      final base = totalUnits ~/ participantCount;
      allocationsUnits = List<int>.filled(participantCount, base);
      remainderUnits = totalUnits - base * participantCount;
      break;
  }

  final amounts = [
    for (final units in allocationsUnits) units / factor,
  ];

  return SplitCalculation(
    amounts: amounts,
    remainder: remainderUnits / factor,
  );
}
