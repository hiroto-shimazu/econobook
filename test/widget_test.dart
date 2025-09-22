import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('placeholder smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(true, isTrue);
  });
}
