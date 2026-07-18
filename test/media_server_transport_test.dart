@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/services/media_server_image_loader.dart';
import 'package:nipaplay/services/media_server_transport.dart';

void main() {
  test('send omits User-Agent when the platform forbids the header', () async {
    final client = _RecordingClient();
    final transport = MediaServerTransport.fromClient(
      client,
      supportsCustomUserAgentHeader: false,
    );
    addTearDown(transport.close);

    await transport.send(
      http.Request('GET', Uri.parse('http://media.invalid/browser-policy')),
      timeout: const Duration(seconds: 1),
    );

    expect(client.userAgents, [isNull]);
  });

  test('adds the app User-Agent unless the caller already supplied one',
      () async {
    final client = _RecordingClient();
    final transport = MediaServerTransport.fromClient(client);
    addTearDown(transport.close);

    await transport.send(
      http.Request('GET', Uri.parse('http://media.invalid/default')),
      timeout: const Duration(seconds: 1),
    );
    await transport.send(
      http.Request('GET', Uri.parse('http://media.invalid/explicit'))
        ..headers['user-agent'] = 'ExplicitClient/3.0',
      timeout: const Duration(seconds: 1),
    );

    expect(client.userAgents, ['NipaPlay/1.0', 'ExplicitClient/3.0']);
  });

  test('closes its pending client only after a request times out', () async {
    final client = _StallingClient();
    final transport = MediaServerTransport.fromClient(client);
    addTearDown(transport.close);
    final targetUri = Uri.parse('http://media.invalid/slow');

    final responseFuture = transport.send(
      http.Request(
        'GET',
        targetUri,
      ),
      timeout: const Duration(milliseconds: 100),
    );
    expect(client.sentRequests, [('GET', targetUri)]);
    expect(client.isClosed, isFalse);

    await expectLater(
      responseFuture,
      throwsA(isA<TimeoutException>()),
    );
    expect(client.isClosed, isTrue);
    expect(client.closeCount, 1);

    transport.close();
    expect(client.closeCount, 1);
  });

  test('recognizes Emby and Jellyfin item image endpoints', () {
    setMediaServerBaseUrl('test-emby', 'https://server.example/emby');
    setMediaServerBaseUrl('test-jellyfin', 'https://jellyfin.example');
    addTearDown(() {
      setMediaServerBaseUrl('test-emby', null);
      setMediaServerBaseUrl('test-jellyfin', null);
    });
    expect(
      isMediaServerImageUri(
        Uri.parse('https://server.example/emby/Items/42/Images/Primary'),
      ),
      isTrue,
    );
    expect(
      isMediaServerImageUri(
        Uri.parse('https://jellyfin.example/Items/42/Images/Backdrop/0'),
      ),
      isTrue,
    );
  });

  test('does not classify unrelated network images as media-server images', () {
    setMediaServerBaseUrl('test-server', 'https://server.example');
    addTearDown(() => setMediaServerBaseUrl('test-server', null));
    expect(
      isMediaServerImageUri(
        Uri.parse('https://lain.bgm.tv/pic/cover/l/example.jpg'),
      ),
      isFalse,
    );
    expect(
      isMediaServerImageUri(
        Uri.parse('https://example.com/api/items/42/poster.jpg'),
      ),
      isFalse,
    );
    expect(
      isMediaServerImageUri(
        Uri.parse('https://other.example/Items/42/Images/Primary'),
      ),
      isFalse,
    );
  });
}

class _StallingClient extends http.BaseClient {
  bool isClosed = false;
  int closeCount = 0;
  final List<(String, Uri)> sentRequests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sentRequests.add((request.method, request.url));
    return Completer<http.StreamedResponse>().future;
  }

  @override
  void close() {
    isClosed = true;
    closeCount += 1;
  }
}

class _RecordingClient extends http.BaseClient {
  final List<String?> userAgents = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    userAgents.add(request.headers['User-Agent']);
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }
}
