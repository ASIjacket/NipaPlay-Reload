import 'dart:async';

import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/media_library/adaptive_media_library_controls.dart';
import 'package:nipaplay/media_library/media_library_section_order_store.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dynamicSection = UnifiedMediaLibrarySection(
  id: 'future-media-source',
  label: 'Future Media',
  phoneSymbol: 'rectangle.stack.badge.plus',
  contentType: UnifiedMediaLibraryContentType.dandanplay,
);

const _sections = <UnifiedMediaLibrarySection>[
  UnifiedMediaLibrarySection(
    id: MediaLibrarySectionIds.local,
    label: '本地媒体库',
    phoneSymbol: 'rectangle.stack',
    contentType: UnifiedMediaLibraryContentType.mediaCollection,
    source: UnifiedMediaLibrarySource.local,
  ),
  UnifiedMediaLibrarySection(
    id: MediaLibrarySectionIds.localManagement,
    label: '本地库管理',
    phoneSymbol: 'folder',
    contentType: UnifiedMediaLibraryContentType.libraryManagement,
    source: UnifiedMediaLibrarySource.local,
  ),
  UnifiedMediaLibrarySection(
    id: MediaLibrarySectionIds.emby,
    label: 'Emby',
    phoneSymbol: 'tv.fill',
    contentType: UnifiedMediaLibraryContentType.networkServer,
    server: UnifiedMediaLibraryServer.emby,
  ),
  _dynamicSection,
];

