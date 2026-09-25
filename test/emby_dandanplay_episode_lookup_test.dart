import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/emby_dandanplay_matcher.dart';

void main() {
  // Same shape as the entries _getAnimeEpisodes builds.
  final episodes = <Map<String, dynamic>>[
    {'episodeId': 195940001, 'episodeTitle': '第1话', 'episodeIndex': 1},
    {'episodeId': 195940002, 'episodeTitle': '第2话', 'episodeIndex': 2},
    {'episodeId': 195940005, 'episodeTitle': '第5话', 'episodeIndex': 5},
  ];

  test('finds the episode with the Emby index number', () {
    // Before the fix every lookup missed and fell back to episode 1.
    expect(findEpisodeByIndex(episodes, 5)?['episodeId'], 195940005);
    expect(findEpisodeByIndex(episodes, 2)?['episodeId'], 195940002);
  });

  test('returns null when the anime has no such episode', () {
    expect(findEpisodeByIndex(episodes, 13), isNull);
    expect(findEpisodeByIndex(const [], 1), isNull);
  });
}
