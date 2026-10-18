import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'dish_record_page.dart';
import 'gemini_service.dart';
import 'verdict_repository.dart';
import 'widgets/section_card.dart';
import 'widgets/verdict_view.dart';

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

  // Whether the verdict on screen was already added to the history.
  bool _isRecorded = false;

  CoupleNames get _names => CoupleNames(
    wife: _wifeNameController.text.trim(),
    husband: _husbandNameController.text.trim(),
  );

  String get _wifeName => _names.wifeLabel;
  String get _husbandName => _names.husbandLabel;

  // Judging is possible once there is an image and at least one checked chore.
  bool get _canJudge {
    final hasChores = _wifeChores.isNotEmpty || _husbandChores.isNotEmpty;
    return _imageBytes != null && hasChores && !_isLoading;
  }

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  /// Fills in the names saved last time.
  Future<void> _loadNames() async {
    final CoupleNames names;
    try {
      names = await verdictRepository.fetchNames();
    } catch (_) {
      return; // the fields simply stay empty
    }
    if (!mounted) return;
    setState(() {
      // Keep anything the user typed while the names were loading.
      if (_wifeNameController.text.isEmpty) {
        _wifeNameController.text = names.wife;
      }
      if (_husbandNameController.text.isEmpty) {
        _husbandNameController.text = names.husband;
      }
    });
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
    // Remember the names for next time. Failing to save them should not
    // stop the verdict, so the error is ignored.
    verdictRepository.saveNames(_names).ignore();
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
      setState(() {
        _verdict = verdict;
        _isRecorded = false;
      });
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

  /// Adds the verdict on screen to the history.
  Future<void> _record() async {
    final verdict = _verdict;
    if (verdict == null || _isRecorded) return; // ignore repeated taps

    // Set before saving so a second tap cannot record it twice.
    setState(() => _isRecorded = true);
    try {
      await verdictRepository.save(verdict);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRecorded = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to record the verdict. Please try again.'),
        ),
      );
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
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Dish record',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DishRecordPage()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: verdict == null
              ? _buildForm()
              : VerdictView(
                  verdict: verdict,
                  wifeName: _wifeName,
                  husbandName: _husbandName,
                  isRecorded: _isRecorded,
                  onRecord: _record,
                  onRetry: _retry,
                ),
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
        SectionCard(
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
        SectionCard(title: '🧹 Today\'s chores', child: _buildChoreTable()),
        SectionCard(
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
