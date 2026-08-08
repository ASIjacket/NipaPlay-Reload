# Emby Media Source and Track Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Emby 剧集页独立查看、选择并记忆媒体源、音轨和字幕，同时让直接播放按已解析的轨道偏好真正生效。

**Architecture:** 以类型化媒体描述、版本名解析器、分层偏好 Store 和纯 Resolver 为核心；短生命周期 Catalog/Controller 负责网络与草稿状态，Windows 对话框和 iOS 底部面板只负责呈现。播放入口和播放器菜单共享同一偏好写入用例，转码、直播放内嵌轨道与直播放外挂字幕分别应用选择结果。

**Tech Stack:** Flutter 3.44.6、Dart、Provider、SharedPreferences、现有 Emby `PlaybackInfo` API、现有播放器抽象层。

## Global Constraints

- 功能只改变 Emby；Jellyfin 调用路径和行为保持不变。
- 剧集页入口只在 Windows 或 iOS 且未启用大屏模式时显示。
- 不实现单文件多视频轨道切换。
- 不修改 UA、代理、转码质量或 GitHub Action 文件。
- 源码注释只解释长期有效的不变量与回退原因，不写平台适配范围或临时版本说明。
- 每个任务严格执行 Red-Green-Refactor；新增生产代码覆盖率不低于 80%。
- 每次代码修改后都执行独立 code-reviewer 审查，修复 blocker 后才能提交。

### Mandatory TDD Gates for Every Task

- **Test gate:** 写完测试后立即调用 code-reviewer；每次修复审查 blocker 后重新审查。向用户展示最终测试 diff 与覆盖边界，并等待明确批准，之后才能运行 RED。
- **Implementation gate:** 写完最小实现后立即调用 code-reviewer；每次修复审查 blocker 后重新审查，之后才能运行 GREEN。
- **Refactor gate:** GREEN 后如修改生产代码，重新调用 code-reviewer，并再次运行该任务的全部测试。

---

## File Map

- Create `lib/models/emby_media_selection.dart`: 类型化媒体源、流描述、轨道指纹、偏好与解析结果。
- Modify `lib/models/media_server_playback.dart`: 补齐 Emby `Name`、`Size`、`Bitrate` 字段映射。
- Create `lib/services/emby_release_name_parser.dart`: 归一化完整版本名并提取发布源家族与版本特征。
- Create `lib/services/emby_media_selection_resolver.dart`: 纯 Dart 媒体源与轨道继承、排序和回退。
- Create `lib/services/emby_media_preference_store.dart`: 版本化 SharedPreferences JSON、账户隔离与有界本集记录。
- Create `lib/services/emby_media_source_catalog.dart`: 按需加载、并发合并和页面生命周期缓存。
- Create `lib/services/emby_media_selection_controller.dart`: 面板草稿、重选轨道、应用与错误状态。
- Create `lib/services/emby_track_application.dart`: 原生播放器轨道匹配与外挂字幕加载决策。
- Create `lib/services/emby_player_menu_selection.dart`: 将现有菜单轨道转换为领域偏好，并为换源解析新的轨道 bundle。
- Replace `lib/widgets/emby_media_source_selector.dart` with reusable selection content while preserving any still-used public helper during migration.
- Create `lib/themes/nipaplay/widgets/emby_media_selection_dialog.dart`: Windows 容器。
- Create `lib/themes/cupertino/widgets/emby_media_selection_sheet.dart`: iOS 容器。
- Modify `lib/pages/media_server_detail_page.dart`: Emby 入口、Controller 生命周期和无强制弹窗播放编排。
- Modify `lib/services/emby_service.dart`: 为 Catalog 暴露媒体描述请求边界并保持播放会话创建职责。
- Modify `lib/utils/video_player_state/video_player_state_streaming.dart`: 应用选择、精确外挂字幕和偏好写入。
- Modify `lib/utils/video_player_state/video_player_state_player_setup.dart`: 播放器打开后应用直播放轨道结果。
- Modify `lib/utils/video_player_state.dart`: 保存当前播放所使用的 Emby 轨道解析结果。
- Modify desktop/iOS Emby player menu files to write the shared Store; leave Jellyfin branches untouched.

### Task 1: Typed Emby Media Description

**Files:**
- Create: `lib/models/emby_media_selection.dart`
- Modify: `lib/models/media_server_playback.dart`
- Test: `test/emby_media_description_test.dart`

**Interfaces:**
- Consumes: Emby `MediaSources` and `MediaStreams` JSON.
- Produces: 后续任务共享的全部领域类型，以及 `EmbyMediaSourceDescriptor describeEmbyMediaSource(PlaybackMediaSource source, {required int ordinal})`。

- [ ] **Step 1: Write the failing parsing tests**

```dart
test('maps Emby source metadata and typed tracks', () {
  final source = PlaybackMediaSource.fromJson({
    'Id': 'baha',
    'Name': 'WEB-DL.Baha',
    'Size': 1470000000,
    'Bitrate': 2200000,
    'Container': 'mkv',
    'MediaStreams': [
      {'Index': 0, 'Type': 'Video', 'Codec': 'hevc', 'Profile': 'Main 10', 'Level': '153', 'Width': 1920, 'Height': 1080, 'VideoRange': 'HDR'},
      {'Index': 1, 'Type': 'Audio', 'Language': 'jpn', 'Title': '日语', 'Codec': 'aac', 'Channels': 2, 'IsDefault': true},
      {'Index': 2, 'Type': 'Subtitle', 'Language': 'chi', 'Title': '简体', 'Codec': 'ass', 'IsExternal': false},
    ],
  });
  final descriptor = describeEmbyMediaSource(source, ordinal: 0);

  expect(source.name, 'WEB-DL.Baha');
  expect(source.size, 1470000000);
  expect(source.bitRate, 2200000);
  expect(descriptor.videoTracks.single.profile, 'Main 10');
  expect(descriptor.videoTracks.single.level, '153');
  expect(descriptor.audioTracks.single.index, 1);
  expect(descriptor.subtitleTracks.single.isExternal, isFalse);
  expect(descriptor.summary, '1080p · 1.37 GB · 2.2 Mbps');
});
```

- [ ] **Gate: Execute the mandatory test gate and wait for user approval**

- [ ] **Step 2: Run the test and verify RED**

Run: `fvm flutter test --no-pub test/emby_media_description_test.dart`

Expected: FAIL because the new fields and descriptor types do not exist.

- [ ] **Step 3: Implement the typed model boundary**

