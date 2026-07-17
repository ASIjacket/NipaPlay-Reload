import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/services/media_server_image_loader.dart';
import 'package:nipaplay/services/media_server_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

  test('routes media-server requests through the configured HTTP proxy',
      () async {
    final proxyReceivedRequest = Completer<({String method, Uri uri})>();
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));

    proxy.listen((request) async {
      if (!proxyReceivedRequest.isCompleted) {
        proxyReceivedRequest.complete((
          method: request.method,
          uri: request.uri,
        ));
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.text
        ..write('proxied');
      await request.response.close();
    });

    final targetUri = Uri.parse(
      'http://media.invalid/emby/Items/42/Images/Primary?maxWidth=600',
    );
    final transport = MediaServerTransport(
      httpProxy: 'http://${proxy.address.address}:${proxy.port}',
    );
    addTearDown(transport.close);

    final response = await transport.send(
      http.Request(
        'GET',
        targetUri,
      ),
      timeout: const Duration(seconds: 2),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(response.body, 'proxied');
    final receivedRequest =
        await proxyReceivedRequest.future.timeout(const Duration(seconds: 2));
    expect(receivedRequest.method, 'GET');
    expect(receivedRequest.uri, targetUri);
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
  });

  test('uses a newly saved proxy for the next media-server request', () async {
    final firstProxyRequests = <Uri>[];
    final secondProxyRequests = <Uri>[];
    final firstProxy = await _startProxy(firstProxyRequests);
    final secondProxy = await _startProxy(secondProxyRequests);
    addTearDown(() => firstProxy.close(force: true));
    addTearDown(() => secondProxy.close(force: true));
    addTearDown(() => MediaServerTransport.setHttpProxyOverride(''));

    MediaServerTransport.setHttpProxyOverride(
      'http://${firstProxy.address.address}:${firstProxy.port}',
    );
    final firstTransport = await MediaServerTransport.fromStoredSettings();
    addTearDown(firstTransport.close);
    final firstTarget = Uri.parse('http://media.invalid/emby/System/Info');
    await firstTransport.send(
      http.Request('GET', firstTarget),
      timeout: const Duration(seconds: 2),
    );

    MediaServerTransport.setHttpProxyOverride(
      'http://${secondProxy.address.address}:${secondProxy.port}',
    );
    final secondTransport = await MediaServerTransport.fromStoredSettings();
    addTearDown(secondTransport.close);
    final secondTarget = Uri.parse('http://media.invalid/Items/7');
    await secondTransport.send(
      http.Request('GET', secondTarget),
      timeout: const Duration(seconds: 2),
    );

    expect(firstProxyRequests, [firstTarget]);
    expect(secondProxyRequests, [secondTarget]);
  });

  test('loads a valid persisted proxy when there is no runtime override',
      () async {
    final proxyRequests = <Uri>[];
    final proxy = await _startProxy(proxyRequests);
    addTearDown(() => proxy.close(force: true));
    SharedPreferences.setMockInitialValues({
      SettingsKeys.playerHttpProxy:
          'http://${proxy.address.address}:${proxy.port}',
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    MediaServerTransport.setHttpProxyOverride('http://127.0.0.1:1');
    MediaServerTransport.clearHttpProxyOverride();
    addTearDown(MediaServerTransport.clearHttpProxyOverride);

    final transport = await MediaServerTransport.fromStoredSettings();
    addTearDown(transport.close);
    final target = Uri.parse('http://media.invalid/emby/Items/9');
    await transport.send(
      http.Request('GET', target),
      timeout: const Duration(seconds: 2),
    );

    expect(proxyRequests, [target]);
  });

  test('rejects an invalid persisted proxy instead of connecting directly',
      () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.playerHttpProxy: 'https://proxy.invalid:443',
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    MediaServerTransport.setHttpProxyOverride('http://127.0.0.1:1');
    MediaServerTransport.clearHttpProxyOverride();
    addTearDown(MediaServerTransport.clearHttpProxyOverride);

    await expectLater(
      MediaServerTransport.fromStoredSettings(),
      throwsA(isA<FormatException>()),
    );
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

  test('validates the supported HTTP forward-proxy address shape', () {
    expect(
      MediaServerTransport.validateHttpProxy('http://127.0.0.1:8000'),
      Uri.parse('http://127.0.0.1:8000'),
    );
    expect(
      MediaServerTransport.validateHttpProxy('http://proxy.invalid'),
      Uri.parse('http://proxy.invalid'),
    );
    expect(
      MediaServerTransport.validateHttpProxy('http://proxy.invalid/'),
      Uri.parse('http://proxy.invalid/'),
    );
    expect(
      MediaServerTransport.validateHttpProxy('http://[::1]:8080'),
      Uri.parse('http://[::1]:8080'),
    );
    expect(MediaServerTransport.validateHttpProxy(''), isNull);
  });

  test('rejects proxy addresses that cannot be honored by the transport', () {
    for (final value in [
      '127.0.0.1:8000',
      'https://127.0.0.1:8000',
      'http://',
      'http://user:pass@127.0.0.1:8000',
      'http://127.0.0.1:8000/proxy',
      'http://127.0.0.1:8000?mode=proxy',
      'http://127.0.0.1:8000#proxy',
      'http://127.0.0.1:0',
      'http://127.0.0.1:70000',
      'http://127.0.0.1:8000//proxy',
    ]) {
      expect(
        () => MediaServerTransport.validateHttpProxy(value),
        throwsA(isA<FormatException>()),
        reason: value,
      );
    }
  });
}

Future<HttpServer> _startProxy(List<Uri> receivedRequests) async {
  final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  proxy.listen((request) async {
    receivedRequests.add(request.uri);
    request.response
      ..statusCode = HttpStatus.ok
      ..write('proxied');
    await request.response.close();
  });
  return proxy;
}

class _StallingClient extends http.BaseClient {
  bool isClosed = false;
  final List<(String, Uri)> sentRequests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sentRequests.add((request.method, request.url));
    return Completer<http.StreamedResponse>().future;
  }

  @override
  void close() {
    isClosed = true;
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
