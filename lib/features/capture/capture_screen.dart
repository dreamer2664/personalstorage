import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:neural_brain/neural_brain.dart';

import '../../app/providers.dart';
import '../../core/design/glass.dart';
import '../../core/design/labels.dart';
import '../../core/design/ps_image.dart';
import '../../core/design/theme.dart';
import '../../core/design/toast.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../core/util/debouncer.dart';
import '../../core/util/time_format.dart';
import '../../services/capture_service.dart';
import '../../services/note_actions.dart';
import '../../services/settings.dart';
import '../library/note_card.dart';
import '../note/note_detail_screen.dart';
import 'insight_chips.dart';
import 'mic_button.dart';

/// The home screen: an always-ready composer. Opening the app (or returning to it) focuses the
/// text field immediately; saving clears it instantly so the next thought can follow.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({required this.active, required this.bottomInset, super.key});

  /// Whether this tab is the visible one (controls focus and keyboard).
  final bool active;

  /// Space reserved at the bottom for the floating tab bar.
  final double bottomInset;

  @override
  ConsumerState<CaptureScreen> createState() => CaptureScreenState();
}

class CaptureScreenState extends ConsumerState<CaptureScreen> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final Debouncer _debounce = Debouncer(const Duration(milliseconds: 110));

  List<String> _images = [];
  NoteAnalysis? _analysis;
  bool _acceptChecklist = false;
  String _source = 'typed';
  String _voiceBase = '';
  ToastData? _toast;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onTextChanged);
    if (widget.active) _focusSoon();
  }

  @override
  void didUpdateWidget(CaptureScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _focusSoon();
    if (!widget.active && oldWidget.active) _focus.unfocus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Resume-to-capture: coming back to the app lands in the composer.
    if (state == AppLifecycleState.resumed && widget.active) _focusSoon();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _focus.dispose();
    _debounce.dispose();
    _toastTimer?.cancel();
    super.dispose();
  }

  void _focusSoon() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });

  /// Called by the shell for deep links / shares.
  void focus() => _focusSoon();

  void prefill({String? text, List<String> images = const []}) {
    if (text != null && text.trim().isNotEmpty) {
      final existing = _controller.text.trim();
      _controller.text = existing.isEmpty ? text : '$existing\n$text';
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      _source = 'share';
    }
    if (images.isNotEmpty) setState(() => _images = [..._images, ...images]);
    _focusSoon();
  }

  Future<void> startVoice() async {
    if (!ref.read(voiceServiceProvider).isListening) await _toggleVoice();
  }

  void _onTextChanged() {
    _debounce.run(() {
      if (!mounted) return;
      final services = ref.read(appServicesProvider).value;
      final text = _controller.text;
      setState(() {
        if (services == null || (text.trim().isEmpty && _images.isEmpty)) {
          _analysis = null;
          _acceptChecklist = false;
        } else {
          _analysis = services.capture.preview(text, imageCount: _images.length);
          if (_analysis!.checklistSuggestion == null) _acceptChecklist = false;
        }
      });
    });
  }

  bool get _canSave => _controller.text.trim().isNotEmpty || _images.isNotEmpty;

  Future<void> _save({String? source}) async {
    final services = ref.read(appServicesProvider).value;
    if (services == null || !_canSave) return;
    final draft = CaptureDraft(
      text: _controller.text,
      imagePaths: List.of(_images),
      source: source ?? _source,
      acceptChecklistSuggestion: _acceptChecklist,
    );
    // Optimistic: clear at once so the next thought can be typed immediately.
    Haptics.success();
    _controller.clear();
    setState(() {
      _images = [];
      _analysis = null;
      _acceptChecklist = false;
      _source = 'typed';
    });
    _focusSoon();
    try {
      final r = await services.capture.capture(draft);
      if (r != null && mounted) _showSaved(services, r);
    } on Object catch (e) {
      // Never lose the user's words: put them back.
      if (!mounted) return;
      _controller.text = draft.text;
      setState(() => _images = draft.imagePaths);
      _flash(ToastData('Couldn\'t save', detail: '$e', icon: CupertinoIcons.exclamationmark_triangle_fill, color: context.ps.danger));
    }
  }

  void _showSaved(AppServices services, CaptureResult r) {
    final a = r.analysis;
    final now = DateTime.now();
    final due = a.actions.map((t) => t.due == null ? null : (t, t.due!)).whereType<(ExtractedAction, DateTime)>().firstOrNull;
    final where = categoryLabel(services.ontology, a.categoryId);
    final detail = due != null
        ? 'Reminder · ${TimeFormat.dueLabel(due.$2, now, hasTime: due.$1.hasDueTime)}'
        : a.tags.isNotEmpty
            ? a.tags.take(3).map((t) => '#${t.name}').join('  ')
            : null;
    _flash(
      ToastData(
        'Saved to $where',
        detail: detail,
        actionLabel: 'Undo',
        onAction: () async {
          await NoteActions(services).delete(r.noteId);
          if (mounted) setState(() => _toast = null);
        },
      ),
    );
  }

  void _flash(ToastData t) {
    _toastTimer?.cancel();
    setState(() => _toast = t);
    _toastTimer = Timer(const Duration(milliseconds: 3800), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _toggleVoice() async {
    final voice = ref.read(voiceServiceProvider);
    final settings = ref.read(settingsProvider);
    if (voice.isListening) {
      await voice.stop();
      return;
    }
    _voiceBase = _controller.text.trim().isEmpty ? '' : '${_controller.text.trimRight()} ';
    void put(String t) => _controller.value = TextEditingValue(
          text: _voiceBase + t,
          selection: TextSelection.collapsed(offset: (_voiceBase + t).length),
        );
    final ok = await voice.start(
      onPartial: put,
      onDone: (t) {
        put(t);
        _source = 'voice';
        if (settings.autoSaveVoice) {
          _save(source: 'voice');
        } else {
          _focusSoon();
        }
      },
      preferOnDevice: settings.preferOnDeviceSpeech,
    );
    if (!ok && mounted) {
      _flash(ToastData('Voice input unavailable', detail: 'Check microphone and speech permissions', icon: CupertinoIcons.mic_slash_fill, color: context.ps.warning));
    }
  }

  Future<void> _pickImages() async {
    final source = await showCupertinoModalPopup<ImageSource>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, ImageSource.camera), child: const Text('Take Photo')),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, ImageSource.gallery), child: const Text('Choose from Library')),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ),
    );
    if (source == null) return;
    try {
      final picker = ImagePicker();
      final paths = source == ImageSource.camera
          ? [(await picker.pickImage(source: source, maxWidth: 2048, imageQuality: 85))?.path]
          : (await picker.pickMultiImage(maxWidth: 2048, imageQuality: 85)).map((x) => x.path).toList();
      final picked = paths.whereType<String>().toList();
      if (picked.isEmpty || !mounted) return;
      setState(() => _images = [..._images, ...picked]);
      _onTextChanged();
    } on Object catch (e) {
      if (mounted) _flash(ToastData('Couldn\'t open photos', detail: '$e', icon: CupertinoIcons.photo, color: context.ps.warning));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    final services = ref.watch(appServicesProvider).value;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final voice = ref.watch(voiceServiceProvider);
    final now = DateTime.now();
    return PsScaffold(
      animatedBackground: widget.active,
      child: SafeArea(
        bottom: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: keyboard > 0 ? keyboard + 8 : widget.bottomInset),
          child: Stack(
            children: [
              Column(
                children: [
                  PsHeader(title: 'Capture', subtitle: TimeFormat.fullDate(now)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
                          const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
                        },
                        child: GlassPanel(
                          radius: 30,
                          strong: true,
                          child: Column(
                            children: [
                              Expanded(
                                child: Stack(
                                  children: [
                                    CupertinoTextField.borderless(
                                      controller: _controller,
                                      focusNode: _focus,
                                      expands: true,
                                      maxLines: null,
                                      minLines: null,
                                      keyboardType: TextInputType.multiline,
                                      textInputAction: TextInputAction.newline,
                                      textAlignVertical: TextAlignVertical.top,
                                      textCapitalization: TextCapitalization.sentences,
                                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                                      cursorColor: ps.accent,
                                      placeholder: 'Capture a thought…',
                                      placeholderStyle: PsText.body(ps.tertiaryLabel).copyWith(fontSize: 21),
                                      style: PsText.body(ps.label).copyWith(fontSize: 21, height: 1.36),
                                    ),
                                    if (voice.isListening)
                                      Positioned(top: 8, right: 14, child: _ListeningBadge(level: voice.level)),
                                  ],
                                ),
                              ),
                              if (_images.isNotEmpty) _ImageStrip(paths: _images, onRemove: (i) => setState(() => _images = [..._images]..removeAt(i))),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _analysis == null || services == null
                                      ? _Hint(ps: ps)
                                      : InsightChips(
                                          analysis: _analysis!,
                                          ontology: services.ontology,
                                          checklistAccepted: _acceptChecklist,
                                          onToggleChecklist: () => setState(() => _acceptChecklist = !_acceptChecklist),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ActionCircle(icon: CupertinoIcons.photo_on_rectangle, label: 'Attach photo', onTap: _pickImages),
                        MicButton(listening: voice.isListening, level: voice.level, onTap: _toggleVoice),
                        ActionCircle(icon: CupertinoIcons.arrow_up, label: 'Save note', filled: true, enabled: _canSave && services != null, onTap: _save),
                      ],
                    ),
                  ),
                  if (keyboard == 0) _RecentRow(bottomInset: 0, now: now),
                ],
              ),
              Positioned(top: 4, left: 24, right: 24, child: Center(child: GlassToast(data: _toast))),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.ps});

  final PsPalette ps;

  @override
  Widget build(BuildContext context) => Text(
        'Try "remind me to call mom tomorrow at 5pm"',
        style: PsText.footnote(ps.tertiaryLabel),
      );
}

class _ListeningBadge extends StatelessWidget {
  const _ListeningBadge({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ShapeDecoration(shape: squircle(14), color: ps.danger.withValues(alpha: 0.14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 4; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 110),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: 5 + 13 * (level * (0.55 + 0.15 * ((i * 7) % 4))).clamp(0.0, 1.0),
              decoration: BoxDecoration(color: ps.danger, borderRadius: BorderRadius.circular(2)),
            ),
          const SizedBox(width: 8),
          Text('Listening', style: PsText.caption(ps.danger)),
        ],
      ),
    );
  }
}

