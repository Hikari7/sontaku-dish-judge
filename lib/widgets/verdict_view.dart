import 'package:flutter/material.dart';

import '../gemini_service.dart';
import 'section_card.dart';

/// Shows the AI judge's verdict.
class VerdictView extends StatelessWidget {
  const VerdictView({
    super.key,
    required this.verdict,
    required this.wifeName,
    required this.husbandName,
    required this.isRecorded,
    required this.onRecord,
    required this.onRetry,
  });

  final Verdict verdict;
  final String wifeName;
  final String husbandName;

  /// Whether this verdict was already added to the history.
  final bool isRecorded;

  /// Called when the user accepts the verdict and wants it recorded.
  final VoidCallback onRecord;

  /// Called when the user asks for another trial.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final loserName = verdict.loserIsWife ? wifeName : husbandName;
    final loserEmoji = verdict.loserIsWife ? '👩' : '👨';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: colors.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Column(
              children: [
                Text('⚖️ Verdict', style: textTheme.headlineLarge),
                const SizedBox(height: 16),
                Text('Today\'s dishes go to...', style: textTheme.titleMedium),
                const SizedBox(height: 12),
                Text(
                  '$loserEmoji $loserName',
                  textAlign: TextAlign.center,
                  style: textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
        SectionCard(
          title: '🧽 Sink contamination',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${verdict.dishDifficulty} / 10',
                textAlign: TextAlign.center,
                style: textTheme.displaySmall,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: verdict.dishDifficulty / 10,
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
            ],
          ),
        ),
        SectionCard(
          title: '📜 Reason for the verdict',
          child: Text(verdict.reason, style: textTheme.bodyLarge),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: isRecorded ? null : onRecord,
          child: Text(isRecorded ? '✅ Recorded' : '📝 Record this verdict'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onRetry,
          child: const Text('🔨 Hold another trial'),
        ),
      ],
    );
  }
}
