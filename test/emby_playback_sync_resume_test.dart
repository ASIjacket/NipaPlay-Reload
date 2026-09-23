import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/emby_playback_sync_service.dart';

void main() {
  group('hasEmbyResumeProgress', () {
    test('accepts an in-progress item reported without PlayCount or '
        'LastPlayedDate', () {
      // Captured from a real Emby server: an episode watched to 31% comes back
      // with PlayCount 0 and no LastPlayedDate at all.
      expect(
        hasEmbyResumeProgress(<String, dynamic>{
          'PlayedPercentage': 31.743341377914103,
          'PlaybackPositionTicks': 4542870000,
          'PlayCount': 0,
          'IsFavorite': false,
          'Played': false,
        }),
        isTrue,
      );
    });

    test('rejects an item the server has no position for', () {
      expect(
        hasEmbyResumeProgress(<String, dynamic>{
          'PlaybackPositionTicks': 0,
          'PlayCount': 0,
          'IsFavorite': false,
          'Played': false,
        }),
        isFalse,
      );
      expect(hasEmbyResumeProgress(<String, dynamic>{}), isFalse);
    });

    test('still accepts what the old check accepted', () {
      // Servers that report PlayCount and LastPlayedDate worked before; a
      // finished item there has position 0 and must keep going through the
      // timestamp comparison exactly as it used to.
      expect(
        hasEmbyResumeProgress(<String, dynamic>{
          'PlaybackPositionTicks': 0,
          'PlayCount': 1,
          'LastPlayedDate': '2026-09-10T12:00:00.0000000Z',
          'Played': true,
        }),
        isTrue,
      );
    });
  });

  group('preferEmbyServerResume', () {
    final local = DateTime.utc(2026, 9, 10, 12);

    test('keeps the newer side when both have timestamps', () {
      // Positions are irrelevant here: this is the behaviour servers that
      // report LastPlayedDate already had.
      expect(
        preferEmbyServerResume(
          serverLastPlayedUtc: local.add(const Duration(minutes: 1)),
          localLastWatchUtc: local,
          serverPositionMs: 1000,
          localPositionMs: 900000,
        ),
        isTrue,
      );
      expect(
        preferEmbyServerResume(
          serverLastPlayedUtc: local.subtract(const Duration(minutes: 1)),
          localLastWatchUtc: local,
          serverPositionMs: 900000,
          localPositionMs: 1000,
        ),
        isFalse,
      );
    });

    test('without a server timestamp picks up progress made elsewhere', () {
      // Watched to 7.5 min on another device, never opened here before.
      expect(
        preferEmbyServerResume(
          serverLastPlayedUtc: null,
          localLastWatchUtc: local,
          serverPositionMs: 454287,
          localPositionMs: 0,
        ),
        isTrue,
      );
    });

    test('without a server timestamp never rewinds local progress', () {
      // Local playback got further than the server knows about, e.g. because
      // progress reports did not reach it. Using the server would rewind.
      expect(
        preferEmbyServerResume(
          serverLastPlayedUtc: null,
          localLastWatchUtc: local,
          serverPositionMs: 120000,
          localPositionMs: 290000,
        ),
        isFalse,
      );
      expect(
        preferEmbyServerResume(
          serverLastPlayedUtc: null,
          localLastWatchUtc: local,
          serverPositionMs: 290000,
          localPositionMs: 290000,
        ),
        isFalse,
      );
    });
  });

  group('shouldUploadEmbyProgress', () {
    const now = 1000000;

    test('never uploads while paused', () {
      // A progress report always says IsPaused=false; the paused state is
      // reported separately by reportPlaybackPaused.
      expect(
        shouldUploadEmbyProgress(
          isPlaying: false,
          nowMs: now,
          lastUploadMs: 0,
        ),
        isFalse,
      );
    });

    test('uploads while playing once the interval has passed', () {
      expect(
        shouldUploadEmbyProgress(
          isPlaying: true,
          nowMs: now,
          lastUploadMs: 0,
        ),
        isTrue,
      );
      expect(
        shouldUploadEmbyProgress(
          isPlaying: true,
          nowMs: now,
          lastUploadMs: now - 5000,
        ),
        isTrue,
      );
    });

    test('throttles uploads that come in faster than the interval', () {
      expect(
        shouldUploadEmbyProgress(
          isPlaying: true,
          nowMs: now,
          lastUploadMs: now - 4999,
        ),
        isFalse,
      );
    });

    test('does not depend on the position landing near a whole second', () {
      // The old gate required position % 1000 < 100, read after several
      // awaits. The replacement takes no position at all, so a report that
      // arrives 150 ms into a second is still sent.
      expect(
        shouldUploadEmbyProgress(
          isPlaying: true,
          nowMs: now + 150,
          lastUploadMs: now - 10000,
        ),
        isTrue,
      );
    });
  });
}