```dart
class PlaybackMediaSource {
  final String? name;
  final int? size;
  final int? bitRate;

  factory PlaybackMediaSource.fromJson(Map<String, dynamic> json) {
    int? integer(Object? value) => value is num ? value.toInt() : int.tryParse('$value');
    return PlaybackMediaSource(
      id: json['Id']?.toString() ?? '',
      name: json['Name']?.toString(),
      size: integer(json['Size']),
      bitRate: integer(json['Bitrate']),
      mediaStreams: parsedStreams,
    );
  }
}

class EmbyTrackFingerprint {
  const EmbyTrackFingerprint({
    this.language,
    this.normalizedTitle,
    this.codec,
    this.channels,
    this.isExternal,
  });
  final String? language;
  final String? normalizedTitle;
  final String? codec;
  final int? channels;
  final bool? isExternal;

  @override
  bool operator ==(Object other) =>
      other is EmbyTrackFingerprint &&
      language == other.language &&
      normalizedTitle == other.normalizedTitle &&
      codec == other.codec &&
      channels == other.channels &&
      isExternal == other.isExternal;

  @override
  int get hashCode => Object.hash(language, normalizedTitle, codec, channels, isExternal);
}

class EmbyReleaseIdentity {
  const EmbyReleaseIdentity({
    required this.normalizedFullName,
    required this.families,
    required this.features,
  });
  final String normalizedFullName;
  final Set<String> families;
  final Set<String> features;
}

class EmbyTechnicalFingerprint {
  const EmbyTechnicalFingerprint({this.height, this.videoCodec, this.hdr, this.container});
  final int? height;
  final String? videoCodec;
  final String? hdr;
  final String? container;
}

class EmbyVideoStreamDescriptor {
  const EmbyVideoStreamDescriptor({required this.index, this.codec, this.profile, this.level, this.width, this.height, this.frameRate, this.bitDepth, this.hdr, this.bitRate});
  final int index;
  final String? codec;
  final String? profile;
  final String? level;
  final int? width;
  final int? height;
  final double? frameRate;
  final int? bitDepth;
  final String? hdr;
  final int? bitRate;
}

class EmbyAudioTrackDescriptor {
  const EmbyAudioTrackDescriptor({required this.index, this.language, this.title, this.codec, this.channels, this.sampleRate, this.bitRate, required this.isDefault, required this.fingerprint});
  final int index;
  final String? language;
  final String? title;
  final String? codec;
  final int? channels;
  final int? sampleRate;
  final int? bitRate;
  final bool isDefault;
  final EmbyTrackFingerprint fingerprint;
}

class EmbySubtitleTrackDescriptor {
  const EmbySubtitleTrackDescriptor({required this.index, this.language, this.title, this.codec, required this.isExternal, required this.isDefault, required this.isForced, required this.fingerprint});
  final int index;
  final String? language;
  final String? title;
  final String? codec;
  final bool isExternal;
  final bool isDefault;
  final bool isForced;
  final EmbyTrackFingerprint fingerprint;
}

class EmbyMediaSourceDescriptor {
  const EmbyMediaSourceDescriptor({
    required this.source,
    required this.displayName,
    required this.summary,
    required this.technical,
    required this.videoTracks,
    required this.audioTracks,
    required this.subtitleTracks,
  });
  final PlaybackMediaSource source;
  final String displayName;
  final String summary;
  final EmbyTechnicalFingerprint technical;
  final List<EmbyVideoStreamDescriptor> videoTracks;
  final List<EmbyAudioTrackDescriptor> audioTracks;
  final List<EmbySubtitleTrackDescriptor> subtitleTracks;
}

class EmbySelectionContext {
  const EmbySelectionContext({required this.accountKey, required this.seriesId, required this.episodeId});
  final String accountKey;
  final String seriesId;
  final String episodeId;
}

enum EmbyTrackPreferenceMode { followDefault, disabled, track }

class EmbyTrackPreference {
  const EmbyTrackPreference.followDefault()
      : mode = EmbyTrackPreferenceMode.followDefault,
        fingerprint = null,
        sourceIndex = null,
        mediaSourceId = null;
  const EmbyTrackPreference.disabled()
      : mode = EmbyTrackPreferenceMode.disabled,
        fingerprint = null,
        sourceIndex = null,
        mediaSourceId = null;
  const EmbyTrackPreference.track(
    EmbyTrackFingerprint value, {
    this.sourceIndex,
    this.mediaSourceId,
  })  : assert((sourceIndex == null) == (mediaSourceId == null)),
        assert(sourceIndex == null || sourceIndex >= 0),
        mode = EmbyTrackPreferenceMode.track,
        fingerprint = value;
  final EmbyTrackPreferenceMode mode;
  final EmbyTrackFingerprint? fingerprint;
  final int? sourceIndex;
  final String? mediaSourceId;
}

enum EmbyResolvedTrackMode { followDefault, disabled, track }

class EmbyResolvedTrackSelection {
  const EmbyResolvedTrackSelection.followDefault()
      : mode = EmbyResolvedTrackMode.followDefault,
        sourceIndex = null,
        fingerprint = null;
  const EmbyResolvedTrackSelection.disabled()
      : mode = EmbyResolvedTrackMode.disabled,
        sourceIndex = null,
        fingerprint = null;
  const EmbyResolvedTrackSelection.track({required int sourceIndex, required EmbyTrackFingerprint fingerprint})
      : mode = EmbyResolvedTrackMode.track,
        sourceIndex = sourceIndex,
        fingerprint = fingerprint;
  final EmbyResolvedTrackMode mode;
  final int? sourceIndex;
  final EmbyTrackFingerprint? fingerprint;
}

class EmbyResolvedTrackBundle {
  const EmbyResolvedTrackBundle({required this.audio, required this.subtitle});
  final EmbyResolvedTrackSelection audio;
  final EmbyResolvedTrackSelection subtitle;
}

class EmbyEpisodePreference {
  const EmbyEpisodePreference({
    this.mediaSourceId,
    this.audio,
    this.subtitle,
    required this.updatedAt,
  });
  final String? mediaSourceId;
  final EmbyTrackPreference? audio;
  final EmbyTrackPreference? subtitle;
  final DateTime updatedAt;
  bool get isEmpty => mediaSourceId == null && audio == null && subtitle == null;
}

class EmbySeriesPreference {
  const EmbySeriesPreference({
    this.normalizedFullName,
    this.families = const <String>{},
    this.features = const <String>{},
    this.technical,
    this.audio,
    this.subtitle,
  });
  final String? normalizedFullName;
  final Set<String> families;
  final Set<String> features;
  final EmbyTechnicalFingerprint? technical;
  final EmbyTrackPreference? audio;
  final EmbyTrackPreference? subtitle;
  bool get isEmpty =>
      normalizedFullName == null && families.isEmpty && features.isEmpty &&
      technical == null && audio == null && subtitle == null;
}

class EmbyGlobalPreference {
  const EmbyGlobalPreference({
    this.families = const <String>{},
    this.technical,
    this.audio,
    this.subtitle,
  });
  final Set<String> families;
  final EmbyTechnicalFingerprint? technical;
  final EmbyTrackPreference? audio;
  final EmbyTrackPreference? subtitle;
  bool get isEmpty =>
      families.isEmpty && technical == null && audio == null && subtitle == null;
}

class EmbyPreferenceLayers {
  const EmbyPreferenceLayers({this.episode, this.series, this.global});
  final EmbyEpisodePreference? episode;
  final EmbySeriesPreference? series;
  final EmbyGlobalPreference? global;
  bool get isEmpty =>
      (episode == null || episode!.isEmpty) &&
      (series == null || series!.isEmpty) &&
      (global == null || global!.isEmpty);
}

class EmbyManualSelectionPatch {
  const EmbyManualSelectionPatch({this.source, this.audio, this.subtitle});
  final EmbyMediaSourceDescriptor? source;
  final EmbyTrackPreference? audio;
  final EmbyTrackPreference? subtitle;
}

enum EmbySelectionReason {
  episodeExact,
  seriesFullName,
  seriesFamily,
  globalFamily,
  technical,
  embyDefault,
}

class EmbySourceCandidate {
  const EmbySourceCandidate({required this.source, required this.reason, required this.tracks});
  final EmbyMediaSourceDescriptor source;
  final EmbySelectionReason reason;
  final EmbyResolvedTrackBundle tracks;
}

class EmbyResolutionPlan {
  const EmbyResolutionPlan({required this.candidates});
  final List<EmbySourceCandidate> candidates;
}
```

Implement the exact top-level function `EmbyMediaSourceDescriptor describeEmbyMediaSource(PlaybackMediaSource source, {required int ordinal})` with safe numeric parsing, source label fallback (`Name` → basename → container/ordinal), human-readable size/bitrate, and typed stream filtering. Map video `Profile` and `Level` into the typed descriptor. Keep `mediaStreams` for backward compatibility.

- [ ] **Gate: Execute the mandatory implementation gate**

- [ ] **Step 4: Run tests and verify GREEN**

Run: `fvm flutter test --no-pub test/emby_media_description_test.dart test/emby_media_source_selection_test.dart`

Expected: PASS.

- [ ] **Gate: Execute the mandatory refactor gate**

- [ ] **Step 5: Review and commit**

