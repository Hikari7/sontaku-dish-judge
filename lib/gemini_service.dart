import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Gemini API key. Not written in the source; passed at run time with
/// --dart-define-from-file.
/// (See README.md for how to set it up.)
const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

/// The Gemini models to use (stable Flash models), best first.
/// When one is too busy (503), the next one is tried.
/// https://ai.google.dev/gemini-api/docs/models
const List<String> geminiModels = [
  'gemini-3.8-flash',
  'gemini-3.6-flash',
  'gemini-3.5-flash',
  'gemini-3.5-flash-lite',
];

/// The AI judge's verdict.
class Verdict {
  const Verdict({
    required this.loserIsWife,
    required this.dishDifficulty,
    required this.reason,
  });

  /// true if the wife does the dishes today, false if the husband does.
  final bool loserIsWife;

  /// Dishwashing difficulty (1-10).
  final int dishDifficulty;

  /// The reason for the verdict.
  final String reason;
}

/// An error whose message can be shown on screen as is.
class GeminiException implements Exception {
  const GeminiException(this.message);

  final String message;

  @override
  String toString() => message;
}

const String _systemInstruction = '''
You are the "Sontaku AI Dish Judge".

As a very fair and strict household judge, analyze the photo of the sink and how much each spouse contributed to today's chores, and decide who does the dishes today.
However, make your writing a little comical.

[Sink analysis]
Judge the following from the image and rate the "dishwashing difficulty" (dishDifficulty) as an integer from 1 to 10.
- The amount of dishes
- Large cookware such as frying pans and pots
- How much grease there is
- Whether it looks hard to wash
- How dirty the sink is overall

[Chore contribution]
Compare the chores each spouse did today.
Do not just count the chores; give some extra weight to demanding ones such as cooking.

[Verdict]
Always pick exactly one person to do the dishes today, and answer in verdict with "wife" or "husband".
In reason, write the reason for the verdict in 2 to 4 English sentences, using both names.
''';

/// Sends the sink image and today's chores to Gemini and returns the verdict.
/// Throws a [GeminiException] on failure.
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
      'The Gemini API key is not set.\n'
      'Create env.json as described in README.md and run again.',
    );
  }

  final userText =
      '''
Wife's name: $wifeName
$wifeName's chores today: ${_describeChores(wifeChores)}

Husband's name: $husbandName
$husbandName's chores today: ${_describeChores(husbandChores)}

The attached image is a photo of the sink right now. Please give your verdict.
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
    // Ask for JSON and fix its shape (schema).
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

  // Gemini answers 503 when a model is too busy. That happens often, so on a
  // 503 move on to the next model in the list.
  late http.Response response;
  for (final model in geminiModels) {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );
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
      throw const GeminiException(
        'The AI judge did not respond (timeout). Please try again.',
      );
    } catch (_) {
      throw const GeminiException(
        'Could not connect to Gemini. Please check your network connection.',
      );
    }

    if (response.statusCode != 503) break;
  }

  if (response.statusCode != 200) {
    throw GeminiException(_describeHttpError(response.statusCode));
  }

  return _parseVerdict(utf8.decode(response.bodyBytes));
}

String _describeChores(List<String> chores) {
  return chores.isEmpty ? 'none' : chores.join(', ');
}

String _describeHttpError(int statusCode) {
  switch (statusCode) {
    case 400:
    case 401:
    case 403:
      return 'The Gemini API rejected the request ($statusCode). Please check that your API key is correct.';
    case 429:
      return 'The Gemini API usage limit was reached (429). Please wait a moment and try again.';
    case 503:
      return 'The AI judge is very busy right now (503). Please wait a moment and try again.';
    default:
      return 'The Gemini API returned an error ($statusCode). Please wait a moment and try again.';
  }
}

/// Extracts the verdict from the Gemini response body.
/// Throws a [GeminiException] if the shape is unexpected (never crashes).
Verdict _parseVerdict(String responseBody) {
  const unexpected = GeminiException(
    'The AI judge sent an unexpected reply. Please try again.',
  );

  try {
    // Whole response: { "candidates": [ { "content": { "parts": [ { "text": "..." } ] } } ] }
    final body = jsonDecode(responseBody);
    final parts = body['candidates'][0]['content']['parts'] as List;
    final text = parts.map((part) => part['text'] ?? '').join();

    // text holds a JSON string in the shape we asked for.
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
    // JSON parse failures and missing or wrongly typed fields all end up here.
    throw unexpected;
  }
}
