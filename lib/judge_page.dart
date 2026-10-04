import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'gemini_service.dart';

/// 選択できる家事の一覧。
const List<String> chores = ['料理', '洗濯', '掃除', 'ゴミ出し', '買い物', 'その他'];

class JudgePage extends StatefulWidget {
  const JudgePage({super.key});

  @override
  State<JudgePage> createState() => _JudgePageState();
}

class _JudgePageState extends State<JudgePage> {
  final _wifeNameController = TextEditingController();
  final _husbandNameController = TextEditingController();

  // チェックされた家事。
  final Set<String> _wifeChores = {};
  final Set<String> _husbandChores = {};

  // 選択されたシンク画像。
  Uint8List? _imageBytes;
  String _imageMimeType = 'image/jpeg';

  bool _isLoading = false;
  Verdict? _verdict;
  String? _errorMessage;

  // 名前が未入力のときは「妻」「夫」と呼ぶ。
  String get _wifeName {
    final name = _wifeNameController.text.trim();
    return name.isEmpty ? '妻' : name;
  }

  String get _husbandName {
    final name = _husbandNameController.text.trim();
    return name.isEmpty ? '夫' : name;
  }

  // 画像があり、家事が1つ以上チェックされていれば判定できる。
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

  /// カメラかギャラリーかを選んでもらい、画像を読み込む。
  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('カメラで撮影'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('ギャラリーから選ぶ'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      // 送信サイズを抑えるため、縮小・圧縮して受け取る。
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
      if (file == null) return; // キャンセルされた

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
            ? 'カメラまたは写真へのアクセスが許可されていません。端末の設定で許可してください。'
            : '画像の選択に失敗しました。もう一度お試しください。';
      });
    } catch (_) {
      setState(() {
        _errorMessage = '画像の読み込みに失敗しました。もう一度お試しください。';
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

  /// Geminiに判決を依頼する。
  Future<void> _judge() async {
    if (!_canJudge) return; // 連打防止

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
        // 画面の並び順でそろえる。
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
      setState(() => _errorMessage = '予期しないエラーが発生しました。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 判決を閉じて入力画面に戻る。
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
      appBar: AppBar(title: const Text('⚖️ 忖度AI皿洗い裁判官'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: verdict == null ? _buildForm() : _buildVerdict(verdict),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 入力フォーム
  // ---------------------------------------------------------------------------

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: '👥 当事者',
          child: Row(
            children: [
              Expanded(child: _buildNameField(_wifeNameController, '👩 名前')),
              const SizedBox(width: 12),
              Expanded(child: _buildNameField(_husbandNameController, '👨 名前')),
            ],
          ),
        ),
        _SectionCard(title: '🧹 今日の家事', child: _buildChoreTable()),
        _SectionCard(
          title: '🍽️ 証拠写真（シンク）',
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
                child: Text(_imageBytes == null ? '📷 シンクを撮影' : '📷 撮り直す'),
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
                Text('AIが油汚れと貢献度を忖度中…'),
              ],
            ),
          )
        else
          FilledButton(
            onPressed: _canJudge ? _judge : null,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('⚖️ AI裁判官に判決を仰ぐ', style: TextStyle(fontSize: 18)),
            ),
          ),
        if (!_canJudge && !_isLoading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '家事を1つ以上チェックし、シンクの写真を用意してください',
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
      // 家事の表の見出しに名前を反映するため、入力のたびに再描画する。
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  /// 家事ごとに、妻・夫それぞれのチェックボックスを並べた表。
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
  // 判決
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
                Text('⚖️ 判決', style: textTheme.headlineLarge),
                const SizedBox(height: 16),
                Text('本日の皿洗い担当は……', style: textTheme.titleMedium),
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
          title: '🧽 シンク汚染度',
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
          title: '📜 判決理由',
          child: Text(verdict.reason, style: textTheme.bodyLarge),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _retry, child: const Text('🔨 もう一度裁判する')),
      ],
    );
  }
}

/// 見出し付きのカード。
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

/// エラーメッセージの表示。
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