```bash
git add lib/models/media_server_playback.dart lib/models/emby_media_selection.dart test/emby_media_description_test.dart
git commit -m "feat: model Emby media source metadata"
```

### Task 2: Release Identity and Deterministic Resolver

**Files:**
- Create: `lib/services/emby_release_name_parser.dart`
- Create: `lib/services/emby_media_selection_resolver.dart`
- Test: `test/emby_release_name_parser_test.dart`
- Test: `test/emby_media_selection_resolver_test.dart`

**Interfaces:**
- Consumes: `EmbyMediaSourceDescriptor` and already-loaded `EmbyPreferenceLayers`.
- Produces: `EmbyReleaseIdentity parseEmbyReleaseIdentity(String name)` and `EmbyResolutionPlan resolve({required List<EmbyMediaSourceDescriptor> sources, required EmbyPreferenceLayers preferences})`.

- [ ] **Step 1: Write failing parser and resolver tests**

```dart
test('extracts families without collapsing subtitle variants', () {
  final identity = parseEmbyReleaseIdentity('简繁日内封.喵萌奶茶屋&LoliHouse');
  expect(identity.families, {'喵萌奶茶屋', 'lolihouse'});
  expect(identity.features, contains('简繁日内封'));
  expect(identity.normalizedFullName, isNot(parseEmbyReleaseIdentity('简体内嵌.喵萌奶茶屋').normalizedFullName));
});

test('orders exact episode, series full name, family, technical, default', () {
  final plan = resolver.resolve(sources: sources, preferences: layers);
  expect(plan.candidates.map((candidate) => candidate.reason), [
    EmbySelectionReason.episodeExact,
    EmbySelectionReason.seriesFullName,
    EmbySelectionReason.globalFamily,
    EmbySelectionReason.technical,
    EmbySelectionReason.embyDefault,
  ]);
});

test('uses an exact stream index only for the media source that owns it', () {
  final sameSource = resolver.resolve(
    sources: [sourceB],
    preferences: layersWithEpisodeAudio(sourceId: 'source-b', index: 7, fingerprint: japaneseStereo),
  );
  expect(sameSource.candidates.single.tracks.audio.sourceIndex, 7);

  final otherSource = resolver.resolve(
    sources: [sourceAWithMatchingJapaneseAtIndex1],
    preferences: layersWithEpisodeAudio(sourceId: 'source-b', index: 7, fingerprint: japaneseStereo),
  );
  expect(otherSource.candidates.single.tracks.audio.sourceIndex, 1);
  expect(otherSource.candidates.single.tracks.audio.sourceIndex, isNot(7));
});
```

- [ ] **Gate: Execute the mandatory test gate and wait for user approval**

- [ ] **Step 2: Run tests and verify RED**

Run: `fvm flutter test --no-pub test/emby_release_name_parser_test.dart test/emby_media_selection_resolver_test.dart`

Expected: FAIL because parser and resolver are absent.

- [ ] **Step 3: Implement deterministic matching**

```dart
abstract interface class EmbyMediaSelectionResolver {
  EmbyResolutionPlan resolve({
    required List<EmbyMediaSourceDescriptor> sources,
    required EmbyPreferenceLayers preferences,
  });
}
```

Implement `DefaultEmbyMediaSelectionResolver` as the concrete implementation of this interface. Normalize whitespace, Latin case and separators; recognize resolution, codec, release format and subtitle packaging tokens. De-duplicate candidates by `source.source.id` while preserving the documented priority. Resolve audio and subtitle independently for every candidate and store the result in `candidate.tracks`; use an episode `sourceIndex` only when its `mediaSourceId` equals the candidate source and that index still exists, otherwise match its fingerprint.

- [ ] **Gate: Execute the mandatory implementation gate**

- [ ] **Step 4: Run tests and verify GREEN**

Run: `fvm flutter test --no-pub test/emby_release_name_parser_test.dart test/emby_media_selection_resolver_test.dart`

Expected: PASS with stable candidate ordering.

- [ ] **Gate: Execute the mandatory refactor gate**

- [ ] **Step 5: Review and commit**

```bash
git add lib/services/emby_release_name_parser.dart lib/services/emby_media_selection_resolver.dart test/emby_release_name_parser_test.dart test/emby_media_selection_resolver_test.dart
git commit -m "feat: resolve Emby release preferences"
```

### Task 3: Versioned Preference Store

**Files:**
- Create: `lib/services/emby_media_preference_store.dart`
- Test: `test/emby_media_preference_store_test.dart`

**Interfaces:**
- Consumes: `SharedPreferences`, `EmbySelectionContext`, `EmbyManualSelectionPatch`.
- Produces: `EmbySelectionContext? buildEmbySelectionContext({required ServerProfile? profile, required String? userId, required String seriesId, required String episodeId})`, `Future<EmbyPreferenceLayers> load(EmbySelectionContext context)`, and `Future<void> saveManualPatch(EmbySelectionContext context, EmbyMediaSourceDescriptor currentSource, EmbyManualSelectionPatch patch)`.

- [ ] **Step 1: Write failing persistence tests**

```dart
late EmbyMediaPreferenceStore store;

setUp(() async {
  SharedPreferences.setMockInitialValues({});
  store = EmbyMediaPreferenceStore(
    await SharedPreferences.getInstance(),
    maxEpisodeRecords: 2,
  );
});

test('isolates accounts and writes all manual layers', () async {
  await store.saveManualPatch(contextA, sourceB, EmbyManualSelectionPatch(
    source: sourceB,
    audio: const EmbyTrackPreference.followDefault(),
    subtitle: const EmbyTrackPreference.followDefault(),
  ));

  expect((await store.load(contextA)).episode?.mediaSourceId, 'source-b');
  expect((await store.load(contextA)).series?.normalizedFullName, 'web-dl.baha');
  expect((await store.load(contextA)).global?.families, contains('baha'));
  expect((await store.load(contextB)).isEmpty, isTrue);
});

test('treats subtitle off as an explicit inherited preference', () async {
  await store.saveManualPatch(contextA, sourceB, const EmbyManualSelectionPatch(subtitle: EmbyTrackPreference.disabled()));
  final inherited = await store.load(nextEpisodeContext);
  expect(inherited.series?.subtitle?.mode, EmbyTrackPreferenceMode.disabled);
  expect(inherited.global?.subtitle?.mode, EmbyTrackPreferenceMode.disabled);
});

test('patches only the dimension the user changed', () async {
  await store.saveManualPatch(contextA, sourceB, EmbyManualSelectionPatch(
    source: sourceB,
    audio: EmbyTrackPreference.track(
      japaneseStereo,
      sourceIndex: 1,
      mediaSourceId: 'source-b',
    ),
    subtitle: EmbyTrackPreference.track(chineseAss),
  ));
  await store.saveManualPatch(contextA, sourceB, const EmbyManualSelectionPatch(subtitle: EmbyTrackPreference.disabled()));
  var layers = await store.load(contextA);
  expect(layers.episode?.mediaSourceId, 'source-b');
  expect(layers.episode?.audio?.fingerprint, japaneseStereo);
  expect(layers.episode?.audio?.sourceIndex, 1);
  expect(layers.episode?.audio?.mediaSourceId, 'source-b');
  expect(layers.episode?.subtitle?.mode, EmbyTrackPreferenceMode.disabled);
  expect(layers.series?.normalizedFullName, 'web-dl.baha');
  expect(layers.series?.audio?.fingerprint, japaneseStereo);
  expect(layers.series?.audio?.sourceIndex, isNull);
  expect(layers.series?.audio?.mediaSourceId, isNull);
  expect(layers.global?.families, contains('baha'));
  expect(layers.global?.audio?.fingerprint, japaneseStereo);
  expect(layers.global?.audio?.sourceIndex, isNull);
  expect(layers.global?.audio?.mediaSourceId, isNull);

  await store.saveManualPatch(contextA, sourceB, const EmbyManualSelectionPatch(audio: EmbyTrackPreference.followDefault()));
  layers = await store.load(contextA);
  expect(layers.episode?.mediaSourceId, 'source-b');
  expect(layers.episode?.audio, isNull);
  expect(layers.series?.audio, isNull);
  expect(layers.global?.audio, isNull);
  expect(layers.episode?.subtitle?.mode, EmbyTrackPreferenceMode.disabled);
});

test('rejects disabled audio preferences', () async {
  await expectLater(
    store.saveManualPatch(contextA, sourceB, const EmbyManualSelectionPatch(audio: EmbyTrackPreference.disabled())),
    throwsArgumentError,
  );
});

test('rejects an account key when server or user identity is missing', () {
  expect(embyAccountKey(null, null), isNull);
  expect(embyAccountKey(profileWithoutServerId, 'user-1'), 'local-profile:user-1');
  expect(embyAccountKey(profileWithServerId, null), isNull);
  expect(buildEmbySelectionContext(profile: null, userId: null, seriesId: 'series-1', episodeId: 'episode-1'), isNull);
});

test('ignores malformed JSON and evicts the oldest episode record', () async {
  SharedPreferences.setMockInitialValues({'emby_media_preferences_v1': '{'});
  final prefs = await SharedPreferences.getInstance();
  var tick = DateTime.utc(2026, 8, 9);
  final evictionStore = EmbyMediaPreferenceStore(
    prefs,
    maxEpisodeRecords: 2,
    now: () => tick = tick.add(const Duration(seconds: 1)),
  );
  expect((await evictionStore.load(contextA)).isEmpty, isTrue);
  await evictionStore.saveManualPatch(episode1, sourceA, EmbyManualSelectionPatch(source: sourceA));
  await evictionStore.saveManualPatch(episode2, sourceA, EmbyManualSelectionPatch(source: sourceA));
  await evictionStore.saveManualPatch(episode3, sourceA, EmbyManualSelectionPatch(source: sourceA));
  expect((await evictionStore.load(episode1)).episode, isNull);
  expect((await evictionStore.load(episode3)).episode?.mediaSourceId, 'source-a');
});
```

