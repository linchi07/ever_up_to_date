import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: avoid_relative_lib_imports
import '../lib/main.dart';

void main() {
  testWidgets('Renders EverUpToDate demo UI', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('EverUpToDate Auto-Update Demo'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.textContaining('空闲 (Idle)'), findsOneWidget);
  });
}
