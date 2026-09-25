import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/server_history_sync_service.dart';

WatchHistoryItem _item({int? animeId, int? episodeId, int lastPosition = 0}) {
  return WatchHistoryItem(
    filePath: 'emby://190216',
    animeName: '圣剑学院的魔剑使',
    episodeTitle: '废都出现',
    animeId: animeId,
    episodeId: episodeId,
    watchProgress: 0.2,
    lastPosition: lastPosition,
    duration: 1440000,
    lastWatchTime: DateTime.utc(2026, 9, 10, 12),
  );
}

void main() {
  test('keeps a real danmaku match from the local record', () {
    final merged = mergeSyncedHistoryItem(
      incoming: _item(lastPosition: 290000),
      existing: _item(animeId: 19594, episodeId: 195940004),
    );

    expect(merged.animeId, 19594);
    expect(merged.episodeId, 195940004);
    expect(merged.lastPosition, 290000);
  });

  test('drops an episodeId that has no animeId', () {
    // Left behind by the old sync, which stored the Emby episode number (5)
    // as if it were a dandanplay episode id.
    final merged = mergeSyncedHistoryItem(
      incoming: _item(lastPosition: 290000),
      existing: _item(episodeId: 5),
    );

    expect(merged.episodeId, isNull);
    expect(merged.animeId, isNull);
  });

  test('keeps an anime-only match without inventing an episode', () {
    final merged = mergeSyncedHistoryItem(
      incoming: _item(),
      existing: _item(animeId: 19594),
    );

    expect(merged.animeId, 19594);
    expect(merged.episodeId, isNull);
  });
}