- [ ] **Gate: Execute the mandatory test gate and wait for user approval**

- [ ] **Step 2: Run test and verify RED**

Run: `fvm flutter test --no-pub test/emby_media_preference_store_test.dart`

Expected: FAIL because the Store is absent.

- [ ] **Step 3: Implement schema, validation and bounded eviction**

```dart
String? embyAccountKey(ServerProfile? profile, String? userId) {
  final server = profile?.serverId?.trim();
  final fallback = profile?.id.trim();
  final resolvedServer = server?.isNotEmpty == true ? server : fallback;
  final resolvedUser = userId?.trim();
  if (resolvedServer == null || resolvedServer.isEmpty || resolvedUser == null || resolvedUser.isEmpty) return null;
  return '$resolvedServer:$resolvedUser';
}
```

Use preference key `emby_media_preferences_v1`. Decode only a map with `version == 1`; malformed JSON returns empty layers. Remove the oldest episode records by `updatedAt` after every save. Persist no token, URL, path or `PlaySessionId`.

Patch semantics are explicit: a null field means “leave that dimension unchanged”; `followDefault` clears the saved manual preference for that dimension; subtitle `disabled` is persisted and audio `disabled` throws `ArgumentError`; `track` persists a non-null fingerprint. The episode layer keeps a validated `mediaSourceId + sourceIndex`; the Store removes both fields from series/global copies. `currentSource` supplies source identity for the layer being edited but does not update the saved source preference unless `patch.source` is non-null. Remove empty layer records after patching and after decoding. Inject `DateTime Function() now` into the Store so eviction tests and timestamps are deterministic.

- [ ] **Gate: Execute the mandatory implementation gate**

- [ ] **Step 4: Run tests and verify GREEN**

Run: `fvm flutter test --no-pub test/emby_media_preference_store_test.dart`

Expected: PASS, including corruption and eviction cases.

- [ ] **Gate: Execute the mandatory refactor gate**

- [ ] **Step 5: Review and commit**

```bash
git add lib/services/emby_media_preference_store.dart test/emby_media_preference_store_test.dart
git commit -m "feat: persist Emby media preferences"
```

### Task 4: On-Demand Catalog and Draft Controller

**Files:**
- Create: `lib/services/emby_media_source_catalog.dart`
- Create: `lib/services/emby_media_selection_controller.dart`
- Modify: `lib/services/emby_service.dart`
- Test: `test/emby_media_source_catalog_test.dart`
- Test: `test/emby_media_selection_controller_test.dart`

**Interfaces:**
- Consumes: `Future<List<PlaybackMediaSource>> Function(String itemId)`, Store and Resolver.
- Produces: `EmbyMediaSourceCatalog.load`, `invalidateScope`, and a `ChangeNotifier` Controller with immutable draft state.

- [ ] **Step 1: Write failing cache and draft tests**

```dart
test('coalesces concurrent loads and invalidates by account', () async {
  final results = await Future.wait([catalog.load('account-a', 'episode-1'), catalog.load('account-a', 'episode-1')]);
  expect(loaderCalls, 1);
  expect(identical(results.first, results.last), isTrue);
  catalog.invalidateScope('account-a');
  await catalog.load('account-a', 'episode-1');
  expect(loaderCalls, 2);
});

test('cancel discards draft and apply writes once without playing', () async {
  await controller.load();
  controller.selectSource('source-b');
  controller.cancel();
  expect(storeWrites, 0);
  expect(playCalls, 0);
});

test('retry bypasses the failed catalog entry', () async {
  loaderErrorsRemaining = 1;
  await controller.load();
  expect(controller.state.error, isNotNull);
  await controller.load(forceRefresh: true);
  expect(controller.state.error, isNull);
  expect(loaderCalls, 2);
});

test('source change re-resolves tracks and records only dirty dimensions', () async {
  await controller.load();
  controller.selectSource('source-b');
  expect(controller.state.audio, resolvedSourceBAudio);
  expect(controller.state.subtitle, resolvedSourceBSubtitle);
  expect(controller.state.dirtyDimensions, {EmbySelectionDimension.source});
});

test('save failure remains visible and never reports success', () async {
  storeError = StateError('disk');
  await controller.load();
  controller.selectSubtitle(const EmbyTrackPreference.disabled());
  await expectLater(controller.apply(), throwsStateError);
  expect(controller.state.isSaving, isFalse);
  expect(controller.state.error, same(storeError));
  expect(applySuccessEvents, 0);
});

test('missing identity loads catalog but disables persistence', () async {
  final controller = buildController(context: null, catalogScopeKey: 'emby-session');
  await controller.load();
  expect(controller.state.sources, isNotEmpty);
  expect(controller.state.canPersist, isFalse);
  expect(storeReads, 0);
  expect(await controller.apply(), isFalse);
  expect(controller.state.error, isA<StateError>());
  expect(storeWrites, 0);
});
```

- [ ] **Gate: Execute the mandatory test gate and wait for user approval**

- [ ] **Step 2: Run tests and verify RED**

Run: `fvm flutter test --no-pub test/emby_media_source_catalog_test.dart test/emby_media_selection_controller_test.dart`

Expected: FAIL because Catalog and Controller are absent.

- [ ] **Step 3: Implement the short-lived coordinator**

