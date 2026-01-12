import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rockzero/main.dart';

void main() {
  testWidgets('App starts correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: RockZeroApp()));

    // Verify the app starts
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
