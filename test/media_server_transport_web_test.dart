@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/services/media_server_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a runtime proxy override is ignored when the platform cannot proxy',
      () async {
    MediaServerTransport.setHttpProxyOverride('http://127.0.0.1:8000');
    addTearDown(MediaServerTransport.clearHttpProxyOverride);

    final transport = await MediaServerTransport.fromStoredSettings();
    addTearDown(transport.close);
  });

  test('a persisted proxy is ignored when the platform cannot proxy', () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.playerHttpProxy: 'http://127.0.0.1:8000',
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    MediaServerTransport.clearHttpProxyOverride();

    final transport = await MediaServerTransport.fromStoredSettings();
    addTearDown(transport.close);
  });

  test('an explicit browser proxy remains fail-fast', () {
    expect(
      () => MediaServerTransport(httpProxy: 'http://127.0.0.1:8000'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('browser transports do not try to set the restricted User-Agent header',
      () async {
    final client = _RecordingClient();
    final transport = MediaServerTransport.fromClient(client);
    addTearDown(transport.close);

    await transport.send(
      http.Request('GET', Uri.parse('https://media.example/Items/1')),
      timeout: const Duration(seconds: 1),
    );

    expect(client.userAgent, isNull);
  });
}

class _RecordingClient extends http.BaseClient {
  String? userAgent;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    userAgent = request.headers['User-Agent'];
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }
}