```dart
typedef EmbyMediaSourceLoader = Future<List<PlaybackMediaSource>> Function(String itemId);

abstract interface class EmbyMediaSourceCatalog {
  Future<List<EmbyMediaSourceDescriptor>> load(String cacheScopeKey, String itemId, {bool forceRefresh = false});
  void invalidateScope(String cacheScopeKey);
  void clear();
}

enum EmbySelectionDimension { source, audio, subtitle }

class EmbyMediaSelectionState {
  EmbyMediaSelectionState({
    List<EmbyMediaSourceDescriptor> sources = const <EmbyMediaSourceDescriptor>[],
    this.selectedSourceId,
    this.audio = const EmbyTrackPreference.followDefault(),
    this.subtitle = const EmbyTrackPreference.followDefault(),
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    this.canPersist = true,
    Set<EmbySelectionDimension> dirtyDimensions = const <EmbySelectionDimension>{},
  })  : sources = List<EmbyMediaSourceDescriptor>.unmodifiable(sources),
        dirtyDimensions = Set<EmbySelectionDimension>.unmodifiable(dirtyDimensions);
  final List<EmbyMediaSourceDescriptor> sources;
  final String? selectedSourceId;
  final EmbyTrackPreference audio;
  final EmbyTrackPreference subtitle;
  final bool isLoading;
  final bool isSaving;
  final Object? error;
  final bool canPersist;
  final Set<EmbySelectionDimension> dirtyDimensions;
}

abstract class EmbyMediaSelectionController extends ChangeNotifier {
  EmbyMediaSelectionState get state;
  Future<void> load({bool forceRefresh = false});
  void selectSource(String sourceId);
  void selectAudio(EmbyTrackPreference preference);
  void selectSubtitle(EmbyTrackPreference preference);
  Future<bool> apply();
  void cancel();
}
```

Implement `CachedEmbyMediaSourceCatalog` with constructor `CachedEmbyMediaSourceCatalog({required EmbyMediaSourceLoader loader, Duration ttl = const Duration(minutes: 2)})` and all `EmbyMediaSourceCatalog` members. Implement `DefaultEmbyMediaSelectionController` with constructor `DefaultEmbyMediaSelectionController({required EmbyMediaSourceCatalog catalog, required EmbyMediaPreferenceStore store, required EmbyMediaSelectionResolver resolver, required EmbySelectionContext? context, required String catalogScopeKey, required String itemId})` and all `EmbyMediaSelectionController` members. Detail page passes `context?.accountKey ?? 'emby-session'` as the page-local cache scope; this value is never persisted. Add an Emby service method that returns parsed `MediaSources` without exposing or persisting a final playback URL/session. Controller stores a baseline state; selectors mark only the dimension directly changed by the user. A source change re-resolves track drafts without marking audio/subtitle dirty. When context is null, load Catalog with empty preference layers, expose `canPersist == false`, and make `apply()` set `StateError('无法保存 Emby 媒体偏好：账号标识不可用')` in state and return `false` without Store access. With a context, `apply()` converts dirty dimensions to `EmbyManualSelectionPatch`, awaits Store save, clears the error and returns `true`. It never calls playback or danmaku APIs.

- [ ] **Gate: Execute the mandatory implementation gate**

- [ ] **Step 4: Run tests and verify GREEN**

Run: `fvm flutter test --no-pub test/emby_media_source_catalog_test.dart test/emby_media_selection_controller_test.dart`

Expected: PASS, including retry, save error and source-change draft re-resolution.

- [ ] **Gate: Execute the mandatory refactor gate**

- [ ] **Step 5: Review and commit**

```bash
git add lib/services/emby_service.dart lib/services/emby_media_source_catalog.dart lib/services/emby_media_selection_controller.dart test/emby_media_source_catalog_test.dart test/emby_media_selection_controller_test.dart
git commit -m "feat: coordinate Emby media selection"
```

### Task 5: Windows and iOS Selection Surfaces

**Files:**
- Modify: `lib/widgets/emby_media_source_selector.dart`
- Create: `lib/themes/nipaplay/widgets/emby_media_selection_dialog.dart`
- Create: `lib/themes/cupertino/widgets/emby_media_selection_sheet.dart`
- Modify: `lib/pages/media_server_detail_page.dart`
- Test: `test/emby_media_selection_panel_test.dart`
- Test: `test/emby_media_selection_entry_policy_test.dart`

**Interfaces:**
- Consumes: `EmbyMediaSelectionController` and a pure entry policy.
- Produces: `Future<bool?> showEmbyMediaSelection({required BuildContext context, required bool useCupertino, required EmbyMediaSelectionController controller})` and `bool shouldShowEmbyMediaSelectionEntry({required bool isEmby, required bool isWindows, required bool isIOS, required bool isLargeScreen})`.

- [ ] **Step 1: Write failing widget and policy tests**

```dart
test('entry policy accepts Emby Windows/iOS outside large screen only', () {
  expect(shouldShowEmbyMediaSelectionEntry(isEmby: true, isWindows: true, isIOS: false, isLargeScreen: false), isTrue);
  expect(shouldShowEmbyMediaSelectionEntry(isEmby: true, isWindows: false, isIOS: true, isLargeScreen: false), isTrue);
  expect(shouldShowEmbyMediaSelectionEntry(isEmby: false, isWindows: true, isIOS: false, isLargeScreen: false), isFalse);
  expect(shouldShowEmbyMediaSelectionEntry(isEmby: true, isWindows: true, isIOS: false, isLargeScreen: true), isFalse);
});

testWidgets('apply saves and closes without starting playback', (tester) async {
  await tester.pumpWidget(buildWindowsHarness(controller));
  expect(find.text('WEB-DL.Baha'), findsOneWidget);
  expect(find.text('1080p · 1.37 GB · 2.2 Mbps'), findsOneWidget);
  await tester.tap(find.text('应用'));
  await tester.pumpAndSettle();
  expect(controller.applyCalls, 1);
  expect(playCalls, 0);
});

testWidgets('failed apply keeps the panel open and shows the controller error', (tester) async {
  controller.applyResult = false;
  controller.error = StateError('无法保存 Emby 媒体偏好：账号标识不可用');
  await tester.pumpWidget(buildWindowsHarness(controller));
  await tester.tap(find.text('应用'));
  await tester.pumpAndSettle();
  expect(find.text('版本与轨道'), findsOneWidget);
  expect(find.textContaining('账号标识不可用'), findsOneWidget);
  expect(applySuccessMessages, 0);
});
```

- [ ] **Gate: Execute the mandatory test gate and wait for user approval**

- [ ] **Step 2: Run tests and verify RED**

Run: `fvm flutter test --no-pub test/emby_media_selection_panel_test.dart test/emby_media_selection_entry_policy_test.dart`

Expected: FAIL because the policy and surfaces do not exist.

- [ ] **Step 3: Implement progressive disclosure UI**

```dart
bool shouldShowEmbyMediaSelectionEntry({
  required bool isEmby,
  required bool isWindows,
  required bool isIOS,
  required bool isLargeScreen,
}) => isEmby && (isWindows || isIOS) && !isLargeScreen;
```

Build one reusable content widget with source list and `概览 / 音轨 / 字幕` tabs. Windows wraps it in `BlurDialog`; iOS wraps it in `CupertinoBottomSheet` with fixed actions. Add an always-visible trailing `版本与轨道` action beside Emby episodes and show the saved source label when available. The episode tile body continues to call `_playEpisode`.

- [ ] **Gate: Execute the mandatory implementation gate**

- [ ] **Step 4: Run tests and verify GREEN**

Run: `fvm flutter test --no-pub test/emby_media_selection_panel_test.dart test/emby_media_selection_entry_policy_test.dart`

Expected: PASS for loading, error, retry, tabs, cancel and apply on both surfaces.

- [ ] **Gate: Execute the mandatory refactor gate**

- [ ] **Step 5: Review and commit**

```bash
git add lib/widgets/emby_media_source_selector.dart lib/themes/nipaplay/widgets/emby_media_selection_dialog.dart lib/themes/cupertino/widgets/emby_media_selection_sheet.dart lib/pages/media_server_detail_page.dart test/emby_media_selection_panel_test.dart test/emby_media_selection_entry_policy_test.dart
git commit -m "feat: add Emby version and track picker"
```

### Task 6: Preference-Driven Playback and Source Fallback

