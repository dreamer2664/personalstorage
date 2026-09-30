import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/design/widgets.dart';

/// User-tunable behaviour. Persisted in `SharedPreferences`; API keys live in secure storage
/// (see `SecretsStore`), never here.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeModeSetting.system,
    this.haptics = true,
    this.autoSaveVoice = true,
    this.preferOnDeviceSpeech = false,
    this.fetchLinkPreviews = true,
    this.edgeThreshold = 0.33,
    this.showTagHubs = false,
    this.reminderHour = 9,
    this.cloudEmbeddings = false,
    this.cloudBaseUrl = 'https://api.openai.com/v1',
    this.cloudModel = 'text-embedding-3-small',
    this.cloudDim = 512,
  });

  final ThemeModeSetting themeMode;
  final bool haptics;

  /// Save a voice note as soon as dictation ends (true) or leave the text in the composer.
  final bool autoSaveVoice;

  /// Ask the OS to use an on-device recogniser (offline, more private) when available.
  final bool preferOnDeviceSpeech;
  final bool fetchLinkPreviews;

  /// Minimum relatedness for an AI-drawn edge (graph "connection strength").
  final double edgeThreshold;
  final bool showTagHubs;

  /// Hour at which all-day task reminders fire.
  final int reminderHour;
  final bool cloudEmbeddings;
  final String cloudBaseUrl;
  final String cloudModel;
  final int cloudDim;

  AppSettings copyWith({
    ThemeModeSetting? themeMode,
    bool? haptics,
    bool? autoSaveVoice,
    bool? preferOnDeviceSpeech,
    bool? fetchLinkPreviews,
    double? edgeThreshold,
    bool? showTagHubs,
    int? reminderHour,
    bool? cloudEmbeddings,
    String? cloudBaseUrl,
    String? cloudModel,
    int? cloudDim,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    haptics: haptics ?? this.haptics,
    autoSaveVoice: autoSaveVoice ?? this.autoSaveVoice,
    preferOnDeviceSpeech: preferOnDeviceSpeech ?? this.preferOnDeviceSpeech,
    fetchLinkPreviews: fetchLinkPreviews ?? this.fetchLinkPreviews,
    edgeThreshold: edgeThreshold ?? this.edgeThreshold,
    showTagHubs: showTagHubs ?? this.showTagHubs,
    reminderHour: reminderHour ?? this.reminderHour,
    cloudEmbeddings: cloudEmbeddings ?? this.cloudEmbeddings,
    cloudBaseUrl: cloudBaseUrl ?? this.cloudBaseUrl,
    cloudModel: cloudModel ?? this.cloudModel,
    cloudDim: cloudDim ?? this.cloudDim,
  );
}

enum ThemeModeSetting { system, light, dark }

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('Override in main()'));

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  late SharedPreferences _prefs;

  @override
  AppSettings build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    const d = AppSettings();
    final s = AppSettings(
      themeMode: ThemeModeSetting.values.firstWhere(
        (m) => m.name == _prefs.getString('theme'),
        orElse: () => d.themeMode,
      ),
      haptics: _prefs.getBool('haptics') ?? d.haptics,
      autoSaveVoice: _prefs.getBool('autoSaveVoice') ?? d.autoSaveVoice,
      preferOnDeviceSpeech: _prefs.getBool('onDeviceSpeech') ?? d.preferOnDeviceSpeech,
      fetchLinkPreviews: _prefs.getBool('linkPreviews') ?? d.fetchLinkPreviews,
      edgeThreshold: _prefs.getDouble('edgeThreshold') ?? d.edgeThreshold,
      showTagHubs: _prefs.getBool('tagHubs') ?? d.showTagHubs,
      reminderHour: _prefs.getInt('reminderHour') ?? d.reminderHour,
      cloudEmbeddings: _prefs.getBool('cloudEmbeddings') ?? d.cloudEmbeddings,
      cloudBaseUrl: _prefs.getString('cloudBaseUrl') ?? d.cloudBaseUrl,
      cloudModel: _prefs.getString('cloudModel') ?? d.cloudModel,
      cloudDim: _prefs.getInt('cloudDim') ?? d.cloudDim,
    );
    Haptics.enabled = s.haptics;
    return s;
  }

  Future<void> update(AppSettings next) async {
    state = next;
    Haptics.enabled = next.haptics;
    await Future.wait([
      _prefs.setString('theme', next.themeMode.name),
      _prefs.setBool('haptics', next.haptics),
      _prefs.setBool('autoSaveVoice', next.autoSaveVoice),
      _prefs.setBool('onDeviceSpeech', next.preferOnDeviceSpeech),
      _prefs.setBool('linkPreviews', next.fetchLinkPreviews),
      _prefs.setDouble('edgeThreshold', next.edgeThreshold),
      _prefs.setBool('tagHubs', next.showTagHubs),
      _prefs.setInt('reminderHour', next.reminderHour),
      _prefs.setBool('cloudEmbeddings', next.cloudEmbeddings),
      _prefs.setString('cloudBaseUrl', next.cloudBaseUrl),
      _prefs.setString('cloudModel', next.cloudModel),
      _prefs.setInt('cloudDim', next.cloudDim),
    ]);
  }
}
