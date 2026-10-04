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
      title: 'Sontaku AI Dish Judge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Brown colors inspired by courtroom wood.
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8D5524)),
        scaffoldBackgroundColor: const Color(0xFFFFF8EE),
      ),
      home: const JudgePage(),
    );
  }
}
