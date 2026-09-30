import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:neural_brain/neural_brain.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../core/design/category_style.dart';
import '../../core/design/collage.dart';
import '../../core/design/glass.dart';
import '../../core/design/labels.dart';
import '../../core/design/ps_image.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../core/util/debouncer.dart';
import '../../core/util/time_format.dart';
import '../../domain/models.dart';
import '../../services/note_actions.dart';
import '../../services/search_service.dart';
import '../library/note_card.dart';

/// Read/edit view of one note: text, checklist, photos, links, tasks, tags and related notes.
/// Edits are saved as you type; text edits trigger a background re-analysis.
class NoteDetailScreen extends ConsumerStatefulWidget {
  const NoteDetailScreen({required this.noteId, super.key});

  final String noteId;

  @override
  ConsumerState<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends ConsumerState<NoteDetailScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final TextEditingController _newItem = TextEditingController();
  final FocusNode _itemFocus = FocusNode();
  final Debouncer _saveBody = Debouncer(const Duration(milliseconds: 700));
  final Debouncer _saveTitle = Debouncer(const Duration(milliseconds: 500));
  bool _hydrated = false;
  bool _bodyDirty = false;
  Future<List<SearchResult>>? _related;

  /// Captured while mounted: `ref` must not be used from `dispose()`.
  AppServices? _cachedServices;
  AppServices? get _services => _cachedServices ?? ref.read(appServicesProvider).value;

  @override
  void dispose() {
    _flush();
    _title.dispose();
    _body.dispose();
    _newItem.dispose();
    _itemFocus.dispose();
    _saveBody.dispose();
    _saveTitle.dispose();
    super.dispose();
  }

  /// Persists pending edits immediately (leaving the screen must never lose text).
  void _flush() {
    final s = _cachedServices;
    if (s == null || !_hydrated) return;
    if (_bodyDirty) {
      _bodyDirty = false;
      unawaited(s.repo.setBody(widget.noteId, _body.text).then((_) => s.enrichment.reanalyze(widget.noteId, convertToChecklist: false)));
    }
  }

  void _hydrate(NoteDetail d) {
    if (_hydrated) return;
    _hydrated = true;
    _title.text = d.title;
    _body.text = d.body;
    _related = _services?.search.related(d.id);
  }

  void _onBodyChanged(String _) {
    _bodyDirty = true;
    _saveBody.run(() {
      final s = _services;
      if (s == null || !mounted) return;
      _bodyDirty = false;
      s.repo.setBody(widget.noteId, _body.text).then((_) => s.enrichment.reanalyze(widget.noteId, convertToChecklist: false));
    });
  }

