import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design/glass.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets.dart';
import '../../services/sample_data.dart';
import '../../services/settings.dart';

/// Preferences, brain status, optional cloud embeddings and data management.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _baseUrl = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _dim = TextEditingController();
  final TextEditingController _key = TextEditingController();
  String? _message;
  bool _keyLoaded = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _baseUrl.text = s.cloudBaseUrl;
    _model.text = s.cloudModel;
    _dim.text = '${s.cloudDim}';
    ref.read(secretsProvider).read().then((k) {
      if (mounted) {
        _key.text = k ?? '';
        setState(() => _keyLoaded = true);
      }
    });
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _dim.dispose();
    _key.dispose();
    super.dispose();
  }

  void _say(String m) => setState(() => _message = m);

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final services = ref.watch(appServicesProvider).value;
    final count = ref.watch(noteCountProvider).value ?? 0;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0x00000000),
      child: PsScaffold(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(children: [GlassIconButton(icon: CupertinoIcons.chevron_left, semanticLabel: 'Back', onPressed: () => Navigator.of(context).maybePop())]),
              ),
              const PsHeader(title: 'Settings'),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 40 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 4),
                        child: GlassPanel(
                          radius: 16,
                          padding: const EdgeInsets.all(12),
                          tint: ps.accentSoft,
                          child: Row(children: [
                            Icon(CupertinoIcons.info_circle_fill, color: ps.accent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_message!, style: PsText.footnote(ps.label))),
                          ]),
                        ),
                      ),
                    const PsSectionHeader('Appearance'),
                    _Group(children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: CupertinoSlidingSegmentedControl<ThemeModeSetting>(
                          groupValue: s.themeMode,
                          children: const {
                            ThemeModeSetting.system: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('System')),
                            ThemeModeSetting.light: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Light')),
                            ThemeModeSetting.dark: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Dark')),
                          },
                          onValueChanged: (v) => n.update(s.copyWith(themeMode: v)),
                        ),
                      ),
                    ]),
                    const PsSectionHeader('Capture'),
                    _Group(children: [
                      _SwitchRow(label: 'Save voice notes automatically', detail: 'Dictation ends → note is saved and categorised', value: s.autoSaveVoice, onChanged: (v) => n.update(s.copyWith(autoSaveVoice: v))),
                      _SwitchRow(label: 'Prefer on-device speech', detail: 'Offline and private when your phone supports it; otherwise the OS may use its cloud recogniser', value: s.preferOnDeviceSpeech, onChanged: (v) => n.update(s.copyWith(preferOnDeviceSpeech: v))),
                      _SwitchRow(label: 'Fetch link previews', detail: 'Contacts the linked website to read its title', value: s.fetchLinkPreviews, onChanged: (v) => n.update(s.copyWith(fetchLinkPreviews: v))),
                      _SwitchRow(label: 'Haptic feedback', value: s.haptics, onChanged: (v) => n.update(s.copyWith(haptics: v))),
                      _NavRow(
                        label: 'All-day reminders at',
                        value: '${s.reminderHour.toString().padLeft(2, '0')}:00',
                        onTap: () async {
                          final h = await showCupertinoModalPopup<int>(
                            context: context,
                            builder: (ctx) => CupertinoActionSheet(
                              title: const Text('Remind me at'),
                              actions: [for (final h in const [7, 8, 9, 10, 12, 18, 20]) CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, h), child: Text('${h.toString().padLeft(2, '0')}:00'))],
                              cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            ),
                          );
                          if (h != null) {
                            await n.update(s.copyWith(reminderHour: h));
                            final sv = ref.read(appServicesProvider).value;
                            if (sv != null) await sv.reminders.syncAll(await sv.repo.openTasksWithReminders(), hour: h);
                          }
                        },
                        last: true,
                      ),
                    ]),
                    const PsSectionHeader('Neural brain'),
                    _Group(children: [
                      _InfoRow(label: 'Engine', value: services == null ? 'Loading…' : services.brain.modelId),
                      _InfoRow(label: 'Notes indexed', value: services == null ? '–' : '${services.brain.index.length} of $count'),
                      _InfoRow(label: 'Concepts', value: services == null ? '–' : '${services.ontology.size} · v${services.brain.ontologyVersion}'),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text('Connection strength', style: PsText.body(ps.label))),
                            Text(s.edgeThreshold.toStringAsFixed(2), style: PsText.subhead(ps.secondaryLabel)),
                          ]),
                          CupertinoSlider(value: s.edgeThreshold.clamp(0.26, 0.75), min: 0.26, max: 0.75, onChanged: (v) => n.update(s.copyWith(edgeThreshold: double.parse(v.toStringAsFixed(2))))),
                          Text('Higher = fewer, stronger links in the graph.', style: PsText.caption(ps.tertiaryLabel)),
                        ]),
                      ),
                      _NavRow(
                        label: 'Re-index all notes',
                        value: '',
                        last: true,
                        onTap: () async {
                          final sv = services;
                          if (sv == null) return;
                          await sv.db.customStatement('DELETE FROM embeddings');
                          sv.brain.index.clear();
                          await sv.enrichment.reindexStale();
                          _say('Re-indexed ${await sv.repo.noteCount()} notes.');
                        },
                      ),
                    ]),
                    const PsSectionHeader('Cloud embeddings (optional)'),
                    _Group(children: [
                      _SwitchRow(
                        label: 'Use an OpenAI-compatible provider',
                        detail: 'Off by default. When on, note text is sent to the provider you configure to compute search vectors. Categorisation, tasks and the graph layout always stay on-device.',
                        value: s.cloudEmbeddings,
                        onChanged: (v) => n.update(s.copyWith(cloudEmbeddings: v)),
                      ),
                      if (s.cloudEmbeddings) ...[
                        _Field(controller: _baseUrl, label: 'Base URL', placeholder: 'https://api.openai.com/v1'),
                        _Field(controller: _model, label: 'Model', placeholder: 'text-embedding-3-small'),
                        _Field(controller: _dim, label: 'Dimensions', placeholder: '512', keyboard: TextInputType.number),
                        _Field(controller: _key, label: 'API key', placeholder: _keyLoaded ? 'sk-…' : 'Loading…', obscure: true),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: PsButton(
                            label: 'Apply & re-index',
                            expand: true,
                            onPressed: () async {
                              await n.update(s.copyWith(
                                cloudBaseUrl: _baseUrl.text.trim(),
                                cloudModel: _model.text.trim(),
                                cloudDim: int.tryParse(_dim.text.trim()) ?? s.cloudDim,
                              ));
                              await ref.read(secretsProvider).write(_key.text.trim());
                              ref.invalidate(appServicesProvider);
                              _say('Provider applied. Notes are being re-embedded in the background.');
                            },
                          ),
                        ),
                      ],
                    ]),
                    const PsSectionHeader('Data'),
                    _Group(children: [
                      _NavRow(
                        label: 'Copy all notes as JSON',
                        value: '',
                        onTap: () async {
                          final sv = services;
                          if (sv == null) return;
                          final data = await sv.repo.exportAll();
                          await Clipboard.setData(ClipboardData(text: const JsonEncoderIndented().convert(data)));
                          _say('JSON copied to the clipboard.');
                        },
                      ),
                      _NavRow(
                        label: 'Copy all notes as Markdown',
                        value: '',
                        onTap: () async {
                          final sv = services;
                          if (sv == null) return;
                          await Clipboard.setData(ClipboardData(text: await sv.repo.exportMarkdown()));
                          _say('Markdown copied — paste it into Obsidian or any editor.');
                        },
                      ),
                      _NavRow(
                        label: 'Add sample notes',
                        value: '',
                        onTap: () async {
                          final sv = services;
                          if (sv == null) return;
                          final added = await SampleData.insert(sv.capture);
                          _say('Added $added sample notes.');
                        },
                      ),
                      _NavRow(
                        label: 'Delete all data',
                        value: '',
                        destructive: true,
                        last: true,
                        onTap: () async {
                          final ok = await showCupertinoDialog<bool>(
                            context: context,
                            builder: (ctx) => CupertinoAlertDialog(
                              title: const Text('Delete everything?'),
                              content: const Text('All notes, tasks and photos references will be removed from this device. This cannot be undone.'),
                              actions: [
                                CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                              ],
                            ),
                          );
                          final sv = services;
                          if (ok == true && sv != null) {
                            await sv.repo.deleteEverything();
                            sv.brain.index.clear();
                            _say('All data deleted.');
                          }
                        },
                      ),
                    ]),
                    const PsSectionHeader('About'),
                    _Group(children: [
                      const _InfoRow(label: 'Privacy', value: 'Local-first'),
                      const _InfoRow(label: 'Model', value: 'potion-base-8M (MIT)'),
                      const _InfoRow(label: 'Typeface', value: 'Inter (OFL 1.1)', last: true),
                    ]),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                      child: Text(
                        'Everything you capture stays on this device. Categorisation, tasks, search and the graph run on-device with no network access.',
                        style: PsText.caption(ps.tertiaryLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class JsonEncoderIndented {
  const JsonEncoderIndented();

  String convert(Object? o) => _enc(o, 0);

  String _enc(Object? o, int depth) {
    final pad = '  ' * depth;
    if (o is Map) {
      if (o.isEmpty) return '{}';
      return '{\n${o.entries.map((e) => '$pad  "${e.key}": ${_enc(e.value, depth + 1)}').join(',\n')}\n$pad}';
    }
    if (o is List) {
      if (o.isEmpty) return '[]';
      return '[\n${o.map((e) => '$pad  ${_enc(e, depth + 1)}').join(',\n')}\n$pad]';
    }
    if (o is String) return '"${o.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';
    return '$o';
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GlassPanel(blur: false, radius: 20, child: Column(children: children));
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.label, required this.value, required this.onChanged, this.detail});

  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: PsText.body(ps.label)),
                if (detail != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(detail!, style: PsText.caption(ps.secondaryLabel))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.label, required this.value, required this.onTap, this.last = false, this.destructive = false});

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool last;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return PressableScale(
      scale: 0.99,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          children: [
            Expanded(child: Text(label, style: PsText.body(destructive ? ps.danger : ps.label))),
            if (value.isNotEmpty) Text(value, style: PsText.body(ps.secondaryLabel)),
            const SizedBox(width: 6),
            if (!destructive) Icon(CupertinoIcons.chevron_right, size: 14, color: ps.tertiaryLabel),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        Expanded(child: Text(label, style: PsText.body(ps.label))),
        Flexible(child: Text(value, textAlign: TextAlign.end, style: PsText.body(ps.secondaryLabel))),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.label, required this.placeholder, this.obscure = false, this.keyboard});

  final TextEditingController controller;
  final String label;
  final String placeholder;
  final bool obscure;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) {
    final ps = context.ps;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(children: [
        SizedBox(width: 92, child: Text(label, style: PsText.subhead(ps.secondaryLabel))),
        Expanded(
          child: CupertinoTextField.borderless(
            controller: controller,
            placeholder: placeholder,
            obscureText: obscure,
            keyboardType: keyboard,
            autocorrect: false,
            enableSuggestions: false,
            padding: const EdgeInsets.symmetric(vertical: 10),
            style: PsText.body(ps.label).copyWith(fontSize: 15),
            placeholderStyle: PsText.body(ps.tertiaryLabel).copyWith(fontSize: 15),
          ),
        ),
      ]),
    );
  }
}
