import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/remote_media_fetcher.dart';

void main() {
  test('abort stops a download that the server never answers', () async {
    // A stalled cloud-drive link: the connection opens but no response comes.
    // Without abort the fetch would sit there for the 20 s request timeout
    // while the player is already trying to open the same link.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((_) {});

    final abort = Completer<void>();
    Timer(const Duration(milliseconds: 100), abort.complete);
    final stopwatch = Stopwatch()..start();

    await expectLater(
      RemoteMediaFetcher.fetchHead(
        Uri.parse('http://${server.address.address}:${server.port}/ep.mkv'),
        userAgent: 'VLC/3.0.20 LibVLC/3.0.20',
        abort: abort.future,
      ),
      throwsA(isA<Exception>()),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