**Files:**
- Modify: `lib/services/emby_media_source_selection.dart`
- Modify: `lib/pages/media_server_detail_page.dart`
- Modify: `lib/utils/video_player_state.dart`
- Modify: `lib/utils/video_player_state/video_player_state_player_setup.dart`
- Modify: `lib/utils/video_player_state/video_player_state_streaming.dart`
- Test: `test/emby_media_source_selection_test.dart`

**Interfaces:**
- Consumes: ordered `EmbyResolutionPlan.candidates` and `EmbyService.createPlaybackSession`.
- Produces: `Future<EmbyResolvedPlayback> resolveEmbyPlaybackSession({required EmbyResolutionPlan plan, required Future<PlaybackSession> Function(EmbySourceCandidate candidate) createSession})`; no chooser callback.

- [ ] **Step 1: Replace chooser tests with failing playback-plan tests**

```dart
test('plays remembered source without opening a chooser', () async {
  final result = await resolveEmbyPlaybackSession(plan: planForSourceB, createSession: createSession);
  expect(result.session.mediaSourceId, 'source-b');
  expect(chooserCalls, 0);
});

test('falls back in resolver order and reports the successful reason', () async {
  failures.add('source-b');
  final result = await resolveEmbyPlaybackSession(plan: planWithFallbacks, createSession: createSession);
  expect(requestedIds, ['source-b', 'source-a']);
  expect(requestedTrackBundles, [sourceBTracks, sourceATracks]);
  expect(result.didFallback, isTrue);
  expect(result.reason, EmbySelectionReason.seriesFamily);
  expect(result.tracks, same(sourceATracks));
});

test('threads the successful track bundle into player initialization', () async {
  await detailHarness.play(planForSourceB);
  expect(detailHarness.initializedSession?.mediaSourceId, 'source-b');
  expect(detailHarness.initializedEmbyTracks, same(sourceBTracks));
});

test('missing account identity keeps default playback available', () async {
  final result = await detailHarness.playWithContext(null);
  expect(result.session.mediaSourceId, embyDefaultSourceId);
  expect(preferenceStoreReads, 0);
  expect(detailHarness.playCalls, 1);
});

test('reload replaces the previous source track bundle', () async {
  await playerHarness.initialize(embyTrackSelection: sourceBTracks);
  await playerHarness.reloadEmby(mediaSourceId: 'source-a', embyTrackSelection: sourceATracks);
  expect(playerHarness.currentEmbyTrackSelection, same(sourceATracks));
  expect(playerHarness.lastInitializedEmbyTracks, same(sourceATracks));
});
```

- [ ] **Gate: Execute the mandatory test gate and wait for user approval**

- [ ] **Step 2: Run test and verify RED**

Run: `fvm flutter test --no-pub test/emby_media_source_selection_test.dart`

Expected: FAIL because playback still requires a chooser.

- [ ] **Step 3: Implement plan-based playback**

```dart
class EmbyResolvedPlayback {
  const EmbyResolvedPlayback({required this.session, required this.reason, required this.didFallback, required this.tracks});
  final PlaybackSession session;
  final EmbySelectionReason reason;
  final bool didFallback;
  final EmbyResolvedTrackBundle tracks;
}
```

For each unique candidate, the callback reads `candidate.tracks` and calls `createPlaybackSession` with that candidate's `mediaSourceId`; when transcoding is enabled, it also passes that candidate's resolved Emby audio/subtitle indices and burn-in state. Catch only candidate/session failures, preserve the final error if all candidates fail, and let the detail page show one non-blocking fallback message after successful playback resolution. Remove `_chooseEmbyMediaSource` from the episode path.

Add optional named parameter `EmbyResolvedTrackBundle? embyTrackSelection` to `_startEpisodePlayback`, `VideoPlayerState.initializePlayer`, and the existing delayed player-start call. Store it in `VideoPlayerState._currentEmbyTrackSelection` immediately after `_clearPreviousVideoState()`. `_startEpisodePlayback` passes `resolvedPlayback.tracks`; non-Emby callers omit it and keep existing behavior. Extend `reloadCurrentEmbyStream` with named parameter `EmbyResolvedTrackBundle? embyTrackSelection` and pass it into `initializePlayer`; every source-switch caller resolves and supplies the selected source's bundle so the previous source's indexes cannot survive reload.

- [ ] **Gate: Execute the mandatory implementation gate**

- [ ] **Step 4: Run tests and verify GREEN**

Run: `fvm flutter test --no-pub test/emby_media_source_selection_test.dart`

Expected: PASS and no assertion expects the old forced chooser.

- [ ] **Gate: Execute the mandatory refactor gate**

- [ ] **Step 5: Review and commit**

```bash
git add lib/services/emby_media_source_selection.dart lib/pages/media_server_detail_page.dart lib/utils/video_player_state.dart lib/utils/video_player_state/video_player_state_player_setup.dart lib/utils/video_player_state/video_player_state_streaming.dart test/emby_media_source_selection_test.dart
git commit -m "feat: apply Emby source preferences on playback"
```

### Task 7: Direct-Play Embedded and External Track Application

**Files:**
- Create: `lib/services/emby_track_application.dart`
- Modify: `lib/utils/video_player_state/video_player_state_streaming.dart`
- Modify: `lib/utils/video_player_state/video_player_state_player_setup.dart`
- Test: `test/emby_track_application_test.dart`
- Test: `test/emby_external_subtitle_selection_test.dart`

**Interfaces:**
- Consumes: `EmbyResolvedTrackBundle`, `PlayerMediaInfo`, selected `mediaSourceId`.
- Produces: native audio/subtitle indices and an explicit external subtitle action.

- [ ] **Step 1: Write failing direct-play contract tests**

```dart
test('matches native tracks after open by fingerprint rather than Emby index', () {
  final result = resolveNativeEmbyTracks(preference, playerMediaInfo);
  expect(result.audioIndex, 1);
  expect(result.subtitleIndex, 0);
});

test('subtitle off clears embedded and external subtitles', () async {
  await harness.apply(EmbyResolvedTrackSelection.disabled());
  expect(harness.activeSubtitleTracks, isEmpty);
  expect(harness.externalSubtitlePath, isEmpty);
  expect(harness.downloads, isEmpty);
});

test('downloads only the selected external subtitle', () async {
  await harness.loadExternal(selectedExternalTrack);
  expect(harness.downloadedIndexes, [4]);
  expect(harness.activatedServerIndex, 4);
  expect(harness.lastExternalAction.streamIndex, 4);
  expect(harness.lastExternalAction.codec, 'ass');
});

test('uses a safe text codec when an external subtitle omits codec', () {
  final action = resolveExternalSubtitleAction(externalTrackWithoutCodec);
  expect(action.kind, EmbyExternalSubtitleActionKind.select);
  expect(action.streamIndex, 5);
  expect(action.codec, 'srt');
});
```

- [ ] **Gate: Execute the mandatory test gate and wait for user approval**

- [ ] **Step 2: Run tests and verify RED**

Run: `fvm flutter test --no-pub test/emby_track_application_test.dart test/emby_external_subtitle_selection_test.dart`

Expected: FAIL because current Emby loader downloads every external subtitle and auto-selects one.

- [ ] **Step 3: Implement the three application modes**

```dart
enum EmbyExternalSubtitleActionKind { followDefault, disabled, select }

class EmbyExternalSubtitleAction {
  const EmbyExternalSubtitleAction.followDefault()
      : kind = EmbyExternalSubtitleActionKind.followDefault,
        streamIndex = null,
        codec = null,
        fingerprint = null;
  const EmbyExternalSubtitleAction.disabled()
      : kind = EmbyExternalSubtitleActionKind.disabled,
        streamIndex = null,
        codec = null,
        fingerprint = null;
  const EmbyExternalSubtitleAction.select({
    required int streamIndex,
    required String codec,
    required EmbyTrackFingerprint fingerprint,
  })  : kind = EmbyExternalSubtitleActionKind.select,
        streamIndex = streamIndex,
        codec = codec,
        fingerprint = fingerprint;
  final EmbyExternalSubtitleActionKind kind;
  final int? streamIndex;
  final String? codec;
  final EmbyTrackFingerprint? fingerprint;
}

class EmbyNativeTrackSelection {
  const EmbyNativeTrackSelection({
    this.audioIndex,
    this.subtitleIndex,
    required this.disableSubtitles,
    required this.externalSubtitle,
  });
  final int? audioIndex;
  final int? subtitleIndex;
  final bool disableSubtitles;
  final EmbyExternalSubtitleAction externalSubtitle;
}
```

