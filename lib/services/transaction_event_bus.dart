import 'package:flutter/foundation.dart';

/// Simple notifier to broadcast when transactions mutate wallet state.
class TransactionEventBus {
  TransactionEventBus._();

  static final TransactionEventBus instance = TransactionEventBus._();

  final ValueNotifier<int> _counter = ValueNotifier<int>(0);

  ValueListenable<int> get counter => _counter;

  void notify() {
    _counter.value++;
  }
}
