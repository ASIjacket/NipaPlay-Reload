import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/pages/media_server_detail_page.dart';

void main() {
  testWidgets('successful Emby playback closes the original detail route',
      (tester) async {
    final playback = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                content: const Text('episode-detail'),
                actions: [
                  TextButton(
                    onPressed: () {
                      unawaited(startEmbyPlaybackAndCloseDetail(
                        detailNavigator: Navigator.of(dialogContext),
                        startPlayback: () => playback.future,
                      ));
                    },
                    child: const Text('play'),
                  ),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('play'));
    await tester.pump();
    expect(find.text('episode-detail'), findsOneWidget);

    playback.complete();
    await tester.pumpAndSettle();
    expect(find.text('episode-detail'), findsNothing);
  });

  testWidgets('failed Emby playback keeps the detail route for fallback',
      (tester) async {
    Object? caughtError;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                content: const Text('episode-detail'),
                actions: [
                  TextButton(
                    onPressed: () async {
                      try {
                        await startEmbyPlaybackAndCloseDetail(
                          detailNavigator: Navigator.of(dialogContext),
                          startPlayback: () async => throw StateError('failed'),
                        );
                      } on StateError catch (error) {
                        caughtError = error;
                      }
                    },
                    child: const Text('play'),
                  ),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();

    expect(find.text('episode-detail'), findsOneWidget);
    expect(caughtError, isA<StateError>());
  });

  test('media detail captures its navigator before switching pages', () {
    final source =
        File('lib/pages/media_server_detail_page.dart').readAsStringSync();
    final methodStart = source.indexOf('Future<void> _startEpisodePlayback(');
    final methodEnd = source.indexOf(
      'Widget _buildEpisodesListForSelectedSeason()',
      methodStart,
    );
    final methodSource = source.substring(methodStart, methodEnd);

    final navigatorCapture =
        methodSource.indexOf('final detailNavigator = Navigator.of(context);');
    final pageChange = methodSource.indexOf(
      'tabChangeNotifier?.changePage(AppPageIds.video);',
    );
    final helperCall =
        methodSource.indexOf('startEmbyPlaybackAndCloseDetail(');

    expect(navigatorCapture, greaterThanOrEqualTo(0));
    expect(navigatorCapture, lessThan(pageChange));
    expect(helperCall, greaterThan(pageChange));
  });
}
