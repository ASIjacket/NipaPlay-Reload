import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/emby_dandanplay_matcher.dart';

void main() {
  const budget = Duration(seconds: 8);
  final hashed = <String, dynamic>{
    'hash': '0123456789abcdef0123456789abcdef',
    'fileName': 'ep05.mkv',
    'fileSize': 734003200,
  };

  test('uses a hash that arrives in time', () async {
    expect(await waitForVideoHash(Future.value(hashed), budget: budget), hashed);
  });

  test('stops waiting after the budget and matching carries on', () async {
    // The old code waited for the whole download to fail: 8-22 s per episode.
    final stuck = Completer<Map<String, dynamic>>();

    final result = await waitForVideoHash(
      stuck.future,
      budget: const Duration(milliseconds: 20),
    );

    expect(result['hash'], '');
    expect(result['fileSize'], 0);
  });

  test('asks to abort the download only when it gives up', () async {
    var gaveUp = 0;
    await waitForVideoHash(
      Future.value(hashed),
      budget: budget,
      onGiveUp: () => gaveUp++,
    );
    expect(gaveUp, 0);

    await waitForVideoHash(
      Completer<Map<String, dynamic>>().future,
      budget: const Duration(milliseconds: 20),
      onGiveUp: () => gaveUp++,
    );
    expect(gaveUp, 1);
  });

  test('a hashing error also yields an empty hash', () async {
    final result = await waitForVideoHash(
      Future<Map<String, dynamic>>.error(Exception('HTTP 403')),
      budget: budget,
    );

    expect(result['hash'], '');
  });
}