class _ImageStrip extends StatelessWidget {
  const _ImageStrip({required this.paths, required this.onRemove});

  final List<String> paths;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: paths.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => Stack(
          clipBehavior: Clip.none,
          children: [
            ClipPath(
              clipper: ShapeBorderClipper(shape: squircle(14)),
              child: SizedBox(width: 64, height: 64, child: PsImage(paths[i], cacheWidth: 200)),
            ),
            Positioned(
              top: -5,
              right: -5,
              child: GestureDetector(
                onTap: () => onRemove(i),
                child: const DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0xCC000000)),
                  child: Padding(padding: EdgeInsets.all(4), child: Icon(CupertinoIcons.xmark, size: 10, color: Color(0xFFFFFFFF))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Last few captures, shown under the composer while the keyboard is down - instant visual
/// confirmation that things were saved, without leaving the capture screen.
class _RecentRow extends ConsumerWidget {
  const _RecentRow({required this.bottomInset, required this.now});

  final double bottomInset;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentSummariesProvider).value ?? const [];
    if (recent.isEmpty) return const SizedBox(height: 4);
    // A plain horizontal scroll view (not a ListView) so the strip is exactly as tall as its
    // tallest card - no fixed height to overflow with long titles or wrapped chips.
    final cardWidth = MediaQuery.sizeOf(context).width * 0.74;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < recent.length.clamp(0, 4); i++)
            Padding(
              padding: EdgeInsets.only(right: i == recent.length.clamp(0, 4) - 1 ? 0 : 10),
              child: SizedBox(
                width: cardWidth,
                child: FadeSlideIn(
                  index: i,
                  child: NoteCard(
                    note: recent[i],
                    now: now,
                    compact: true,
                    onTap: () => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => NoteDetailScreen(noteId: recent[i].id))),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