void main() {
  test('saved section order ignores stale ids and appends new media sources',
      () {
    final ordered = applyMediaLibrarySectionOrder(
      _sections,
      const <String>[
        MediaLibrarySectionIds.emby,
        'removed-media-source',
        MediaLibrarySectionIds.local,
        MediaLibrarySectionIds.emby,
      ],
    );

    expect(
      ordered.map((section) => section.id),
      <String>[
        MediaLibrarySectionIds.emby,
        MediaLibrarySectionIds.local,
        MediaLibrarySectionIds.localManagement,
        _dynamicSection.id,
      ],
    );
  });

  test('section reorder uses the adjusted onReorderItem destination index', () {
    expect(
      reorderMediaLibrarySectionIds(
        _sections.map((section) => section.id).toList(),
        2,
        0,
      ),
      <String>[
        MediaLibrarySectionIds.emby,
        MediaLibrarySectionIds.local,
        MediaLibrarySectionIds.localManagement,
        _dynamicSection.id,
      ],
    );
    expect(
      reorderMediaLibrarySectionIds(
        _sections.map((section) => section.id).toList(),
        0,
        2,
      ),
      <String>[
        MediaLibrarySectionIds.localManagement,
        MediaLibrarySectionIds.emby,
        MediaLibrarySectionIds.local,
        _dynamicSection.id,
      ],
    );
  });

  test('section order round-trips through settings storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsKeys.mediaLibrarySectionOrder: <String>[
        MediaLibrarySectionIds.emby,
        MediaLibrarySectionIds.local,
      ],
    });
    final store = MediaLibrarySectionOrderStore();

    expect(await store.restore(), isTrue);
    expect(
      store.sectionIds,
      <String>[
        MediaLibrarySectionIds.emby,
        MediaLibrarySectionIds.local,
      ],
    );

    await store.update(<String>[
      MediaLibrarySectionIds.localManagement,
      MediaLibrarySectionIds.emby,
    ]);
    final restoredStore = MediaLibrarySectionOrderStore();
    expect(await restoredStore.restore(), isTrue);
    expect(
      restoredStore.sectionIds,
      <String>[
        MediaLibrarySectionIds.localManagement,
        MediaLibrarySectionIds.emby,
      ],
    );
  });

  test('delayed restore cannot overwrite a newly saved section order',
      () async {
    final delayedLoad = Completer<List<String>>();
    final savedOrders = <List<String>>[];
    final store = MediaLibrarySectionOrderStore(
      load: () => delayedLoad.future,
      save: (ids) async => savedOrders.add(List<String>.of(ids)),
    );

    final pendingRestore = store.restore();
    await store.update(<String>[
      MediaLibrarySectionIds.localManagement,
      MediaLibrarySectionIds.emby,
    ]);
    delayedLoad.complete(<String>[
      MediaLibrarySectionIds.emby,
      MediaLibrarySectionIds.local,
    ]);

    expect(await pendingRestore, isFalse);
    expect(
      store.sectionIds,
      <String>[
        MediaLibrarySectionIds.localManagement,
        MediaLibrarySectionIds.emby,
      ],
    );
    expect(
      savedOrders.single,
      <String>[
        MediaLibrarySectionIds.localManagement,
        MediaLibrarySectionIds.emby,
      ],
    );
  });

  testWidgets('desktop media library exposes every dynamic section to sorting',
      (tester) async {
    List<String>? savedOrder;

    await tester.pumpWidget(
      MaterialApp(
        home: AppDisplaySurfaceScope(
          surface: AppDisplaySurface.desktopTablet,
          child: SizedBox(
            width: 1000,
            height: 700,
            child: AdaptiveMediaLibraryScaffold(
              sections: _sections,
              selectedSection: _sections.first,
              onSectionSelected: (_) {},
              onSectionOrderChanged: (value) => savedOrder = value,
              onRemoteAccess: () {},
              onAddMedia: () {},
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('排序'));
    await tester.pumpAndSettle();

    expect(find.text('媒体库排序'), findsOneWidget);
    for (final section in _sections) {
      expect(find.text(section.label), findsWidgets);
    }

    final embyHandle = find.byKey(
      const ValueKey<String>('media-library-order-drag-emby'),
    );
    final firstRow = find.byKey(
      const ValueKey<String>('media-library-order-row-local_library'),
    );
    final dragStart = tester.getCenter(embyHandle);
    final gesture = await tester.startGesture(dragStart);
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    await gesture.moveTo(
      Offset(dragStart.dx, tester.getTopLeft(firstRow).dy - 20),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(
      savedOrder,
      <String>[
        MediaLibrarySectionIds.emby,
        MediaLibrarySectionIds.local,
        MediaLibrarySectionIds.localManagement,
        _dynamicSection.id,
      ],
    );
  });

  testWidgets('desktop order dialog grows with section count and caps its size',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<Size> openDialogWith(int sectionCount) async {
      final sections = List<UnifiedMediaLibrarySection>.generate(
        sectionCount,
        (index) => UnifiedMediaLibrarySection(
          id: 'dynamic-$index',
          label: '动态媒体库 $index',
          phoneSymbol: 'rectangle.stack',
          contentType: UnifiedMediaLibraryContentType.dandanplay,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AppDisplaySurfaceScope(
            surface: AppDisplaySurface.desktopTablet,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  await showAdaptiveMediaLibrarySectionOrder(
                    context,
                    sections,
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
      final size = tester.getSize(
        find.byKey(
          const ValueKey<String>('media-library-order-dialog-content'),
        ),
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      return size;
    }

    final twoSections = await openDialogWith(2);
    final sixSections = await openDialogWith(6);
    final manySections = await openDialogWith(20);

    for (final size in <Size>[twoSections, sixSections, manySections]) {
      expect(size.width, greaterThanOrEqualTo(640));
      expect(size.width, lessThanOrEqualTo(720));
    }
    expect(twoSections.height, greaterThanOrEqualTo(240));
    expect(sixSections.height, greaterThan(twoSections.height));
    expect(manySections.height, greaterThan(sixSections.height));
    expect(manySections.height, lessThanOrEqualTo(576));
  });

  testWidgets('phone media library can open and save dynamic section sorting',
      (tester) async {
    List<String>? savedOrder;

    await tester.pumpWidget(
      ChangeNotifierProvider<BottomBarProvider>(
        create: (_) => BottomBarProvider(),
        child: cupertino.CupertinoApp(
          home: AppDisplaySurfaceScope(
            surface: AppDisplaySurface.phone,
            child: AdaptiveMediaLibraryScaffold(
              sections: _sections,
              selectedSection: _sections.first,
              onSectionSelected: (_) {},
              onSectionOrderChanged: (value) => savedOrder = value,
              onRemoteAccess: () {},
              onAddMedia: () {},
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('排序'));
    await tester.pumpAndSettle();

    expect(find.text('媒体库排序'), findsOneWidget);
    for (final section in _sections) {
      expect(find.text(section.label), findsWidgets);
    }

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(savedOrder, _sections.map((section) => section.id).toList());
  });
}