After player preparation, direct play maps fingerprints against `player.mediaInfo.audio` and `.subtitle`, then sets `player.activeAudioTracks` / `player.activeSubtitleTracks`. Change `_loadEmbyExternalSubtitles` to accept the resolved decision. `disabled` clears the subtitle manager and returns; `select` downloads and activates one matching track for the current `mediaSourceId`; `followDefault` retains current default-selection behavior. Normalize a selected external subtitle's codec to lowercase and use `srt` when Emby omits it, so the existing subtitle endpoint can return a text stream. Do not change `_loadJellyfinExternalSubtitles`.

- [ ] **Gate: Execute the mandatory implementation gate**

- [ ] **Step 4: Run tests and verify GREEN**

Run: `fvm flutter test --no-pub test/emby_track_application_test.dart test/emby_external_subtitle_selection_test.dart test/emby_media_source_selection_test.dart`

Expected: PASS for transcoding indexes, direct embedded tracks, exact external track and subtitle off.

- [ ] **Gate: Execute the mandatory refactor gate**

- [ ] **Step 5: Review and commit**

```bash
git add lib/services/emby_track_application.dart lib/utils/video_player_state/video_player_state_streaming.dart lib/utils/video_player_state/video_player_state_player_setup.dart test/emby_track_application_test.dart test/emby_external_subtitle_selection_test.dart
git commit -m "feat: apply Emby track preferences during playback"
```

### Task 8: Share Preferences with Existing Player Menus

**Files:**
- Create: `lib/services/emby_player_menu_selection.dart`
- Modify: `lib/themes/nipaplay/widgets/jellyfin_quality_menu.dart`
- Modify: `lib/themes/nipaplay/widgets/audio_tracks_menu.dart`
- Modify: `lib/themes/nipaplay/widgets/subtitle_tracks_menu.dart`
- Modify: `lib/themes/cupertino/widgets/player_menu/cupertino_jellyfin_quality_pane.dart`
- Modify: `lib/themes/cupertino/widgets/player_menu/cupertino_audio_tracks_pane.dart`
- Modify: `lib/themes/cupertino/widgets/player_menu/cupertino_subtitle_tracks_pane.dart`
- Modify: `lib/utils/video_player_state/video_player_state_streaming.dart`
- Test: `test/emby_player_menu_preference_test.dart`
- Test: `test/emby_jellyfin_isolation_test.dart`

**Interfaces:**
- Consumes: current Emby episode ID, `PlaybackDetailContext.sourceKey`, selected source/track descriptor and shared Store.
- Produces:
  - `EmbyTrackPreference preferenceForEmbyServerAudio(EmbyMediaSourceDescriptor source, int streamIndex)`
  - `EmbyTrackPreference preferenceForEmbyServerSubtitle(EmbyMediaSourceDescriptor source, int streamIndex)`
  - `EmbyTrackPreference preferenceForEmbyNativeAudio(PlayerAudioStreamInfo track)`
  - `EmbyTrackPreference preferenceForEmbyNativeSubtitle(PlayerSubtitleStreamInfo track)`
  - `Future<EmbyResolvedTrackBundle> resolveEmbyTracksForSource({required EmbySelectionContext? context, required EmbyMediaSourceDescriptor currentSource, required EmbyMediaPreferenceStore store, required EmbyMediaSelectionResolver resolver})`
  - `Future<bool> persistCurrentEmbyManualPatch({required EmbyMediaSourceDescriptor currentSource, required EmbyManualSelectionPatch patch})`

- [ ] **Step 1: Write failing menu persistence and isolation tests**

```dart
test('extracts the series id from the current Emby detail context', () {
  expect(embySeriesIdFromSourceKey('emby:series-9:season-2'), 'series-9');
  expect(embySeriesIdFromSourceKey('jellyfin:series-9:season-2'), isNull);
});

test('successful Emby menu selection writes shared layers once', () async {
  await harness.selectAudio(embyAudioTrack);
  expect(storeWrites, 1);
  expect(lastWrite.context.episodeId, 'episode-1');
  expect(lastWrite.context.seriesId, 'series-9');
  expect(lastWrite.patch.audio?.fingerprint, embyAudioTrack.fingerprint);
  expect(lastWrite.patch.source, isNull);
  expect(lastWrite.patch.subtitle, isNull);
});

test('adapts real server and native menu track shapes centrally', () {
  final source = describeEmbyMediaSource(playbackSourceWithServerTracks, ordinal: 0);
  final serverAudio = preferenceForEmbyServerAudio(source, 3);
  expect(serverAudio.sourceIndex, 3);
  expect(serverAudio.mediaSourceId, source.source.id);

  final nativeAudio = preferenceForEmbyNativeAudio(playerAudioStreamInfo);
  expect(nativeAudio.fingerprint?.language, playerAudioStreamInfo.language);
  expect(nativeAudio.sourceIndex, isNull);
  expect(nativeAudio.mediaSourceId, isNull);

  final serverSubtitle = preferenceForEmbyServerSubtitle(source, 4);
  expect(serverSubtitle.sourceIndex, 4);
  expect(serverSubtitle.mediaSourceId, source.source.id);
  expect(serverSubtitle.fingerprint?.isExternal, isTrue);

  final nativeSubtitle = preferenceForEmbyNativeSubtitle(playerSubtitleStreamInfo);
  expect(nativeSubtitle.fingerprint?.language, playerSubtitleStreamInfo.language);
  expect(nativeSubtitle.sourceIndex, isNull);
  expect(nativeSubtitle.mediaSourceId, isNull);
});

test('source menu resolves and reloads with the new source bundle', () async {
  await harness.selectSource(sourceB);
  expect(trackResolverSourceIds, ['source-b']);
  expect(harness.reloadTrackBundle, same(sourceBTracks));
});

test('source and subtitle menus patch only their own dimensions', () async {
  await harness.selectSource(sourceB);
  expect(lastWrite.patch.source, same(sourceB));
  expect(lastWrite.patch.audio, isNull);
  expect(lastWrite.patch.subtitle, isNull);

  await harness.disableSubtitles();
  expect(lastWrite.patch.source, isNull);
  expect(lastWrite.patch.audio, isNull);
  expect(lastWrite.patch.subtitle?.mode, EmbyTrackPreferenceMode.disabled);

  await harness.selectSubtitle(serverSubtitleTrack);
  expect(lastWrite.patch.source, isNull);
  expect(lastWrite.patch.audio, isNull);
  expect(lastWrite.patch.subtitle?.sourceIndex, serverSubtitleTrack.index);
  expect(lastWrite.patch.subtitle?.mediaSourceId, sourceB.source.id);
});

test('failed Emby reload never persists a menu patch', () async {
  reloadError = StateError('reload');
  await expectLater(harness.selectAudio(embyAudioTrack), throwsStateError);
  expect(storeWrites, 0);
});

test('Jellyfin menu path never reads or writes Emby preference store', () async {
  await harness.selectJellyfinQuality();
  expect(embyStoreReads, 0);
  expect(embyStoreWrites, 0);
});

test('missing Emby identity skips persistence without blocking the switch', () async {
  identityContext = null;
  final switched = await harness.selectAudio(embyAudioTrack);
  expect(switched, isTrue);
  expect(storeReads, 0);
  expect(storeWrites, 0);
  expect(lastPersistResult, isFalse);
  expect(harness.reloadTrackBundle, defaultSourceTracks);
});
```

