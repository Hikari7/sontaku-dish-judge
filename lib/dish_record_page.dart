import 'package:flutter/material.dart';

import 'verdict_repository.dart';
import 'widgets/section_card.dart';

/// Shows how many times each spouse did the dishes, and the history.
class DishRecordPage extends StatefulWidget {
  const DishRecordPage({super.key});

  @override
  State<DishRecordPage> createState() => _DishRecordPageState();
}

class _DishRecordPageState extends State<DishRecordPage> {
  /// Held in the state rather than a FutureBuilder, because a swiped-away
  /// record has to leave the list in the same frame it is dismissed.
  List<VerdictRecord>? _records;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final records = await verdictRepository.fetchAll();
      if (!mounted) return;
      setState(() => _records = records);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    final Widget body;
    if (_loadFailed) {
      body = const Center(
        child: Text('Failed to load the record. Please try again.'),
      );
    } else if (records == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (records.isEmpty) {
      body = const Center(child: Text('No verdicts have been recorded yet.'));
    } else {
      body = _buildRecord(records);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('📊 Dish record'), centerTitle: true),
      body: SafeArea(child: body),
    );
  }

  Widget _buildRecord(List<VerdictRecord> records) {
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Swipe a verdict left to delete it',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              for (final record in records) _buildHistoryItem(record),
            ],
          ),
        ),
      ],
    );
  }

  /// A history row that is deleted by swiping it to the left.
  Widget _buildHistoryItem(VerdictRecord record) {
    final colorScheme = Theme.of(context).colorScheme;
    // Dismissible slides the row without clipping it, so without this the
    // part pushed out to the left stays visible beside the delete background.
    return ClipRect(
      child: Dismissible(
        key: ValueKey(record.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          color: colorScheme.errorContainer,
          child: Icon(Icons.delete, color: colorScheme.onErrorContainer),
        ),
        confirmDismiss: (_) => _confirmAndDelete(record),
        onDismissed: (_) => setState(() => _records!.remove(record)),
        child: ListTile(
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
      ),
    );
  }

  /// Asks before deleting [record], then removes it from the database.
  Future<bool> _confirmAndDelete(VerdictRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this verdict?'),
        content: Text(
          '${_formatDate(record.judgedAt)}  '
          '${record.loserIsWife ? record.wifeName : record.husbandName}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    try {
      await verdictRepository.delete(record.id);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete the verdict.')),
        );
      }
      return false;
    }
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
