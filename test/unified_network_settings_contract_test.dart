import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unified network settings own the desktop HTTP proxy workflow', () {
    final source = File(
      'lib/settings/pages/network_settings_content.dart',
    ).readAsStringSync();

    expect(source, contains('MediaServerTransport.validateHttpProxy'));
    expect(source, contains('PlayerFactory.saveHttpProxy'));
    expect(source, contains('MediaServerServiceBase.setHttpProxyOverride'));
    expect(source, contains('if (kIsWeb) return false'));
    expect(source, contains('TargetPlatform.windows'));
    expect(source, contains('TargetPlatform.macOS'));
    expect(source, contains('TargetPlatform.linux'));
  });

  test('unified remote-media settings expose the connection UA workflow', () {
    final pageSource = File(
      'lib/settings/pages/remote_media_library_settings_content.dart',
    ).readAsStringSync();
    final settingSource = File(
      'lib/settings/widgets/media_server_connection_user_agent_setting.dart',
    ).readAsStringSync();

    expect(
      pageSource,
      contains('MediaServerConnectionUserAgentSetting'),
    );
    expect(
      settingSource,
      contains('MediaServerServiceBase.getStoredConnectionUserAgent'),
    );
    expect(
      settingSource,
      contains('MediaServerServiceBase.saveConnectionUserAgent'),
    );
    expect(
      settingSource,
      contains('MediaServerServiceBase.defaultConnectionUserAgent'),
    );
  });
}
