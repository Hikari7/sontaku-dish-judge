# ⚖️ Sontaku AI Dish Judge (dish_judge)

An Android demo app where an AI judge (Gemini) settles a couple's
"who does the dishes today?" from today's chores and a photo of the sink.

## Setup

1. Create a Gemini API key in [Google AI Studio](https://aistudio.google.com/apikey)
2. Copy `env.example.json` to `env.json` and put the key in it

   ```sh
   cp env.example.json env.json
   ```

   ```json
   { "GEMINI_API_KEY": "your key" }
   ```

   `env.json` is listed in `.gitignore`, so it is not committed.

3. Connect an Android device and run

   ```sh
   flutter pub get
   flutter run --dart-define-from-file=env.json
   ```

## ⚠️ About the API key

This app has no backend and calls the Gemini API directly from the app.
The API key is embedded in the app (APK) at build time, so **anyone who gets the APK can extract the key**.

- It is only meant for experiments and lightning-talk demos on your own device
- Do not publish it to a store or distribute the APK as it is
- To publish it, route the calls through a backend that holds the key

## Structure

| File | Role |
| --- | --- |
| `lib/main.dart` | App startup and theme |
| `lib/judge_page.dart` | The screen (form and verdict) |
| `lib/gemini_service.dart` | Gemini API call and response parsing |

Change the model with `geminiModel` in `lib/gemini_service.dart`.
