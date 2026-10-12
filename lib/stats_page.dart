import 'package:flutter/material.dart';

import 'verdict_repository.dart';
import 'widgets/section_card.dart';

/// Shows how many times each spouse did the dishes, and the history.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late final Future<List<VerdictRecord>> _records = verdictRepository
      .fetchAll();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📊 Dish record'), centerTitle: true),
      body: SafeArea(
        child: FutureBuilder<List<VerdictRecord>>(
          future: _records,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text('Failed to load the record. Please try again.'),
              );
            }
            final records = snapshot.data;
            if (records == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (records.isEmpty) {
              return const Center(
                child: Text('No verdicts have been recorded yet.'),
              );
            }
            return _buildStats(records);
          },
        ),
      ),
    );
  }

  Widget _buildStats(List<VerdictRecord> records) {
    final wifeCount = records.where((record) => record.loserIsWife).length;
    final husbandCount = records.length - wifeCount;
    // Names can change between verdicts, so show the latest ones.
    final latest = records.first;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: '🧽 Times on dish duty',
          child: Row(
            children: [
              Expanded(child: _buildCount('👩 ${latest.wifeName}', wifeCount)),
              Expanded(
                child: _buildCount('👨 ${latest.husbandName}', husbandCount),
              ),
            ],
          ),
        ),
        SectionCard(
          title: '📜 History',
          child: Column(
            children: [
              for (final record in records)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text(
                    record.loserIsWife ? '👩' : '👨',
                    style: const TextStyle(fontSize: 28),
                  ),
                  title: Text(
                    record.loserIsWife ? record.wifeName : record.husbandName,
                  ),
                  subtitle: Text(_formatDate(record.judgedAt)),
                  trailing: Text('🧽 ${record.dishDifficulty} / 10'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCount(String name, int count) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text('$count', style: textTheme.displayMedium),
      ],
    );
  }

  String _formatDate(DateTime date) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }
}
