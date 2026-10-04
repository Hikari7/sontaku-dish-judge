# ⚖️ 忖度AI皿洗い裁判官 (dish_judge)

夫婦の「今日どっちが皿洗いする？」を、AI裁判官（Gemini）が
今日の家事とシンクの写真から判決するAndroid向けデモアプリです。

## セットアップ

1. [Google AI Studio](https://aistudio.google.com/apikey) でGemini APIキーを発行する
2. `env.example.json` をコピーして `env.json` を作り、キーを書く

   ```sh
   cp env.example.json env.json
   ```

   ```json
   { "GEMINI_API_KEY": "発行したキー" }
   ```

   `env.json` は `.gitignore` 済みなのでコミットされません。

3. Android端末を接続して実行する

   ```sh
   flutter pub get
   flutter run --dart-define-from-file=env.json
   ```

## ⚠️ APIキーについて

このアプリはバックエンドを持たず、アプリから直接Gemini APIを呼び出します。
APIキーはビルド時にアプリ本体（APK）へ埋め込まれるため、**APKを入手した人はキーを取り出せます**。

- 個人の端末で動かす実験・LTデモ専用です
- このままの構成でストア公開やAPKの配布をしないでください
- 公開する場合は、キーを持つバックエンドを経由させる必要があります

## 構成

| ファイル | 役割 |
| --- | --- |
| `lib/main.dart` | アプリの起動とテーマ |
| `lib/judge_page.dart` | 画面（入力フォーム・判決表示） |
| `lib/gemini_service.dart` | Gemini API呼び出しとレスポンスのパース |

使用モデルは `lib/gemini_service.dart` の `geminiModel` で変更できます。
