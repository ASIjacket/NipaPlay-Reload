import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/remote_media_fetcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('remote media hashing sends the sanitized player User-Agent', () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.customPlayerUA: '  PlayerClient/5.0\r\nInjected  ',
    });
    await PlayerFactory.initialize();
    addTearDown(() async {
      await PlayerFactory.saveCustomPlayerUA('');
      SharedPreferences.setMockInitialValues({});
    });
    final userAgents = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      userAgents.add(request.headers.value(HttpHeaders.userAgentHeader));
      if (request.method == 'HEAD') {
        request.response.headers.set(HttpHeaders.contentLengthHeader, '6');
      } else {
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-5/6')
          ..add([1, 2, 3, 4, 5, 6]);
      }
      await request.response.close();
    });

    final result = await RemoteMediaFetcher.fetchHead(
      Uri.parse('http://${server.address.address}:${server.port}/episode.mkv'),
    );

    expect(result.fileSize, 6);
    expect(result.bytesHashed, 6);
    expect(userAgents, hasLength(2));
    expect(userAgents, everyElement('PlayerClient/5.0Injected'));
  });

  test('keeps the User-Agent after the server redirects', () async {
    // Media servers commonly 302 the stream to a cloud-drive link that only
    // accepts the player's UA. dart:io used to fall back to its default UA
    // (NipaPlay/1.0) on the redirected request, so the link answered 403.
    const userAgent = 'VLC/3.0.20 LibVLC/3.0.20';
    final finalUserAgents = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final response = request.response;
      if (request.uri.path == '/emby/Videos/1/stream') {
        response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/drive/episode.mkv');
      } else {
        final ua = request.headers.value(HttpHeaders.userAgentHeader);
        finalUserAgents.add(ua);
        if (ua != userAgent) {
          response.statusCode = HttpStatus.forbidden;
        } else if (request.method == 'HEAD') {
          response.headers.set(HttpHeaders.contentLengthHeader, '6');
        } else {
          response
            ..statusCode = HttpStatus.partialContent
            ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-5/6')
            ..add([1, 2, 3, 4, 5, 6]);
        }
      }
      await response.close();
    });

    final result = await RemoteMediaFetcher.fetchHead(
      Uri.parse(
        'http://${server.address.address}:${server.port}/emby/Videos/1/stream',
      ),
      userAgent: userAgent,
    );

    expect(result.bytesHashed, 6);
    expect(finalUserAgents, hasLength(2));
    expect(finalUserAgents, everyElement(userAgent));
  });
}
