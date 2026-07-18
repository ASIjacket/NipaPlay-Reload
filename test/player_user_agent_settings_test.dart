import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/player_abstraction/abstract_player.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saving a player User-Agent sanitizes and applies it immediately',
      () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.legacyPlayerCustomUserAgent:
          '  PersistedClient/1.0\r\nInjected  ',
    });
    addTearDown(() async {
      await PlayerFactory.saveCustomPlayerUA('');
      SharedPreferences.setMockInitialValues({});
    });
    await PlayerFactory.initialize();
    expect(PlayerFactory.getCustomPlayerUA(), 'PersistedClient/1.0Injected');
    var preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(SettingsKeys.customPlayerUA),
      'PersistedClient/1.0Injected',
    );
    final userAgentKernelChanged = PlayerFactory.onKernelChanged.first;

    await PlayerFactory.saveCustomPlayerUA(
      '  PlayerClient/5.0\r\nInjected  ',
    );

    expect(PlayerFactory.getCustomPlayerUA(), 'PlayerClient/5.0Injected');
    preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(SettingsKeys.customPlayerUA),
      'PlayerClient/5.0Injected',
    );
    expect(
      await userAgentKernelChanged.timeout(const Duration(seconds: 1)),
      PlayerKernelType.mdk,
    );
  });

  test('stream setup delegates reachability to the configured player', () {
    final source = File(
      'lib/utils/video_player_state/video_player_state_player_setup.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('http.head(')));
    expect(
      source,
      contains('PlayerFactory.applyUserAgentForNextOpen(player.setUserAgent);'),
    );
  });

  test('one-time User-Agent is cleared on the following player open', () async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() async {
      PlayerFactory.setOneTimeUA('');
      await PlayerFactory.saveCustomPlayerUA('');
      SharedPreferences.setMockInitialValues({});
    });
    await PlayerFactory.initialize();
    await PlayerFactory.saveCustomPlayerUA('');
    final player = _UserAgentRecordingPlayer();

    PlayerFactory.setOneTimeUA('OneTimeClient/1.0');
    PlayerFactory.applyUserAgentForNextOpen(player.setUserAgent);
    PlayerFactory.applyUserAgentForNextOpen(player.setUserAgent);

    expect(player.userAgents, <String>['OneTimeClient/1.0', '']);
  });
}

class _UserAgentRecordingPlayer extends Fake implements AbstractPlayer {
  final List<String> userAgents = <String>[];

  @override
  void setUserAgent(String ua) => userAgents.add(ua);
}
