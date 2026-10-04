import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dish_judge/main.dart';

void main() {
  testWidgets('the judge button is disabled initially', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('⚖️ Sontaku AI Dish Judge'), findsOneWidget);
    expect(find.text('📷 Photograph the sink'), findsOneWidget);

    final judgeButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '⚖️ Ask the AI judge for a verdict'),
    );
    expect(judgeButton.onPressed, isNull);
  });
}
