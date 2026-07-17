import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saving a player User-Agent sanitizes and applies it immediately',
      () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.playerCustomUserAgent: '  PersistedClient/1.0\r\nInjected  ',
    });
    await PlayerFactory.initialize();
    addTearDown(() async {
      await PlayerFactory.saveCustomUserAgent('');
      SharedPreferences.setMockInitialValues({});
    });
    expect(PlayerFactory.getCustomUserAgent(), 'PersistedClient/1.0Injected');
    final kernelChanged = PlayerFactory.onKernelChanged.first;

    await PlayerFactory.saveCustomUserAgent(
      '  PlayerClient/5.0\r\nInjected  ',
    );

    expect(PlayerFactory.getCustomUserAgent(), 'PlayerClient/5.0Injected');
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(SettingsKeys.playerCustomUserAgent),
      'PlayerClient/5.0Injected',
    );
    expect(
      await kernelChanged.timeout(const Duration(seconds: 1)),
      PlayerKernelType.mdk,
    );
  });
}
