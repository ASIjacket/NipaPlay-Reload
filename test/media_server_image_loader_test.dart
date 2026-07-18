@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/media_server_image_loader.dart';
import 'package:nipaplay/services/media_server_service_base.dart';

void main() {
  test('Emby and Jellyfin server setters register their image base paths', () {
    final emby = EmbyService.instance;
    final jellyfin = JellyfinService.instance;
    emby.serverUrl = 'https://media.example/emby';
    jellyfin.serverUrl = 'https://jellyfin.example/jellyfin';
    addTearDown(() {
      emby.serverUrl = null;
      jellyfin.serverUrl = null;
    });

    expect(
      isMediaServerImageUri(
        Uri.parse(
          'https://media.example/emby/Items/library-id/Images/Primary',
        ),
      ),
      isTrue,
    );
    expect(
      isMediaServerImageUri(
        Uri.parse(
          'https://media.example/other/Items/library-id/Images/Primary',
        ),
      ),
      isFalse,
    );
    expect(
      isMediaServerImageUri(
        Uri.parse(
          'https://jellyfin.example/jellyfin/Items/movie-id/Images/Backdrop',
        ),
      ),
      isTrue,
    );
  });

  test('the default media-server image loader uses the configured transport',
      () async {
    final receivedRequests = <({Uri uri, String? userAgent})>[];
    final expectedBytes = Uint8List.fromList([1, 2, 3, 4]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      receivedRequests.add((
        uri: request.requestedUri,
        userAgent: request.headers.value('user-agent'),
      ));
      request.response
        ..statusCode = HttpStatus.ok
        ..add(expectedBytes);
      await request.response.close();
    });
    final savedUserAgent = await MediaServerServiceBase.saveConnectionUserAgent(
      '  EmbyClient/2.0\r\nInjected  ',
    );
    addTearDown(() => MediaServerServiceBase.saveConnectionUserAgent(''));
    final target = Uri.parse(
      'http://${server.address.address}:${server.port}'
      '/emby/Items/library-id/Images/Primary',
    );
    final emby = EmbyService.instance;
    emby.serverUrl = 'http://${server.address.address}:${server.port}';
    addTearDown(() => emby.serverUrl = null);

    final bytes = await loadNetworkImageBytes(target);

    expect(savedUserAgent, 'EmbyClient/2.0Injected');
    expect(receivedRequests, [
      (uri: target, userAgent: 'EmbyClient/2.0Injected'),
    ]);
    expect(bytes, expectedBytes);
  });

  test('media-server image HEAD validation uses the connection User-Agent',
      () async {
    final receivedRequests = <({String method, Uri uri, String? userAgent})>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final userAgent = request.headers.value(HttpHeaders.userAgentHeader);
      receivedRequests.add((
        method: request.method,
        uri: request.requestedUri,
        userAgent: userAgent,
      ));
      if (request.method == 'HEAD' && userAgent == 'ImageProbe/8.0') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('image', 'png')
          ..contentLength = 512;
      } else {
        request.response.statusCode = HttpStatus.forbidden;
      }
      await request.response.close();
    });

    await MediaServerServiceBase.saveConnectionUserAgent('ImageProbe/8.0');
    addTearDown(() => MediaServerServiceBase.saveConnectionUserAgent(''));
    final emby = EmbyService.instance;
    emby.serverUrl = 'http://${server.address.address}:${server.port}/emby';
    addTearDown(() => emby.serverUrl = null);
    final target = Uri.parse(
      '${emby.serverUrl}/Items/library-id/Images/Primary',
    );

    final valid = await validateMediaServerImageCandidate(
      target,
      timeout: const Duration(seconds: 1),
    );

    expect(valid, isTrue);
    expect(receivedRequests, [
      (method: 'HEAD', uri: target, userAgent: 'ImageProbe/8.0'),
    ]);
  });
}
