import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nipaplay/services/emby_dandanplay_matcher.dart';
import 'package:nipaplay/services/emby_danmaku_series_memory.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';

/// 播放器菜单里的 Emby"本季弹幕记忆"操作，两套主题的弹幕菜单共用。

const String _embyScheme = 'emby://';

String? _embyItemId(String? videoPath) {
  if (videoPath == null || !videoPath.startsWith(_embyScheme)) return null;
  final itemId = videoPath.substring(_embyScheme.length).trim();
  return itemId.isEmpty ? null : itemId;
}

/// 手动匹配 Emby 弹幕后调用：记住本季选择，并提示后续集会沿用；提示里的
/// "仅本集"撤回这次记忆，只改当前这一集。
///
/// 返回是否已经弹出了提示（不是 Emby 剧集、或记不住时为 false）。
Future<bool> rememberEmbyManualDanmakuMatch(
  BuildContext context, {
  required String videoPath,
  required String animeId,
  required String episodeId,
  String? animeTitle,
}) async {
  final itemId = _embyItemId(videoPath);
  final parsedAnimeId = int.tryParse(animeId);
  final parsedEpisodeId = int.tryParse(episodeId);
  if (itemId == null || parsedAnimeId == null || parsedEpisodeId == null) {
    return false;
  }
  final title = animeTitle?.trim() ?? '';
  final matcher = EmbyDandanplayMatcher.instance;
  final undo = await matcher.rememberManualMatch(
    itemId: itemId,
    animeId: parsedAnimeId,
    animeTitle: title.isNotEmpty ? title : '所选番剧',
    episodeId: parsedEpisodeId,
  );
  if (undo == null || !context.mounted) return false;
  BlurSnackBar.show(
    context,
    '已记住：本季后续集沿用《${undo.animeTitle}》',
    actionText: '仅本集',
    onAction: () => unawaited(matcher.undoRememberedMatch(undo)),
  );
  return true;
}

/// 当前播放的 Emby 剧集所在季记住的弹幕匹配；不是 Emby 或没有记忆时为 null。
Future<EmbyDanmakuSeriesMemoryRecord?> loadEmbySeriesDanmakuMemory(
  String? videoPath,
) async {
  final itemId = _embyItemId(videoPath);
  if (itemId == null) return null;
  return EmbyDandanplayMatcher.instance.seriesMemoryForItem(itemId);
}

/// 忘记当前 Emby 剧集所在季的弹幕匹配。
Future<void> forgetEmbySeriesDanmakuMemory(
  BuildContext context,
  String? videoPath,
) async {
  final itemId = _embyItemId(videoPath);
  if (itemId == null) return;
  await EmbyDandanplayMatcher.instance.forgetSeriesMemoryForItem(itemId);
  if (context.mounted) {
    BlurSnackBar.show(context, '已忘记本季匹配，之后的集会重新匹配');
  }
}
