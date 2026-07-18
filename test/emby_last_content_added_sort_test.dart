import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/media_library_sort_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_library_view.dart';
import 'package:provider/provider.dart';

void main() {
  const sortBy = 'DateLastContentAdded';

  test('Emby exposes last episode added with both sort orders', () {
    final option = getMediaSortOptions(MediaLibraryType.emby).singleWhere(
      (option) => option.value == sortBy,
    );

    expect(option.label, '最后一集添加时间');
    expect(option.description, '按最后一集添加时间排序');
    expect(
      getMediaSortOptions(MediaLibraryType.jellyfin)
          .where((option) => option.value == sortBy),
      isEmpty,
    );
    expect(
      mediaLibrarySortOrders.map((order) => order['value']),
      containsAll(<String>['Ascending', 'Descending']),
    );
  });

  test('shared remote sorting builds ascending and descending Emby choices',
      () {
    final choices = buildNetworkMediaSortChoices(
      MediaLibraryType.emby,
      currentSortBy: 'DateCreated',
      currentSortOrder: 'Ascending',
    ).where((choice) => choice.sortBy == sortBy);

    expect(
      choices.map((choice) => choice.sortOrder),
      <String>['Ascending', 'Descending'],
    );
    expect(
      choices.map((choice) => choice.label),
      <String>[
        '最后一集添加时间 (升序)',
        '最后一集添加时间 (降序)',
      ],
    );
  });

  testWidgets(
      'desktop network media sort selects last episode added descending',
      (tester) async {
    NetworkMediaSortChoice? result;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AppDisplaySurfaceScope(
          surface: AppDisplaySurface.desktopTablet,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showAdaptiveNetworkMediaSortDialog(
                  context,
                  libraryType: MediaLibraryType.emby,
                  currentSortBy: 'DateCreated',
                  currentSortOrder: 'Ascending',
                );
              },
              child: const Text('打开排序'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开排序'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('最后一集添加时间 (降序)'));
    await tester.pumpAndSettle();

    expect(result?.sortBy, sortBy);
    expect(result?.sortOrder, 'Descending');
  });

  testWidgets('phone network media sort selects last episode added descending',
      (tester) async {
    NetworkMediaSortChoice? result;

    await tester.pumpWidget(
      ChangeNotifierProvider<BottomBarProvider>(
        create: (_) => BottomBarProvider(),
        child: cupertino.CupertinoApp(
          home: AppDisplaySurfaceScope(
            surface: AppDisplaySurface.phone,
            child: Builder(
              builder: (context) => cupertino.CupertinoButton(
                onPressed: () async {
                  result = await showAdaptiveNetworkMediaSortDialog(
                    context,
                    libraryType: MediaLibraryType.emby,
                    currentSortBy: 'DateCreated',
                    currentSortOrder: 'Ascending',
                  );
                },
                child: const Text('打开排序'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最后一集添加时间 (降序)'));
    await tester.pumpAndSettle();

    expect(result?.sortBy, sortBy);
    expect(result?.sortOrder, 'Descending');
  });
}
