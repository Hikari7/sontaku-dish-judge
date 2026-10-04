import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Gemini APIキー。ソースには書かず、実行時に --dart-define-from-file で渡す。
/// （設定方法は README.md を参照）
const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

/// 使用するGeminiモデル（Flash系の安定版）。
/// https://ai.google.dev/gemini-api/docs/models
const String geminiModel = 'gemini-3.8-flash';

/// AI裁判官の判決。
class Verdict {
  const Verdict({
    required this.loserIsWife,
    required this.dishDifficulty,
    required this.reason,
  });

  /// true なら妻、false なら夫が今日の皿洗い担当。
  final bool loserIsWife;

  /// 皿洗い難易度（1〜10）。
  final int dishDifficulty;

  /// 判決理由。
  final String reason;
}

/// 画面にそのまま表示できるメッセージを持つエラー。
class GeminiException implements Exception {
  const GeminiException(this.message);

  final String message;

  @override
  String toString() => message;
}

const String _systemInstruction = '''
あなたは「忖度AI皿洗い裁判官」です。

非常に公平で厳格な家庭内裁判官として、シンクの写真と夫婦それぞれの今日の家事貢献度を分析し、本日の皿洗い担当者を決定してください。
ただし、文章は少しコミカルにしてください。

【シンク分析】
画像から以下を判断し、「皿洗い難易度」(dishDifficulty) を1〜10の整数で評価してください。
- 食器の量
- フライパンや鍋などの大型調理器具
- 油汚れの多さ
- 洗うのが大変そうか
- シンク全体の汚さ

【家事貢献度】
夫婦それぞれが今日行った家事を比較してください。
単純に家事の数だけではなく、料理など負担の大きい家事はある程度考慮してください。

【判決】
今日の皿洗い担当を必ず1人決定し、verdict に "wife"（妻）または "husband"（夫）で答えてください。
reason には判決理由を、2人の名前を使って日本語で2〜4文で書いてください。
''';

/// シンク画像と今日の家事をGeminiに送り、判決を受け取る。
/// 失敗した場合は [GeminiException] を投げる。
Future<Verdict> requestVerdict({
  required Uint8List imageBytes,
  required String imageMimeType,
  required String wifeName,
  required String husbandName,
  required List<String> wifeChores,
  required List<String> husbandChores,
}) async {
  if (geminiApiKey.isEmpty) {
    throw const GeminiException(
      'Gemini APIキーが設定されていません。\n'
      'README.md の手順で env.json を用意して起動してください。',
    );
  }

  final userText =
      '''
妻（wife）の名前: $wifeName
$wifeName の今日の家事: ${_describeChores(wifeChores)}

夫（husband）の名前: $husbandName
$husbandName の今日の家事: ${_describeChores(husbandChores)}

添付の画像は現在のシンクの写真です。判決をお願いします。
''';

  final requestBody = {
    'systemInstruction': {
      'parts': [
        {'text': _systemInstruction},
      ],
    },
    'contents': [
      {
        'role': 'user',
        'parts': [
          {
            'inlineData': {
              'mimeType': imageMimeType,
              'data': base64Encode(imageBytes),
            },
          },
          {'text': userText},
        ],
      },
    ],
    // JSONで返すように指定し、形（スキーマ）も決めておく。
    'generationConfig': {
      'responseMimeType': 'application/json',
      'responseSchema': {
        'type': 'OBJECT',
        'properties': {
          'dishDifficulty': {'type': 'INTEGER'},
          'verdict': {
            'type': 'STRING',
            'enum': ['wife', 'husband'],
          },
          'reason': {'type': 'STRING'},
        },
        'required': ['dishDifficulty', 'verdict', 'reason'],
      },
    },
  };

  final uri = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent',
  );

  final http.Response response;
  try {
    response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': geminiApiKey,
          },
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 60));
  } on TimeoutException {
    throw const GeminiException('AI裁判官の応答がありません（タイムアウト）。もう一度お試しください。');
  } catch (_) {
    throw const GeminiException('Geminiに接続できませんでした。ネットワーク接続を確認してください。');
  }

  if (response.statusCode != 200) {
    throw GeminiException(_describeHttpError(response.statusCode));
  }

  return _parseVerdict(utf8.decode(response.bodyBytes));
}

String _describeChores(List<String> chores) {
  return chores.isEmpty ? 'なし' : chores.join('、');
}

String _describeHttpError(int statusCode) {
  switch (statusCode) {
    case 400:
    case 401:
    case 403:
      return 'Gemini APIに拒否されました（$statusCode）。APIキーが正しいか確認してください。';
    case 429:
      return 'Gemini APIの利用上限に達しました（429）。少し待ってからお試しください。';
    default:
      return 'Gemini APIでエラーが発生しました（$statusCode）。少し待ってからお試しください。';
  }
}

/// Geminiのレスポンス本文から判決を取り出す。
/// 想定外の形だった場合は [GeminiException] を投げる（クラッシュさせない）。
Verdict _parseVerdict(String responseBody) {
  const unexpected = GeminiException('AI裁判官から想定外の返答が届きました。もう一度お試しください。');

  try {
    // レスポンス全体: { "candidates": [ { "content": { "parts": [ { "text": "..." } ] } } ] }
    final body = jsonDecode(responseBody);
    final parts = body['candidates'][0]['content']['parts'] as List;
    final text = parts.map((part) => part['text'] ?? '').join();

    // text の中身が、こちらで指定した形のJSON文字列になっている。
    final json = jsonDecode(text);
    final difficulty = json['dishDifficulty'];
    final verdict = json['verdict'];
    final reason = json['reason'];

    if (difficulty is! num || reason is! String) throw unexpected;
    if (verdict != 'wife' && verdict != 'husband') throw unexpected;

    return Verdict(
      loserIsWife: verdict == 'wife',
      dishDifficulty: difficulty.round().clamp(1, 10),
      reason: reason,
    );
  } on GeminiException {
    rethrow;
  } catch (_) {
    // JSONパース失敗や、フィールドが無い・型が違う場合はすべてここに来る。
    throw unexpected;
  }
}