  void _onTitleChanged(String v) => _saveTitle.run(() => _services?.repo.setTitle(widget.noteId, v.trim(), lock: true));

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    _cachedServices = ref.watch(appServicesProvider).value;
    final detail = ref.watch(noteDetailProvider(widget.noteId));
    return CupertinoPageScaffold(
      backgroundColor: const Color(0x00000000),
      child: PsScaffold(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _TopBar(noteId: widget.noteId, detail: detail.value),
              Expanded(
                child: detail.when(
                  loading: () => const Center(child: CupertinoActivityIndicator()),
                  error: (e, _) => Center(child: Text('$e', style: PsText.body(ps.danger))),
                  data: (d) {
                    if (d == null) {
                      return const PsEmptyState(icon: CupertinoIcons.trash, title: 'Note deleted', message: 'This note is no longer available.');
                    }
                    _hydrate(d);
                    return _content(d);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(NoteDetail d) {
    final ps = context.ps;
    final services = _services;
    final now = DateTime.now();
    final cat = categoryStyle(d.categoryId);
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 40 + MediaQuery.paddingOf(context).bottom),
      children: [
        // Category + priority + meta
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PsChip(
              icon: cat.icon,
              label: categoryLabel(services?.ontology ?? Ontology.standard, d.categoryId) + (d.categoryLocked ? '' : ' · auto'),
              color: cat.color,
              onTap: () => _pickCategory(d),
            ),
            PsChip(
              icon: CupertinoIcons.flag_fill,
              label: const ['No priority', 'Low', 'Medium', 'High'][d.priority.clamp(0, 3)],
              color: d.priority >= 3 ? ps.danger : (d.priority == 2 ? ps.warning : ps.secondaryLabel),
              onTap: () => _pickPriority(d),
            ),
            Text('Edited ${TimeFormat.ago(d.updatedAt, now)}', style: PsText.caption(ps.tertiaryLabel)),
          ],
        ),
        const SizedBox(height: 10),
        CupertinoTextField.borderless(
          controller: _title,
          onChanged: _onTitleChanged,
          maxLines: null,
          padding: EdgeInsets.zero,
          placeholder: 'Title',
          placeholderStyle: PsText.largeTitle(ps.tertiaryLabel).copyWith(fontSize: 28),
          style: PsText.largeTitle(ps.label).copyWith(fontSize: 28),
          cursorColor: ps.accent,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 10),
        if (d.kind != NoteKind.checklist)
          GlassPanel(
            blur: false,
            radius: 20,
            child: CupertinoTextField.borderless(
              controller: _body,
              onChanged: _onBodyChanged,
              minLines: 3,
              maxLines: null,
              padding: const EdgeInsets.all(16),
              placeholder: 'Write something…',
              placeholderStyle: PsText.body(ps.tertiaryLabel),
              style: PsText.body(ps.label),
              cursorColor: ps.accent,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
        if (d.kind == NoteKind.checklist) _checklist(d),
        if (d.images.isNotEmpty) ...[
          const PsSectionHeader('Photos', padding: EdgeInsets.fromLTRB(4, 22, 4, 8)),
          PhotoCollage(
            paths: [for (final i in d.images) i.uri],
            height: d.images.length == 1 ? 260 : 300,
            onTap: (i) => Navigator.of(context).push(CupertinoPageRoute<void>(fullscreenDialog: true, builder: (_) => _PhotoViewer(images: d.images, initial: i))),
          ),
        ],
        for (final l in d.links) ...[
          const SizedBox(height: 12),
          _LinkCard(link: l, onRemove: () => NoteActions(services!).removeAttachment(l.id)),
        ],
        _tasks(d),
        _tags(d),
        _related == null
            ? const SizedBox.shrink()
            : FutureBuilder<List<SearchResult>>(
                future: _related,
                builder: (context, snap) {
                  final list = snap.data ?? const [];
                  if (list.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const PsSectionHeader('Related', padding: EdgeInsets.fromLTRB(4, 24, 4, 8)),
                      for (var i = 0; i < list.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: FadeSlideIn(
                            index: i,
                            child: NoteCard(
                              note: list[i].note,
                              now: now,
                              reasons: list[i].reasons,
                              onTap: () => Navigator.of(context).pushReplacement(CupertinoPageRoute<void>(builder: (_) => NoteDetailScreen(noteId: list[i].note.id))),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: PsButton(
                label: 'Show in graph',
                icon: CupertinoIcons.graph_circle,
                style: PsButtonStyle.tinted,
                onPressed: () {
                  ref.read(graphFocusProvider.notifier).focus(d.id);
                  ref.read(selectedTabProvider.notifier).select(2);
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
              ),
            ),
            const SizedBox(width: 10),
            PsButton(label: 'Photo', icon: CupertinoIcons.camera, style: PsButtonStyle.tinted, color: ps.secondaryLabel, onPressed: () => _addPhoto(d)),
          ],
        ),
        const SizedBox(height: 14),
        Center(child: Text('Created ${DateFormat.yMMMd().add_jm().format(d.createdAt)} · ${d.source}', style: PsText.caption(ps.tertiaryLabel))),
      ],
    );
  }

  // ── checklist ────────────────────────────────────────────────────────────
  Widget _checklist(NoteDetail d) {
    final ps = context.ps;
    final repo = _services!.repo;
    final done = d.checklist.where((c) => c.checked).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PsSectionHeader('Checklist · $done/${d.checklist.length}', padding: const EdgeInsets.fromLTRB(4, 10, 4, 8)),
        GlassPanel(
          blur: false,
          radius: 20,
          child: Column(
            children: [
              for (var i = 0; i < d.checklist.length; i++)
                Dismissible(
                  key: ValueKey(d.checklist[i].id),
                  direction: DismissDirection.endToStart,
                  background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: ps.danger, child: const Icon(CupertinoIcons.trash, color: Color(0xFFFFFFFF))),
                  onDismissed: (_) => repo.removeChecklistItem(d.id, d.checklist[i].id),
                  child: _CheckRow(
                    label: d.checklist[i].label,
                    checked: d.checklist[i].checked,
                    last: false,
                    onToggle: () {
                      Haptics.select();
                      repo.setChecklistChecked(d.checklist[i].id, !d.checklist[i].checked);
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.plus_circle_fill, size: 22, color: ps.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoTextField.borderless(
                        controller: _newItem,
                        focusNode: _itemFocus,
                        placeholder: 'Add item',
                        placeholderStyle: PsText.body(ps.tertiaryLabel),
                        style: PsText.body(ps.label),
                        textInputAction: TextInputAction.done,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        onSubmitted: (v) async {
                          final t = v.trim();
                          if (t.isEmpty) return;
                          _newItem.clear();
                          await repo.addChecklistItem(d.id, t);
                          _itemFocus.requestFocus();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── tasks ────────────────────────────────────────────────────────────────
  Widget _tasks(NoteDetail d) {
    final ps = context.ps;
    final actions = NoteActions(_services!);
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PsSectionHeader('Tasks', padding: const EdgeInsets.fromLTRB(4, 24, 4, 8), trailing: GestureDetector(
          onTap: () => _addTask(d),
          child: Icon(CupertinoIcons.plus_circle_fill, size: 22, color: ps.accent),
        )),
        if (d.tasks.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('No tasks found in this note. Try "call Anna tomorrow at 5pm".', style: PsText.footnote(ps.tertiaryLabel)))
        else
          GlassPanel(
            blur: false,
            radius: 20,
            child: Column(
              children: [
                for (final t in d.tasks)
                  Dismissible(
                    key: ValueKey('task-${t.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: ps.danger, child: const Icon(CupertinoIcons.trash, color: Color(0xFFFFFFFF))),
                    onDismissed: (_) => actions.deleteTask(t.id),
                    child: _CheckRow(
                      label: t.title,
                      checked: t.done,
                      last: false,
                      trailing: t.dueAt == null
                          ? PsChip(dense: true, icon: CupertinoIcons.calendar_badge_plus, label: 'Add date', color: ps.secondaryLabel, onTap: () => _pickDue(t))
                          : PsChip(
                              dense: true,
                              icon: t.isOverdue(now) ? CupertinoIcons.exclamationmark_circle_fill : CupertinoIcons.bell_fill,
                              label: TimeFormat.dueLabel(t.dueAt!, now, hasTime: t.hasTime),
                              color: t.isOverdue(now) ? ps.danger : ps.accent,
                              onTap: () => _pickDue(t),
                            ),
                      onToggle: () {
                        Haptics.select();
                        actions.setTaskDone(t.id, !t.done);
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _addTask(NoteDetail d) async {
    final c = TextEditingController();
    final title = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('New task'),
        content: Padding(padding: const EdgeInsets.only(top: 10), child: CupertinoTextField(controller: c, autofocus: true, placeholder: 'e.g. Send the invoice')),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (title != null && title.isNotEmpty) await _services!.repo.addTask(d.id, title);
  }

  Future<void> _pickDue(TaskInfo t) async {
    var picked = t.dueAt ?? DateTime.now().add(const Duration(hours: 2));
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => Container(
        height: 330,
        padding: const EdgeInsets.only(top: 8),
        color: CupertinoTheme.of(ctx).scaffoldBackgroundColor == const Color(0x00000000) ? context.ps.backgroundTint : CupertinoTheme.of(ctx).scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  CupertinoButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Done')),
                ],
              ),
              Expanded(child: CupertinoDatePicker(initialDateTime: picked, onDateTimeChanged: (v) => picked = v)),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) await NoteActions(_services!).reschedule(t, picked);
  }

  // ── tags ─────────────────────────────────────────────────────────────────
  Widget _tags(NoteDetail d) {
    final ps = context.ps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PsSectionHeader('Tags', padding: EdgeInsets.fromLTRB(4, 24, 4, 8)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in d.tags)
              PsChip(
                label: '#${t.name}',
                color: t.isUser ? ps.accent : ps.secondaryLabel,
                filled: false,
                onTap: () => _tagMenu(d, t),
              ),
            PsChip(icon: CupertinoIcons.plus, label: 'Add tag', color: ps.accent, onTap: () => _addTag(d)),
          ],
        ),
        if (d.tags.any((t) => !t.isUser))
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 2),
            child: Row(children: [
              Icon(CupertinoIcons.sparkles, size: 12, color: ps.tertiaryLabel),
              const SizedBox(width: 5),
              Text('Grey tags were added by the on-device brain', style: PsText.caption(ps.tertiaryLabel)),
            ]),
          ),
      ],
    );
  }

  Future<void> _addTag(NoteDetail d) async {
    final c = TextEditingController();
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Add tag'),
        content: Padding(padding: const EdgeInsets.only(top: 10), child: CupertinoTextField(controller: c, autofocus: true, placeholder: 'e.g. lisbon', prefix: const Padding(padding: EdgeInsets.only(left: 8), child: Text('#')))),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Add')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await _services!.repo.addUserTag(d.id, name);
      await _services!.enrichment.reanalyze(d.id, convertToChecklist: false);
    }
  }

  Future<void> _tagMenu(NoteDetail d, TagInfo t) async {
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('#${t.name}'),
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'show'), child: const Text('Show notes with this tag')),
          CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, 'remove'), child: const Text('Remove from this note')),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ),
    );
    if (choice == 'remove') await _services!.repo.removeTag(d.id, t.name);
    if (choice == 'show' && mounted) {
      ref.read(libraryFilterProvider.notifier).set(LibraryFilter(tag: t.name));
      ref.read(selectedTabProvider.notifier).select(1);
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  // ── pickers ──────────────────────────────────────────────────────────────
  Future<void> _pickCategory(NoteDetail d) async {
    final services = _services!;
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Category'),
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, '_auto'), child: const Text('Automatic')),
          for (final id in allCategoryIds)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, id),
              child: Text(categoryLabel(services.ontology, id)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ),
    );
    if (choice == null) return;
    await services.repo.setCategory(d.id, choice == '_auto' ? null : choice);
    if (choice == '_auto') await services.enrichment.reanalyze(d.id, convertToChecklist: false);
  }

  Future<void> _pickPriority(NoteDetail d) async {
    final repo = _services!.repo;
    final choice = await showCupertinoModalPopup<int>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Priority'),
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, -1), child: const Text('Automatic')),
          for (var i = 0; i < 4; i++)
            CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, i), child: Text(const ['None', 'Low', 'Medium', 'High'][i])),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ),
    );
    if (choice == null) return;
    if (choice == -1) {
      await repo.setPriority(d.id, null);
      await _services!.enrichment.reanalyze(d.id, convertToChecklist: false);
    } else {
      await repo.setPriority(d.id, choice);
    }
  }

