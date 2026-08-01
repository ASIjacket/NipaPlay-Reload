import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/media_library_sort_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_library_view.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/route_recording_observer.dart';

void main() {
  const sortBy = 'DateLastContentAdded';

  test('Emby exposes last episode added with both sort orders', () {
    final option = getMediaSortOptions(
      MediaLibraryType.emby,
    ).singleWhere((option) => option.value == sortBy);

    expect(option.label, '最后一集添加时间');
    expect(option.description, '按最后一集添加时间排序');
    expect(
      getMediaSortOptions(
        MediaLibraryType.jellyfin,
      ).where((option) => option.value == sortBy),
      isEmpty,
    );
    expect(mediaLibrarySortOrders, <Map<String, String>>[
      <String, String>{'value': 'Ascending', 'label': '升序'},
      <String, String>{'value': 'Descending', 'label': '降序'},
    ]);
  });

  test('Emby provider sends last-content sorting to the HTTP API', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/emby/Users/test-user/Items/library-id') {
        request.response.write('{"CollectionType":"tvshows"}');
      } else if (request.uri.path == '/emby/Items') {
        request.response.write('{"Items":[],"TotalRecordCount":0}');
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{}');
      }
      await request.response.close();
    });

    final service = EmbyService.instance;
    final previousServerUrl = service.serverUrl;
    final previousUserId = service.userId;
    final previousAccessToken = service.accessToken;
    final previousConnected = service.isConnected;
    final previousProfile = service.currentProfile;
    final provider = EmbyProvider();
    addTearDown(() async {
      provider.dispose();
      await server.close(force: true);
      service.currentProfile = previousProfile;
      service.serverUrl = previousServerUrl;
      service.userId = previousUserId;
      service.accessToken = previousAccessToken;
      service.isConnected = previousConnected;
      SharedPreferences.setMockInitialValues({});
    });

    service.currentProfile = null;
    service.serverUrl = 'http://${server.address.address}:${server.port}';
    service.userId = 'test-user';
    service.accessToken = 'test-token';
    service.isConnected = true;
    provider.setLibrarySortSettings('library-id', sortBy, 'Descending');

    await HttpOverrides.runWithHttpOverrides(
      () => provider.fetchMediaItemsForLibrary('library-id', limit: 37),
      _RealHttpOverrides(),
    );

    final itemsRequest = requests.singleWhere(
      (uri) => uri.path == '/emby/Items',
    );
    expect(itemsRequest.queryParameters['ParentId'], 'library-id');
    expect(itemsRequest.queryParameters['SortBy'], sortBy);
    expect(itemsRequest.queryParameters['SortOrder'], 'Descending');
    expect(itemsRequest.queryParameters['Limit'], '37');
  });

  test('large Emby sorted libraries use one sorted request', () async {
    SharedPreferences.setMockInitialValues({});
    const totalItems = 201;
    final itemRequests = <Uri>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/emby/Users/test-user/Items/library-id') {
        request.response.write('{"CollectionType":"tvshows"}');
      } else if (request.uri.path == '/emby/Items') {
        itemRequests.add(request.uri);
        final startIndex =
            int.tryParse(request.uri.queryParameters['StartIndex'] ?? '') ?? 0;
        final requestedLimit =
            int.tryParse(request.uri.queryParameters['Limit'] ?? '') ??
                totalItems;
        final remaining = totalItems - startIndex;
        final count = remaining <= 0
            ? 0
            : (remaining < requestedLimit ? remaining : requestedLimit);
        request.response.write(
          jsonEncode({
            'Items': [
              for (var index = 0; index < count; index++)
                {
                  'Id': 'item-${startIndex + index}',
                  'Name': 'Item ${startIndex + index}',
                  'Type': 'Series',
                  'DateCreated': '2026-01-01T00:00:00Z',
                },
            ],
            'TotalRecordCount': totalItems,
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{}');
      }
      await request.response.close();
    });

    final service = EmbyService.instance;
    final previousServerUrl = service.serverUrl;
    final previousUserId = service.userId;
    final previousAccessToken = service.accessToken;
    final previousConnected = service.isConnected;
    final previousProfile = service.currentProfile;
    addTearDown(() async {
      await server.close(force: true);
      service.currentProfile = previousProfile;
      service.serverUrl = previousServerUrl;
      service.userId = previousUserId;
      service.accessToken = previousAccessToken;
      service.isConnected = previousConnected;
      SharedPreferences.setMockInitialValues({});
    });

    service.currentProfile = null;
    service.serverUrl = 'http://${server.address.address}:${server.port}';
    service.userId = 'test-user';
    service.accessToken = 'test-token';
    service.isConnected = true;

    final items = await HttpOverrides.runWithHttpOverrides(
      () => service.getLatestMediaItemsByLibrary(
        'library-id',
        limit: 99999,
        sortBy: sortBy,
        sortOrder: 'Descending',
      ),
      _RealHttpOverrides(),
    );

    expect(items, hasLength(totalItems));
    expect(itemRequests, hasLength(1));
    expect(itemRequests.single.queryParameters['StartIndex'], isNull);
    expect(itemRequests.single.queryParameters['Limit'], '99999');
    expect(
      itemRequests.map((uri) => uri.queryParameters['SortBy']).toSet(),
      <String>{sortBy},
    );
    expect(
      itemRequests.map((uri) => uri.queryParameters['SortOrder']).toSet(),
      <String>{'Descending'},
    );
  });

  testWidgets('Emby sort dialog avoids focus and request storms', (
    tester,
  ) async {
    await HttpOverrides.runWithHttpOverrides(() async {
      SharedPreferences.setMockInitialValues({});
      const totalItems = 201;
      final sortedItemRequests = <Uri>[];
      final sortedResponsesCompleted = Completer<void>();
      final server = (await tester.runAsync(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          var completesSortedResponse = false;
          request.response.headers.contentType = ContentType.json;
          final uri = request.uri;
          if (uri.path == '/emby/Library/MediaFolders') {
            request.response.write(
              '{"Items":[{"Id":"library-id","Name":"Test Library",'
              '"CollectionType":"tvshows"}]}',
            );
          } else if (uri.path == '/emby/Users/test-user/Items' &&
              uri.queryParameters['Limit'] == '0') {
            request.response.write(
              '{"Items":[],"TotalRecordCount":$totalItems}',
            );
          } else if (uri.path == '/emby/Users/test-user/Items') {
            request.response.write('{"Items":[],"TotalRecordCount":0}');
          } else if (uri.path == '/emby/Users/test-user/Items/library-id') {
            request.response.write('{"CollectionType":"tvshows"}');
          } else if (uri.path == '/emby/Items') {
            final isTargetSort = uri.queryParameters['SortBy'] == sortBy;
            if (isTargetSort) sortedItemRequests.add(uri);
            final startIndex =
                int.tryParse(uri.queryParameters['StartIndex'] ?? '') ?? 0;
            final requestedLimit =
                int.tryParse(uri.queryParameters['Limit'] ?? '') ?? totalItems;
            final remaining = totalItems - startIndex;
            final count = isTargetSort && remaining > 0
                ? (remaining < requestedLimit ? remaining : requestedLimit)
                : 0;
            completesSortedResponse =
                isTargetSort && startIndex + count >= totalItems;
            request.response.write(
              jsonEncode({
                'Items': [
                  for (var index = 0; index < count; index++)
                    {
                      'Id': 'item-${startIndex + index}',
                      'Name': 'Item ${startIndex + index}',
                      'Type': 'Series',
                      'DateCreated': '2026-01-01T00:00:00Z',
                    },
                ],
                'TotalRecordCount': isTargetSort ? totalItems : 0,
              }),
            );
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('{}');
          }
          await request.response.close();
          if (completesSortedResponse &&
              !sortedResponsesCompleted.isCompleted) {
            sortedResponsesCompleted.complete();
          }
        });
        return server;
      }))!;

      final service = EmbyService.instance;
      final previousServerUrl = service.serverUrl;
      final previousUserId = service.userId;
      final previousAccessToken = service.accessToken;
      final previousConnected = service.isConnected;
      final previousProfile = service.currentProfile;
      final previousSelectedLibraryIds = List<String>.of(
        service.selectedLibraryIds,
      );
      final provider = EmbyProvider();
      final appearanceProvider = AppearanceSettingsProvider();
      final routeObserver = RouteRecordingObserver();
      addTearDown(() async {
        provider.dispose();
        appearanceProvider.dispose();
        await tester.runAsync(() => server.close(force: true));
        service.clearServiceData();
        service.currentProfile = previousProfile;
        service.serverUrl = previousServerUrl;
        service.userId = previousUserId;
        service.accessToken = previousAccessToken;
        service.isConnected = previousConnected;
        service.selectedLibraryIds = previousSelectedLibraryIds;
        SharedPreferences.setMockInitialValues({});
      });

      service.currentProfile = null;
      service.clearServiceData();
      service.serverUrl = 'http://${server.address.address}:${server.port}';
      service.userId = 'test-user';
      service.accessToken = 'test-token';
      service.isConnected = true;
      service.selectedLibraryIds = <String>['library-id'];
      await tester.runAsync(service.loadAvailableLibraries);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<EmbyProvider>.value(value: provider),
            ChangeNotifierProvider<AppearanceSettingsProvider>.value(
              value: appearanceProvider,
            ),
          ],
          child: MaterialApp(
            navigatorObservers: <NavigatorObserver>[routeObserver],
            home: const AppDisplaySurfaceScope(
              surface: AppDisplaySurface.desktopTablet,
              child: SizedBox(
                width: 1000,
                height: 700,
                child: NetworkMediaLibraryView(
                  serverType: NetworkMediaServerType.emby,
                ),
              ),
            ),
          ),
        ),
      );
      try {
        await tester.pump();

        await tester.tap(find.text('Test Library'));
        await tester.pump();
        expect(find.byType(AdaptiveMediaActivityIndicator), findsOneWidget);
        await _pumpUntil(
          tester,
          () => find.byType(AdaptiveMediaActivityIndicator).evaluate().isEmpty,
          description: 'initial library load to finish',
          timeout: const Duration(seconds: 2),
        );
        await tester.tap(find.byIcon(Icons.sort_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        await _pumpUntil(
          tester,
          () => find.text('最后一集添加时间 (降序)').evaluate().isNotEmpty,
          description: 'remote sort options to appear',
          timeout: const Duration(seconds: 2),
        );
        final firstDialogAction =
            tester.widget<NipaplayLargeScreenFocusableAction>(
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(NipaplayLargeScreenFocusableAction),
              )
              .first,
        );
        expect(
          <bool?>[
            routeObserver.lastPushedRoute?.requestFocus,
            firstDialogAction.autofocus,
          ],
          <bool?>[
            defaultTargetPlatform != TargetPlatform.windows,
            defaultTargetPlatform != TargetPlatform.windows,
          ],
          reason: 'Only the native Windows dialog and its first option must '
              'avoid synchronously requesting window focus.',
        );
        final sortOption = find.text('最后一集添加时间 (降序)');
        await tester.ensureVisible(sortOption);
        await tester.pump();
        await tester.tap(sortOption);
        await _pumpUntil(
          tester,
          () =>
              provider.getLibrarySortSettings('library-id')['sortBy'] == sortBy,
          description: 'remote sort selection to apply',
          timeout: const Duration(seconds: 2),
        );
        await _pumpUntil(
          tester,
          () => sortedResponsesCompleted.isCompleted,
          description: 'all sorted responses to complete',
          timeout: const Duration(seconds: 2),
        );
        await _pumpUntil(
          tester,
          () => find.text('Item 0').evaluate().isNotEmpty,
          description: 'sorted library results to render',
          timeout: const Duration(seconds: 2),
        );

        expect(provider.getLibrarySortSettings('library-id'), <String, String>{
          'sortBy': sortBy,
          'sortOrder': 'Descending',
        });
        expect(sortedItemRequests, hasLength(1));
        expect(
          sortedItemRequests.single.queryParameters['StartIndex'],
          isNull,
        );
        expect(sortedItemRequests.single.queryParameters['Limit'], '99999');
        expect(
          sortedItemRequests
              .map((uri) => uri.queryParameters['SortOrder'])
              .toSet(),
          <String>{'Descending'},
        );
      } finally {
        ImageCacheManager.instance.clear();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<EmbyProvider>.value(value: provider),
              ChangeNotifierProvider<AppearanceSettingsProvider>.value(
                value: appearanceProvider,
              ),
            ],
            child: const MaterialApp(home: SizedBox.shrink()),
          ),
        );
        await tester.pump();
      }
    }, _RealHttpOverrides());
  }, variant: const TargetPlatformVariant(<TargetPlatform>{
    TargetPlatform.linux,
    TargetPlatform.windows,
  }));
}

class _RealHttpOverrides extends HttpOverrides {}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}
