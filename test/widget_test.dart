import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jitter/main.dart';

void main() {
  testWidgets('Jitter smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const JitterApp());

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}