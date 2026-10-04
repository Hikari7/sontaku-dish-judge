import 'package:flutter/material.dart';

import 'judge_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '忖度AI皿洗い裁判官',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // 法廷の木目をイメージした茶色ベースの配色。
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8D5524)),
        scaffoldBackgroundColor: const Color(0xFFFFF8EE),
      ),
      home: const JudgePage(),
    );
  }
}
