import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dish_judge/main.dart';

void main() {
  testWidgets('初期状態では判定ボタンが押せない', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('⚖️ 忖度AI皿洗い裁判官'), findsOneWidget);
    expect(find.text('📷 シンクを撮影'), findsOneWidget);

    final judgeButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '⚖️ AI裁判官に判決を仰ぐ'),
    );
    expect(judgeButton.onPressed, isNull);
  });
}
