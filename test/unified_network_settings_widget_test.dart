import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/services/media_server_service_base.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/remote_media_library_settings_content.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

class _InitializedEmbyProvider extends EmbyProvider {
  @override
  bool get isInitialized => true;

  @override
  bool get isLoading => false;
}

class _InitializedJellyfinProvider extends JellyfinProvider {
  @override
  bool get isInitialized => true;

  @override
  bool get isLoading => false;
}

class _InitializedDandanplayProvider extends DandanplayRemoteProvider {
  @override
  bool get isInitialized => true;

  @override
  bool get isLoading => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp(
    Widget child, {
    AdaptiveSettingsStyle style = AdaptiveSettingsStyle.desktopTablet,
  }) {
    return ChangeNotifierProvider(
      create: (_) => AppearanceSettingsProvider(),
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AdaptiveSettingsScope(
          style: style,
          child: child,
        ),
      ),
    );
  }

  Widget buildRemoteSettingsApp({
    AdaptiveSettingsStyle style = AdaptiveSettingsStyle.desktopTablet,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<EmbyProvider>(
          create: (_) => _InitializedEmbyProvider(),
        ),
        ChangeNotifierProvider<JellyfinProvider>(
          create: (_) => _InitializedJellyfinProvider(),
        ),
        ChangeNotifierProvider<DandanplayRemoteProvider>(
          create: (_) => _InitializedDandanplayProvider(),
        ),
        ChangeNotifierProvider<SharedRemoteLibraryProvider>(
          create: (_) => SharedRemoteLibraryProvider(),
        ),
      ],
      child: buildApp(
        const RemoteMediaLibrarySettingsContent(),
        style: style,
      ),
    );
  }

  testWidgets('connection UA setting loads, sanitizes, and restores default',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.customPlayerUA: 'ExistingPlayer/7.0',
      SettingsKeys.mediaServerConnectionUserAgent: 'StoredClient/1.0',
    });
    addTearDown(() async {
      await MediaServerServiceBase.saveConnectionUserAgent('');
      SharedPreferences.setMockInitialValues({});
    });

    await tester.pumpWidget(
      buildRemoteSettingsApp(),
    );
    await tester.pumpAndSettle();
    final tile = find.text('连接 User-Agent（Jellyfin/Emby）');
    await tester.scrollUntilVisible(
      tile,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('StoredClient/1.0'), findsOneWidget);

    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '  NewClient/2.0\r\nInjected  ',
    );
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    expect(
      await MediaServerServiceBase.getStoredConnectionUserAgent(),
      'NewClient/2.0Injected',
    );
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(SettingsKeys.customPlayerUA),
      'ExistingPlayer/7.0',
      reason: 'The media-server setting must not replace PR #712 player UA.',
    );
    expect(
      preferences.getString(SettingsKeys.mediaServerConnectionUserAgent),
      'NewClient/2.0Injected',
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '');
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    expect(
      await MediaServerServiceBase.getStoredConnectionUserAgent(),
      isEmpty,
    );
    expect(
      find.text(MediaServerServiceBase.defaultConnectionUserAgent),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('phone connection UA setting saves through the Cupertino dialog',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await MediaServerServiceBase.saveConnectionUserAgent('PhoneClient/1.0');
    addTearDown(() async {
      await MediaServerServiceBase.saveConnectionUserAgent('');
      SharedPreferences.setMockInitialValues({});
    });

    await tester.pumpWidget(
      buildRemoteSettingsApp(
        style: AdaptiveSettingsStyle.phone,
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.text('连接 User-Agent（Jellyfin/Emby）');
    await tester.scrollUntilVisible(
      tile,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('PhoneClient/1.0'), findsOneWidget);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(cupertino.CupertinoTextField).last,
      'PhoneClient/2.0',
    );
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();

    expect(
      await MediaServerServiceBase.getStoredConnectionUserAgent(),
      'PhoneClient/2.0',
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
