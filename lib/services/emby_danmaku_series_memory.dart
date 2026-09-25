import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Emby 弹幕"按季记住匹配"。
///
/// 用户在某一季里明确选过一次弹弹play 的番剧（和集）后，播放这一季的其他集
/// 时按集号偏移推算对应的弹幕剧集，不必每集重新匹配。只记用户的明确选择；
/// 自动搜索、预匹配、哈希得到的结果都不记，免得把猜错的结果传给后面的集。

const String embyDanmakuSeriesMemoryPrefsKey = 'emby_danmaku_series_memory_v1';
const int _schemaVersion = 1;
const int _maxEntries = 500;

@immutable
class EmbyDanmakuSeriesMemoryRecord {
  const EmbyDanmakuSeriesMemoryRecord({
    required this.animeId,
    required this.animeTitle,
    required this.anchorIndex,
    this.anchorEpisodeId,
    this.anchorEpisodeNumber,
    required this.updatedAt,
  });

  final int animeId;
  final String animeTitle;

  /// 做出选择的那一集在 Emby 里的集号（IndexNumber）。
  final int anchorIndex;

  /// 用户明确选中的弹弹play 剧集 ID；只选了番剧时为 null。
  final int? anchorEpisodeId;

  /// 锚点在弹弹play 里的集号（如 "4"、"S1"）。用来在剧集列表里找不到
  /// [anchorEpisodeId] 时兜底；只选了番剧时就是 Emby 集号本身。
  final String? anchorEpisodeNumber;

  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'animeId': animeId,
        'animeTitle': animeTitle,
        'anchorIndex': anchorIndex,
        if (anchorEpisodeId != null) 'anchorEpisodeId': anchorEpisodeId,
        if (anchorEpisodeNumber != null)
          'anchorEpisodeNumber': anchorEpisodeNumber,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  static EmbyDanmakuSeriesMemoryRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final animeId = _asInt(json['animeId']);
    final anchorIndex = _asInt(json['anchorIndex']);
    final updatedAt = DateTime.tryParse('${json['updatedAt']}');
    if (animeId == null || animeId <= 0 || anchorIndex == null) return null;
    return EmbyDanmakuSeriesMemoryRecord(
      animeId: animeId,
      animeTitle: json['animeTitle']?.toString() ?? '',
      anchorIndex: anchorIndex,
      anchorEpisodeId: _asInt(json['anchorEpisodeId']),
      anchorEpisodeNumber: json['anchorEpisodeNumber']?.toString(),
      updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// 记忆的键：账号 + 剧 + 季。
///
/// 没有账号或剧集 ID 时不记；电影的 SeriesId 为空或就是自身，也不记。
/// 没有 SeasonId 时按季号区分，第 0 季（特别篇）自成一个键。
String? embyDanmakuMemoryKey({
  required String? accountKey,
  required String itemId,
  required String? seriesId,
  required String? seasonId,
  required int? parentIndexNumber,
}) {
  final account = accountKey?.trim() ?? '';
  final series = seriesId?.trim() ?? '';
  if (account.isEmpty || series.isEmpty || series == itemId.trim()) {
    return null;
  }
  final season = seasonId?.trim() ?? '';
  final seasonKey = season.isNotEmpty
      ? season
      : (parentIndexNumber != null ? 's$parentIndexNumber' : '-');
  return '$account|$series|$seasonKey';
}

/// 把弹弹play 的集号拆成前缀和数字：`"4"`→("", 4)，`"S1"`→("S", 1)。
/// 不是"字母前缀 + 数字"的（如 "OVA"）返回 null。
@visibleForTesting
({String prefix, int number})? parseDandanplayEpisodeNumber(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  final match = RegExp(r'^([A-Za-z]*)(\d+)$').firstMatch(text);
  if (match == null) return null;
  final number = int.tryParse(match.group(2)!);
  if (number == null) return null;
  return (prefix: match.group(1)!.toUpperCase(), number: number);
}

/// 按 [record] 推算 Emby 第 [targetIndex] 集对应的弹弹play 剧集。
///
/// 目标集号 = 锚点集号 + (targetIndex − 锚点的 Emby 集号)，只在同一前缀下
/// 恰好命中一集时返回；推不出、越界或有重复时返回 null，交给原有流程。
/// 不按 episodeId 做算术：弹弹play 的剧集编号并不总是连续的。
Map<String, dynamic>? mapEpisodeFromMemory({
  required List<Map<String, dynamic>> episodes,
  required EmbyDanmakuSeriesMemoryRecord record,
  required int targetIndex,
}) {
  Object? anchorNumberRaw = record.anchorEpisodeNumber;
  final anchorId = record.anchorEpisodeId;
  if (anchorId != null) {
    for (final ep in episodes) {
      if (_asInt(ep['episodeId']) == anchorId) {
        anchorNumberRaw = ep['episodeNumber'];
        break;
      }
    }
  }
  final anchor = parseDandanplayEpisodeNumber(anchorNumberRaw);
  if (anchor == null) return null;

  final wanted = anchor.number + (targetIndex - record.anchorIndex);
  if (wanted <= 0) return null;

  Map<String, dynamic>? found;
  for (final ep in episodes) {
    final parsed = parseDandanplayEpisodeNumber(ep['episodeNumber']);
    if (parsed == null ||
        parsed.prefix != anchor.prefix ||
        parsed.number != wanted) {
      continue;
    }
    if (found != null) return null;
    found = ep;
  }
  return found;
}

/// 记忆的读写，存在 SharedPreferences 里，最多 [_maxEntries] 条。
class EmbyDanmakuSeriesMemory {
  EmbyDanmakuSeriesMemory._();

  static final EmbyDanmakuSeriesMemory instance = EmbyDanmakuSeriesMemory._();

  /// 每次写入或删除后加一，界面据此刷新显示。
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<EmbyDanmakuSeriesMemoryRecord?> read(String key) async {
    final entries = await _readAll();
    return entries[key];
  }

  Future<void> write(String key, EmbyDanmakuSeriesMemoryRecord record) async {
    final entries = await _readAll();
    entries[key] = record;
    if (entries.length > _maxEntries) {
      final oldestFirst = entries.entries.toList()
        ..sort((a, b) => a.value.updatedAt.compareTo(b.value.updatedAt));
      for (final entry in oldestFirst.take(entries.length - _maxEntries)) {
        entries.remove(entry.key);
      }
    }
    await _writeAll(entries);
    revision.value++;
  }

  Future<void> remove(String key) async {
    final entries = await _readAll();
    if (entries.remove(key) != null) {
      await _writeAll(entries);
      revision.value++;
    }
  }

  Future<Map<String, EmbyDanmakuSeriesMemoryRecord>> _readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(embyDanmakuSeriesMemoryPrefsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      final entries = decoded is Map ? decoded['entries'] : null;
      if (entries is! Map) return {};
      final result = <String, EmbyDanmakuSeriesMemoryRecord>{};
      entries.forEach((key, value) {
        final record = EmbyDanmakuSeriesMemoryRecord.fromJson(value);
        if (key is String && record != null) result[key] = record;
      });
      return result;
    } catch (e) {
      debugPrint('[弹幕记忆] 读取失败，按空处理: $e');
      return {};
    }
  }

  Future<void> _writeAll(Map<String, EmbyDanmakuSeriesMemoryRecord> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      embyDanmakuSeriesMemoryPrefsKey,
      jsonEncode({
        'version': _schemaVersion,
        'entries': {
          for (final entry in entries.entries) entry.key: entry.value.toJson(),
        },
      }),
    );
  }
}
