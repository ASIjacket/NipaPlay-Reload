import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/emby_danmaku_series_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _ep(int id, String number) =>
    {'episodeId': id, 'episodeTitle': '第$number话', 'episodeNumber': number};

EmbyDanmakuSeriesMemoryRecord _record({
  required int anchorIndex,
  int? anchorEpisodeId,
  String? anchorEpisodeNumber,
  DateTime? updatedAt,
}) {
  return EmbyDanmakuSeriesMemoryRecord(
    animeId: 19594,
    animeTitle: '圣剑学院的魔剑使',
    anchorIndex: anchorIndex,
    anchorEpisodeId: anchorEpisodeId,
    anchorEpisodeNumber: anchorEpisodeNumber,
    updatedAt: updatedAt ?? DateTime.utc(2026, 9, 24),
  );
}

void main() {
  group('embyDanmakuMemoryKey', () {
    test('combines account, series and season', () {
      expect(
        embyDanmakuMemoryKey(
          accountKey: 'srv:user',
          itemId: '190216',
          seriesId: '190100',
          seasonId: '190101',
          parentIndexNumber: 1,
        ),
        'srv:user|190100|190101',
      );
    });

    test('falls back to the season number, specials get their own key', () {
      expect(
        embyDanmakuMemoryKey(
          accountKey: 'srv:user',
          itemId: '190216',
          seriesId: '190100',
          seasonId: null,
          parentIndexNumber: 0,
        ),
        'srv:user|190100|s0',
      );
    });

    test('does not remember movies or unknown accounts', () {
      expect(
        embyDanmakuMemoryKey(
          accountKey: 'srv:user',
          itemId: '5000',
          seriesId: '5000',
          seasonId: null,
          parentIndexNumber: null,
        ),
        isNull,
      );
      expect(
        embyDanmakuMemoryKey(
          accountKey: 'srv:user',
          itemId: '5000',
          seriesId: null,
          seasonId: null,
          parentIndexNumber: null,
        ),
        isNull,
      );
      expect(
        embyDanmakuMemoryKey(
          accountKey: null,
          itemId: '190216',
          seriesId: '190100',
          seasonId: '190101',
          parentIndexNumber: 1,
        ),
        isNull,
      );
    });
  });

  group('parseDandanplayEpisodeNumber', () {
    test('reads plain and prefixed numbers', () {
      expect(parseDandanplayEpisodeNumber('4'), (prefix: '', number: 4));
      expect(parseDandanplayEpisodeNumber(4), (prefix: '', number: 4));
      expect(parseDandanplayEpisodeNumber('S1'), (prefix: 'S', number: 1));
      expect(parseDandanplayEpisodeNumber('c2'), (prefix: 'C', number: 2));
    });

    test('rejects what cannot be offset', () {
      expect(parseDandanplayEpisodeNumber('OVA'), isNull);
      expect(parseDandanplayEpisodeNumber(''), isNull);
      expect(parseDandanplayEpisodeNumber(null), isNull);
    });
  });

  group('mapEpisodeFromMemory', () {
    final season = [
      for (var n = 1; n <= 12; n++) _ep(195940000 + n, '$n'),
      _ep(195940101, 'S1'),
      _ep(195940102, 'S2'),
    ];

    test('same numbering: picked E4 as 4, so E5 is 5', () {
      final mapped = mapEpisodeFromMemory(
        episodes: season,
        record: _record(anchorIndex: 4, anchorEpisodeId: 195940004),
        targetIndex: 5,
      );
      expect(mapped?['episodeId'], 195940005);
    });

    test('keeps the offset the user chose', () {
      // Emby numbers the second cour 13..24 while dandanplay has 1..12.
      final mapped = mapEpisodeFromMemory(
        episodes: season,
        record: _record(anchorIndex: 13, anchorEpisodeId: 195940001),
        targetIndex: 14,
      );
      expect(mapped?['episodeId'], 195940002);

      final shifted = mapEpisodeFromMemory(
        episodes: season,
        record: _record(anchorIndex: 3, anchorEpisodeId: 195940002),
        targetIndex: 4,
      );
      expect(shifted?['episodeId'], 195940003);
    });

    test('stays within specials', () {
      final mapped = mapEpisodeFromMemory(
        episodes: season,
        record: _record(anchorIndex: 1, anchorEpisodeId: 195940101),
        targetIndex: 2,
      );
      expect(mapped?['episodeId'], 195940102);
    });

    test('anime-only choice maps episode numbers one to one', () {
      final mapped = mapEpisodeFromMemory(
        episodes: season,
        record: _record(anchorIndex: 3, anchorEpisodeNumber: '3'),
        targetIndex: 7,
      );
      expect(mapped?['episodeId'], 195940007);
    });

    test('uses the stored number when the anchor id is not listed', () {
      final mapped = mapEpisodeFromMemory(
        episodes: season,
        record: _record(
          anchorIndex: 4,
          anchorEpisodeId: 999,
          anchorEpisodeNumber: '4',
        ),
        targetIndex: 6,
      );
      expect(mapped?['episodeId'], 195940006);
    });

    test('the anchor episode maps to itself', () {
      final mapped = mapEpisodeFromMemory(
        episodes: season,
        record: _record(anchorIndex: 4, anchorEpisodeId: 195940004),
        targetIndex: 4,
      );
      expect(mapped?['episodeId'], 195940004);
    });

    test('gives up instead of guessing', () {
      final record = _record(anchorIndex: 4, anchorEpisodeId: 195940004);
      // Past the end of the list.
      expect(
        mapEpisodeFromMemory(episodes: season, record: record, targetIndex: 20),
        isNull,
      );
      // Would land before episode 1.
      expect(
        mapEpisodeFromMemory(
          episodes: season,
          record: _record(anchorIndex: 10, anchorEpisodeId: 195940001),
          targetIndex: 5,
        ),
        isNull,
      );
      // Ambiguous list.
      expect(
        mapEpisodeFromMemory(
          episodes: [...season, _ep(195949005, '5')],
          record: record,
          targetIndex: 5,
        ),
        isNull,
      );
      // Anchor that cannot be offset.
      expect(
        mapEpisodeFromMemory(
          episodes: [_ep(1, 'OVA'), _ep(2, '2')],
          record: _record(anchorIndex: 1, anchorEpisodeId: 1),
          targetIndex: 2,
        ),
        isNull,
      );
    });
  });

  group('EmbyDanmakuSeriesMemory store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('writes, overwrites and removes', () async {
      final store = EmbyDanmakuSeriesMemory.instance;
      await store.write('k', _record(anchorIndex: 4, anchorEpisodeId: 195940004));
      expect((await store.read('k'))?.anchorEpisodeId, 195940004);

      await store.write('k', _record(anchorIndex: 5, anchorEpisodeId: 195940006));
      final updated = await store.read('k');
      expect(updated?.anchorIndex, 5);
      expect(updated?.anchorEpisodeId, 195940006);

      await store.remove('k');
      expect(await store.read('k'), isNull);
    });

    test('treats corrupt data as empty', () async {
      SharedPreferences.setMockInitialValues({
        embyDanmakuSeriesMemoryPrefsKey: '{not json',
      });
      expect(await EmbyDanmakuSeriesMemory.instance.read('k'), isNull);
    });

    test('evicts the oldest entries beyond the limit', () async {
      final store = EmbyDanmakuSeriesMemory.instance;
      for (var i = 0; i < 501; i++) {
        await store.write(
          'k$i',
          _record(
            anchorIndex: 1,
            anchorEpisodeId: 195940001,
            updatedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
          ),
        );
      }
      expect(await store.read('k0'), isNull);
      expect(await store.read('k1'), isNotNull);
      expect(await store.read('k500'), isNotNull);
    });
  });
}
