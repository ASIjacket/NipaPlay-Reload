import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/player_abstraction/mdk_player_adapter_io.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MDK applies the HTTP proxy to both FFmpeg option layers', () {
    final applied = <(String, String)>[];

    applyMdkHttpProxyProperties(
      (key, value) => applied.add((key, value)),
      'http://127.0.0.1:8000',
    );

    expect(applied, [
      ('avformat.http_proxy', 'http://127.0.0.1:8000'),
      ('avio.http_proxy', 'http://127.0.0.1:8000'),
    ]);
  });

  test('MediaKit maps the HTTP proxy to the libmpv option', () {
    final applied = <(String, String)>[];

    applyMediaKitNetworkOptions(
      (key, value) => applied.add((key, value)),
      userAgent: '',
      httpProxy: 'http://127.0.0.1:8000',
    );

    expect(applied, [('http-proxy', 'http://127.0.0.1:8000')]);
  });

  test('saving a proxy persists it and rebuilds the active kernel', () async {
    SharedPreferences.setMockInitialValues({});
    await PlayerFactory.initialize();
    addTearDown(() async {
      await PlayerFactory.saveHttpProxy('');
      SharedPreferences.setMockInitialValues({});
    });
    final kernelChanged = PlayerFactory.onKernelChanged.first;

    await PlayerFactory.saveHttpProxy('  http://127.0.0.1:8000  ');

    expect(PlayerFactory.getHttpProxy(), 'http://127.0.0.1:8000');
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(SettingsKeys.playerHttpProxy),
      'http://127.0.0.1:8000',
    );
    expect(
      await kernelChanged.timeout(const Duration(seconds: 1)),
      PlayerKernelType.mdk,
    );
  });

  test('initialization restores the persisted HTTP proxy', () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.playerHttpProxy: '  http://127.0.0.1:8123  ',
    });
    addTearDown(() async {
      await PlayerFactory.saveHttpProxy('');
      SharedPreferences.setMockInitialValues({});
    });

    await PlayerFactory.initialize();

    expect(PlayerFactory.getHttpProxy(), 'http://127.0.0.1:8123');
  });

  test('PlayerFactory passes the proxy to MDK and MediaKit adapters', () {
    final source = File(
      'lib/player_abstraction/player_factory.dart',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

    expect(
      source,
      contains('MdkPlayerAdapter( userAgent: customPlayerUA, '
          'httpProxy: httpProxy,'),
    );
    expect(
      source,
      contains('MediaKitPlayerAdapter( bufferSize:'),
    );
    expect(
      source,
      contains('userAgent: customPlayerUA, httpProxy: httpProxy,'),
    );
  });
}
