@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
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
}