  Future<void> _addPhoto(NoteDetail d) async {
    try {
      final files = await ImagePicker().pickMultiImage(maxWidth: 2048, imageQuality: 85);
      if (files.isEmpty) return;
      final s = _services!;
      final saved = [for (final f in files) await s.media.persistImage(f.path)];
      await s.repo.addImages(d.id, saved);
    } on Object catch (e) {
      if (mounted) await showCupertinoDialog<void>(context: context, builder: (ctx) => CupertinoAlertDialog(title: const Text('Couldn\'t add photo'), content: Text('$e'), actions: [CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]));
    }
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.noteId, required this.detail});

  final String noteId;
  final NoteDetail? detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.read(appServicesProvider).value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          GlassIconButton(icon: CupertinoIcons.chevron_left, semanticLabel: 'Back', onPressed: () => Navigator.of(context).maybePop()),
          const Spacer(),
          if (detail != null) ...[
            GlassIconButton(
              icon: detail!.pinned ? CupertinoIcons.pin_fill : CupertinoIcons.pin,
              semanticLabel: detail!.pinned ? 'Unpin' : 'Pin',
              color: detail!.pinned ? context.ps.warning : null,
              onPressed: () => services?.repo.setPinned(noteId, !detail!.pinned),
            ),
            const SizedBox(width: 8),
            GlassIconButton(
              icon: CupertinoIcons.ellipsis,
              semanticLabel: 'More',
              onPressed: () async {
                final choice = await showCupertinoModalPopup<String>(
                  context: context,
                  builder: (ctx) => CupertinoActionSheet(
                    actions: [
                      CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'copy'), child: const Text('Copy text')),
                      CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Delete note')),
                    ],
                    cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  ),
                );
                if (choice == 'copy') {
                  final d = detail!;
                  final text = [d.title, d.body, for (final c in d.checklist) '- [${c.checked ? 'x' : ' '}] ${c.label}'].where((s) => s.isNotEmpty).join('\n');
                  await Clipboard.setData(ClipboardData(text: text));
                }
                if (choice == 'delete' && services != null) {
                  await NoteActions(services).delete(noteId);
                  if (context.mounted) Navigator.of(context).maybePop();
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.checked, required this.onToggle, required this.last, this.trailing});

  final String label;
  final bool checked;
  final VoidCallback onToggle;
  final bool last;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return PressableScale(
      scale: 0.99,
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            AnimatedContainer(
              duration: PsMotion.base,
              curve: PsMotion.spring,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked ? ps.accent : const Color(0x00000000),
                border: Border.all(color: checked ? ps.accent : ps.tertiaryLabel, width: 1.6),
              ),
              child: AnimatedOpacity(
                duration: PsMotion.fast,
                opacity: checked ? 1 : 0,
                child: const Icon(CupertinoIcons.checkmark_alt, size: 15, color: Color(0xFFFFFFFF)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: PsMotion.base,
                style: PsText.body(checked ? ps.tertiaryLabel : ps.label).copyWith(decoration: checked ? TextDecoration.lineThrough : TextDecoration.none),
                child: Text(label),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.link, required this.onRemove});

  final AttachmentInfo link;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return GlassPanel(
      blur: false,
      radius: 20,
      onTap: () => launchUrl(Uri.parse(link.uri), mode: LaunchMode.externalApplication),
      onLongPress: onRemove,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: ShapeDecoration(shape: squircle(12), color: ps.accentSoft),
            child: Icon(CupertinoIcons.link, color: ps.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(link.title ?? link.host ?? link.uri, maxLines: 2, overflow: TextOverflow.ellipsis, style: PsText.headline(ps.label)),
                if (link.description != null) Text(link.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: PsText.footnote(ps.secondaryLabel)),
                Text(link.host ?? '', style: PsText.caption(ps.accent)),
              ],
            ),
          ),
          Icon(CupertinoIcons.arrow_up_right, size: 16, color: ps.tertiaryLabel),
        ],
      ),
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.images, required this.initial});

  final List<AttachmentInfo> images;
  final int initial;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _page = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF000000),
      child: Stack(
        children: [
          PageView.builder(
            controller: _pc,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => InteractiveViewer(maxScale: 5, child: Center(child: PsImage(widget.images[i].uri, fit: BoxFit.contain))),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  GlassIconButton(icon: CupertinoIcons.xmark, semanticLabel: 'Close', onPressed: () => Navigator.of(context).pop()),
                  const Spacer(),
                  Text('${_page + 1} / ${widget.images.length}', style: PsText.subhead(const Color(0xFFFFFFFF))),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