- [ ] **Gate: Execute the mandatory test gate and wait for user approval**

- [ ] **Step 2: Run tests and verify RED**

Run: `fvm flutter test --no-pub test/emby_player_menu_preference_test.dart test/emby_jellyfin_isolation_test.dart`

Expected: FAIL because existing menus only update in-memory raw indexes.

- [ ] **Step 3: Persist only after successful Emby changes**

```dart
String? embySeriesIdFromSourceKey(String? sourceKey) {
  final parts = sourceKey?.split(':');
  return parts != null && parts.length >= 3 && parts.first == 'emby' ? parts[1] : null;
}
```

Implement the shared adapter service so UI files only pass a selected stream or native player track; language/title/codec/channel normalization stays outside widgets. `resolveEmbyTracksForSource` uses empty layers without Store access when context is null; otherwise it loads layers, runs the shared Resolver against a one-source list, and returns that candidate's bundle before `reloadCurrentEmbyStream` is called. Use one `VideoPlayerState` method to build account/series/episode context and forward a field-level patch after reload/application succeeds. Source selection sends only `patch.source`, audio selection only `patch.audio`, and subtitle/off selection only `patch.subtitle`; `currentSource` supplies Store context without changing untouched dimensions. If identity context is null, let the successful menu switch stand, skip Store access and return `false` from persistence. Keep the current in-memory index maps as transient playback state; they are not the inheritance store. Do not import the Emby Store in Jellyfin-only branches.

- [ ] **Gate: Execute the mandatory implementation gate**

- [ ] **Step 4: Run tests and verify GREEN**

Run: `fvm flutter test --no-pub test/emby_player_menu_preference_test.dart test/emby_jellyfin_isolation_test.dart test/emby_media_source_selection_test.dart`

Expected: PASS on desktop and Cupertino menu contracts, with Jellyfin Store calls remaining zero.

- [ ] **Gate: Execute the mandatory refactor gate**

- [ ] **Step 5: Review and commit**

```bash
git add lib/services/emby_player_menu_selection.dart lib/themes/nipaplay/widgets/jellyfin_quality_menu.dart lib/themes/nipaplay/widgets/audio_tracks_menu.dart lib/themes/nipaplay/widgets/subtitle_tracks_menu.dart lib/themes/cupertino/widgets/player_menu/cupertino_jellyfin_quality_pane.dart lib/themes/cupertino/widgets/player_menu/cupertino_audio_tracks_pane.dart lib/themes/cupertino/widgets/player_menu/cupertino_subtitle_tracks_pane.dart lib/utils/video_player_state/video_player_state_streaming.dart test/emby_player_menu_preference_test.dart test/emby_jellyfin_isolation_test.dart
git commit -m "feat: remember Emby player menu selections"
```

## Final Verification

- [ ] Run all feature tests:

```bash
fvm flutter test --no-pub test/emby_media_description_test.dart test/emby_release_name_parser_test.dart test/emby_media_selection_resolver_test.dart test/emby_media_preference_store_test.dart test/emby_media_source_catalog_test.dart test/emby_media_selection_controller_test.dart test/emby_media_selection_panel_test.dart test/emby_media_selection_entry_policy_test.dart test/emby_media_source_selection_test.dart test/emby_track_application_test.dart test/emby_external_subtitle_selection_test.dart test/emby_player_menu_preference_test.dart test/emby_jellyfin_isolation_test.dart
```

- [ ] Run analyzer on touched production paths:

```bash
fvm flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings lib/models/emby_media_selection.dart lib/models/media_server_playback.dart lib/services/emby_release_name_parser.dart lib/services/emby_media_selection_resolver.dart lib/services/emby_media_preference_store.dart lib/services/emby_media_source_catalog.dart lib/services/emby_media_selection_controller.dart lib/services/emby_track_application.dart lib/services/emby_player_menu_selection.dart lib/services/emby_service.dart lib/services/emby_media_source_selection.dart lib/widgets/emby_media_source_selector.dart lib/themes/nipaplay/widgets/emby_media_selection_dialog.dart lib/themes/cupertino/widgets/emby_media_selection_sheet.dart lib/themes/nipaplay/widgets/jellyfin_quality_menu.dart lib/themes/nipaplay/widgets/audio_tracks_menu.dart lib/themes/nipaplay/widgets/subtitle_tracks_menu.dart lib/themes/cupertino/widgets/player_menu/cupertino_jellyfin_quality_pane.dart lib/themes/cupertino/widgets/player_menu/cupertino_audio_tracks_pane.dart lib/themes/cupertino/widgets/player_menu/cupertino_subtitle_tracks_pane.dart lib/pages/media_server_detail_page.dart lib/utils/video_player_state.dart lib/utils/video_player_state/video_player_state_streaming.dart lib/utils/video_player_state/video_player_state_player_setup.dart
```

- [ ] Measure coverage for all new and changed feature paths and confirm new production code line coverage is at least 80%:

```bash
fvm flutter test --no-pub --coverage test/emby_media_description_test.dart test/emby_release_name_parser_test.dart test/emby_media_selection_resolver_test.dart test/emby_media_preference_store_test.dart test/emby_media_source_catalog_test.dart test/emby_media_selection_controller_test.dart test/emby_media_selection_panel_test.dart test/emby_media_selection_entry_policy_test.dart test/emby_media_source_selection_test.dart test/emby_track_application_test.dart test/emby_external_subtitle_selection_test.dart test/emby_player_menu_preference_test.dart test/emby_jellyfin_isolation_test.dart
```

- [ ] Fail verification when coverage of added executable lines is below 80%:

```bash
python -c '
from pathlib import Path
import re
import subprocess
import sys

diff = subprocess.run(
    ["git", "diff", "--unified=0", "main...HEAD", "--", "lib"],
    check=True,
    capture_output=True,
    text=True,
    encoding="utf-8",
    errors="replace",
).stdout
added = {}
current = None
for line in diff.splitlines():
    if line.startswith("+++ b/"):
        current = line[6:].replace("\\", "/")
    elif current is not None and line.startswith("@@"):
        match = re.search(r"\+(\d+)(?:,(\d+))?", line)
        if match and current.endswith(".dart"):
            start = int(match.group(1))
            count = int(match.group(2) or "1")
            if count > 0:
                added.setdefault(current, set()).update(range(start, start + count))

covered = 0
total = 0
current = None
seen = set()
root = Path.cwd().resolve()
for line in Path("coverage/lcov.info").read_text(encoding="utf-8").splitlines():
    if line.startswith("SF:"):
        source = Path(line[3:])
        absolute = source.resolve() if source.is_absolute() else (root / source).resolve()
        try:
            relative = absolute.relative_to(root).as_posix()
        except ValueError:
            relative = ""
        current = relative if relative in added else None
        if current is not None:
            seen.add(current)
    elif current is not None and line.startswith("DA:"):
        line_number, hits = map(int, line[3:].split(",")[:2])
        if line_number in added[current]:
            total += 1
            covered += hits > 0

missing = sorted(set(added) - seen)
if missing:
    raise SystemExit("Added production files absent from lcov.info: " + ", ".join(missing))
if total == 0:
    raise SystemExit("No added executable lines were found in lcov.info")
percentage = covered * 100 / total
print(f"Added-line coverage: {covered}/{total} = {percentage:.2f}%")
sys.exit(0 if percentage >= 80 else 1)
'
```

- [ ] Verify formatting for every touched Dart file:

```bash
dart format --output=none --set-exit-if-changed lib test
```

- [ ] Run platform smoke builds without modifying workflows:

```bash
fvm flutter build windows --debug --no-pub
fvm flutter build ios --debug --no-codesign --no-pub
```

Run the Windows command on Windows and the iOS command on a macOS runner.

- [ ] Confirm the final diff contains no Action, UA, proxy, Android, TV or unrelated Jellyfin changes:

```bash
git diff --name-only main...HEAD
git diff --check main...HEAD
```
