import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'gemini_service.dart';

/// The chores that can be selected.
const List<String> chores = [
  'Cooking',
  'Laundry',
  'Cleaning',
  'Trash',
  'Shopping',
  'Other',
];

class JudgePage extends StatefulWidget {
  const JudgePage({super.key});

  @override
  State<JudgePage> createState() => _JudgePageState();
}

class _JudgePageState extends State<JudgePage> {
  final _wifeNameController = TextEditingController();
  final _husbandNameController = TextEditingController();

  // The checked chores.
  final Set<String> _wifeChores = {};
  final Set<String> _husbandChores = {};

  // The selected sink image.
  Uint8List? _imageBytes;
  String _imageMimeType = 'image/jpeg';

  bool _isLoading = false;
  Verdict? _verdict;
  String? _errorMessage;

  // Fall back to "Wife" and "Husband" when no name is entered.
  String get _wifeName {
    final name = _wifeNameController.text.trim();
    return name.isEmpty ? 'Wife' : name;
  }

  String get _husbandName {
    final name = _husbandNameController.text.trim();
    return name.isEmpty ? 'Husband' : name;
  }

  // Judging is possible once there is an image and at least one checked chore.
  bool get _canJudge {
    final hasChores = _wifeChores.isNotEmpty || _husbandChores.isNotEmpty;
    return _imageBytes != null && hasChores && !_isLoading;
  }

  @override
  void dispose() {
    _wifeNameController.dispose();
    _husbandNameController.dispose();
    super.dispose();
  }

  /// Lets the user choose camera or gallery, then loads the image.
  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      // Shrink and compress the image to keep the upload small.
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
      if (file == null) return; // cancelled

      final bytes = await file.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _imageMimeType = _guessMimeType(file.name);
        _errorMessage = null;
      });
    } on PlatformException catch (e) {
      final isPermissionError = e.code.contains('access_denied');
      setState(() {
        _errorMessage = isPermissionError
            ? 'Access to the camera or photos is not allowed. Please allow it in the device settings.'
            : 'Failed to pick an image. Please try again.';
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Failed to load the image. Please try again.';
      });
    }
  }

  String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  /// Asks Gemini for a verdict.
  Future<void> _judge() async {
    if (!_canJudge) return; // ignore repeated taps

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final verdict = await requestVerdict(
        imageBytes: _imageBytes!,
        imageMimeType: _imageMimeType,
        wifeName: _wifeName,
        husbandName: _husbandName,
        // Keep the same order as on screen.
        wifeChores: chores.where(_wifeChores.contains).toList(),
        husbandChores: chores.where(_husbandChores.contains).toList(),
      );
      if (!mounted) return;
      setState(() => _verdict = verdict);
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'An unexpected error occurred. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Closes the verdict and goes back to the form.
  void _retry() {
    setState(() {
      _verdict = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final verdict = _verdict;

    return Scaffold(
      appBar: AppBar(
        title: const Text('⚖️ Sontaku AI Dish Judge'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: verdict == null ? _buildForm() : _buildVerdict(verdict),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Form
  // ---------------------------------------------------------------------------

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: '👥 The parties',
          child: Row(
            children: [
              Expanded(child: _buildNameField(_wifeNameController, '👩 Name')),
              const SizedBox(width: 12),
              Expanded(
                child: _buildNameField(_husbandNameController, '👨 Name'),
              ),
            ],
          ),
        ),
        _SectionCard(title: '🧹 Today\'s chores', child: _buildChoreTable()),
        _SectionCard(
          title: '🍽️ Evidence photo (sink)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_imageBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _imageBytes!,
                    height: 220,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton(
                onPressed: _isLoading ? null : _pickImage,
                child: Text(
                  _imageBytes == null ? '📷 Photograph the sink' : '📷 Retake',
                ),
              ),
            ],
          ),
        ),
        if (_errorMessage != null) _ErrorBox(message: _errorMessage!),
        const SizedBox(height: 8),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('The AI is weighing grease against contributions...'),
              ],
            ),
          )
        else
          FilledButton(
            onPressed: _canJudge ? _judge : null,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                '⚖️ Ask the AI judge for a verdict',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        if (!_canJudge && !_isLoading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Check at least one chore and add a photo of the sink',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildNameField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      enabled: !_isLoading,
      // Rebuild on every change so the chore table header shows the names.
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  /// A table with a checkbox for the wife and the husband on each chore.
  Widget _buildChoreTable() {
    const columnWidth = 80.0;

    Widget header(String text) {
      return SizedBox(
        width: columnWidth,
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
    }

    Widget checkbox(Set<String> selected, String chore) {
      return SizedBox(
        width: columnWidth,
        child: Checkbox(
          value: selected.contains(chore),
          onChanged: _isLoading
              ? null
              : (checked) {
                  setState(() {
                    if (checked == true) {
                      selected.add(chore);
                    } else {
                      selected.remove(chore);
                    }
                  });
                },
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            const Spacer(),
            header('👩 $_wifeName'),
            header('👨 $_husbandName'),
          ],
        ),
        for (final chore in chores)
          Row(
            children: [
              Expanded(child: Text(chore)),
              checkbox(_wifeChores, chore),
              checkbox(_husbandChores, chore),
            ],
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Verdict
  // ---------------------------------------------------------------------------

  Widget _buildVerdict(Verdict verdict) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final loserName = verdict.loserIsWife ? _wifeName : _husbandName;
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
        _SectionCard(
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
        _SectionCard(
          title: '📜 Reason for the verdict',
          child: Text(verdict.reason, style: textTheme.bodyLarge),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _retry,
          child: const Text('🔨 Hold another trial'),
        ),
      ],
    );
  }
}

/// A card with a heading.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Shows an error message.
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '⚠️ $message',
        style: TextStyle(color: colors.onErrorContainer),
      ),
    );
  }
}
