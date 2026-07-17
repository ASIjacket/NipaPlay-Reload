import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/media_server_image_loader.dart';
import 'package:nipaplay/services/media_server_service_base.dart';
import 'package:nipaplay/services/media_server_transport.dart';

void main() {
  test('media-server image detection stays inside the registered base path',
      () {
    setMediaServerBaseUrl('test-emby', 'https://media.example/emby');
    addTearDown(() => setMediaServerBaseUrl('test-emby', null));

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
  });

  test('the default media-server image loader uses the configured transport',
      () async {
    final receivedRequests = <({Uri uri, String? userAgent})>[];
    final expectedBytes = Uint8List.fromList([1, 2, 3, 4]);
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    proxy.listen((request) async {
      receivedRequests.add((
        uri: request.uri,
        userAgent: request.headers.value('user-agent'),
      ));
      request.response
        ..statusCode = HttpStatus.ok
        ..add(expectedBytes);
      await request.response.close();
    });
    MediaServerTransport.setHttpProxyOverride(
      'http://${proxy.address.address}:${proxy.port}',
    );
    addTearDown(MediaServerTransport.clearHttpProxyOverride);
    final savedUserAgent = await MediaServerServiceBase.saveConnectionUserAgent(
      '  EmbyClient/2.0\r\nInjected  ',
    );
    addTearDown(() => MediaServerServiceBase.saveConnectionUserAgent(''));
    final target = Uri.parse(
      'http://media.invalid/emby/Items/library-id/Images/Primary',
    );
    setMediaServerBaseUrl('test-emby', 'http://media.invalid');
    addTearDown(() => setMediaServerBaseUrl('test-emby', null));

    final bytes = await loadNetworkImageBytes(target);

    expect(savedUserAgent, 'EmbyClient/2.0Injected');
    expect(receivedRequests, [
      (uri: target, userAgent: 'EmbyClient/2.0Injected'),
    ]);
    expect(bytes, expectedBytes);
  });
}
