import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/player_abstraction/mdk_player_adapter_io.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'default restore initializes the kernel and later write failures surface',
    () async {
      const channel = MethodChannel('plugins.flutter.io/shared_preferences');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var failWrites = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getAll') {
          return <String, Object>{
            'flutter.player_kernel_type': PlayerKernelType.mediaKit.index,
            'flutter.${SettingsKeys.customPlayerUA}': 'CustomClient/1.0',
          };
        }
        if (call.method == 'setString' && failWrites) {
          throw PlatformException(
            code: 'write-failed',
            message: 'simulated persistence failure',
          );
        }
        return true;
      });
      SharedPreferences.resetStatic();
      final kernelChanged = Completer<PlayerKernelType>();
      final subscription = PlayerFactory.onKernelChanged.listen((event) {
        if (!kernelChanged.isCompleted) kernelChanged.complete(event);
      });
      addTearDown(() async {
        await subscription.cancel();
        messenger.setMockMethodCallHandler(channel, null);
        SharedPreferences.resetStatic();
      });

      await PlayerFactory.saveCustomPlayerUA('');

      expect(
        await kernelChanged.future.timeout(const Duration(milliseconds: 250)),
        PlayerKernelType.mediaKit,
      );

      failWrites = true;
      await expectLater(
        PlayerFactory.saveCustomPlayerUA('UnsavedClient/2.0'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'write-failed',
          ),
        ),
      );
    },
  );

  test(
    'every player open applies and then clears a one-time User-Agent',
    () async {
      SharedPreferences.setMockInitialValues({});
      await PlayerFactory.initialize();
      final player = _UserAgentRecordingPlayer();
      addTearDown(() {
        PlayerFactory.setOneTimeUA('');
        SharedPreferences.setMockInitialValues({});
      });

      PlayerFactory.setOneTimeUA('OneTimeClient/1.0');
      await Function.apply(PlayerFactory.applyUserAgentForNextOpen, [
        player.setUserAgent,
      ]);
      await Function.apply(PlayerFactory.applyUserAgentForNextOpen, [
        player.setUserAgent,
      ]);

      expect(player.userAgents, <String>['OneTimeClient/1.0', '']);
    },
  );

  test('default User-Agent does not write an empty native option override', () {
    final mdkApplied = <(String, String)>[];
    applyMdkUserAgentProperties(
      (key, value) => mdkApplied.add((key, value)),
      '',
    );
    expect(mdkApplied, isEmpty);

    final mediaKitApplied = <(String, String)>[];
    applyMediaKitUserAgentProperty(
      (key, value) => mediaKitApplied.add((key, value)),
      '',
    );
    expect(mediaKitApplied, isEmpty);
  });

  test(
    'restoring the default User-Agent requests the active native kernel',
    () async {
      addTearDown(() async {
        await PlayerFactory.saveCustomPlayerUA('');
        SharedPreferences.setMockInitialValues({});
      });

      for (final kernel in <PlayerKernelType>[
        PlayerKernelType.mdk,
        PlayerKernelType.mediaKit,
      ]) {
        SharedPreferences.setMockInitialValues({
          'player_kernel_type': kernel.index,
        });
        await PlayerFactory.initialize();
        await PlayerFactory.saveCustomPlayerUA('CustomClient/1.0');

        final kernelChanged = Completer<PlayerKernelType>();
        final subscription = PlayerFactory.onKernelChanged.listen((event) {
          if (!kernelChanged.isCompleted) kernelChanged.complete(event);
        });
        try {
          await PlayerFactory.saveCustomPlayerUA('');
          expect(
            await kernelChanged.future.timeout(
              const Duration(milliseconds: 250),
            ),
            kernel,
          );
        } finally {
          await subscription.cancel();
        }
      }
    },
  );

  test('MDK User-Agent setter uses the error-propagating property path', () {
    final source = File(
      'lib/player_abstraction/mdk_player_adapter_io.dart',
    ).readAsStringSync();
    final setter = _methodBody(
      source,
      'Future<void> setUserAgent(String ua)',
      'void setProperty(String key, String value)',
    );

    expect(
      setter,
      contains('applyMdkUserAgentProperties(_setStickyProperty, ua)'),
    );
    expect(setter, isNot(contains('applyMdkUserAgentProperties(setProperty')));
  });

  test(
    'initializePlayer delegates its only media open to the ordered boundary',
    () {
      final source = File(
        'lib/utils/video_player_state/video_player_state_player_setup.dart',
      ).readAsStringSync();
      final initializePlayer = _methodBody(
        source,
        'Future<void> initializePlayer(',
        'void _startBackgroundDanmakuLoading(',
      );

      expect(initializePlayer, isNot(contains('http.head(')));
      expect(initializePlayer, contains('await player.openMedia(playUrl);'));
      expect(
        RegExp(r'\bplayer\.openMedia\(playUrl\)').allMatches(initializePlayer),
        hasLength(1),
      );
      expect(initializePlayer, isNot(contains('player.media = playUrl;')));
    },
  );

  test(
    'player open waits until an asynchronous User-Agent setter completes',
    () async {
      SharedPreferences.setMockInitialValues({});
      await PlayerFactory.initialize();
      final setterMayComplete = Completer<void>();
      final events = <String>[];

      final result = Function.apply(PlayerFactory.applyUserAgentForNextOpen, [
        (String userAgent) async {
          events.add('setter-start:$userAgent');
          await setterMayComplete.future;
          events.add('setter-complete');
        },
      ]);

      if (result is! Future<void>) {
        fail('applyUserAgentForNextOpen must expose asynchronous completion');
      }
      var applyCompleted = false;
      result.then((_) => applyCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(applyCompleted, isFalse);

      setterMayComplete.complete();
      await result;

      expect(applyCompleted, isTrue);
      expect(events, <String>['setter-start:', 'setter-complete']);
    },
  );

  test(
    'media-open boundary waits for User-Agent before opening media',
    () async {
      SharedPreferences.setMockInitialValues({});
      await PlayerFactory.initialize();
      final setterMayComplete = Completer<void>();
      final delegate = _OrderedMediaOpenPlayer(setterMayComplete);
      final player = Player.withDelegate(delegate);

      final open = player.openMedia('https://media.example/video.mkv');

      await Future<void>.delayed(Duration.zero);
      expect(delegate.events, <String>['setter-start:']);

      setterMayComplete.complete();
      await open;

      expect(delegate.events, <String>[
        'setter-start:',
        'setter-complete',
        'media-open:https://media.example/video.mkv',
      ]);
    },
  );

  test('media-open boundary awaits the delegate open operation', () async {
    SharedPreferences.setMockInitialValues({});
    await PlayerFactory.initialize();
    final delegate = _AwaitableMediaOpenPlayer();
    final player = Player.withDelegate(delegate);
    var completed = false;

    final open = player
        .openMedia('https://media.example/awaitable.mkv')
        .whenComplete(() => completed = true);
    await Future<void>.delayed(Duration.zero);

    expect(completed, isFalse);
    expect(delegate.events, <String>[
      'setter:',
      'open-start:https://media.example/awaitable.mkv',
    ]);

    delegate.openMayComplete.complete();
    await open;
    expect(delegate.events, <String>[
      'setter:',
      'open-start:https://media.example/awaitable.mkv',
      'open-complete',
    ]);
  });

  test(
    'failed User-Agent application preserves one-time UA and does not open',
    () async {
      SharedPreferences.setMockInitialValues({});
      await PlayerFactory.initialize();
      PlayerFactory.setOneTimeUA('RetryClient/1.0');
      addTearDown(() => PlayerFactory.setOneTimeUA(''));
      final delegate = _FailingUserAgentPlayer();
      final player = Player.withDelegate(delegate);

      await expectLater(
        player.openMedia('https://media.example/failing.mkv'),
        throwsStateError,
      );

      expect(delegate.openedMedia, isEmpty);
      expect(PlayerFactory.getOneTimeUA(), 'RetryClient/1.0');

      delegate.failUserAgent = false;
      await player.openMedia('https://media.example/retry.mkv');
      expect(delegate.openedMedia, <String>['https://media.example/retry.mkv']);
      expect(PlayerFactory.getOneTimeUA(), isNull);
    },
  );

  test('concurrent media opens are serialized in invocation order', () async {
    SharedPreferences.setMockInitialValues({});
    await PlayerFactory.initialize();
    final delegate = _SequencedMediaOpenPlayer();
    final player = Player.withDelegate(delegate);

    final firstOpen = player.openMedia('https://media.example/first.mkv');
    await Future<void>.delayed(Duration.zero);
    final secondOpen = player.openMedia('https://media.example/second.mkv');
    await Future<void>.delayed(Duration.zero);

    expect(delegate.events, <String>['setter-start:']);

    delegate.setterCompletions.single.complete();
    await Future<void>.delayed(Duration.zero);
    expect(delegate.events, <String>[
      'setter-start:',
      'setter-complete',
      'media-open:https://media.example/first.mkv',
      'setter-start:',
    ]);

    delegate.setterCompletions.last.complete();
    await Future.wait<void>([firstOpen, secondOpen]);
    expect(delegate.events, <String>[
      'setter-start:',
      'setter-complete',
      'media-open:https://media.example/first.mkv',
      'setter-start:',
      'setter-complete',
      'media-open:https://media.example/second.mkv',
    ]);
  });

  test('one-time User-Agent is reserved by only one player', () async {
    SharedPreferences.setMockInitialValues({});
    await PlayerFactory.initialize();
    PlayerFactory.setOneTimeUA('SingleUseClient/1.0');
    addTearDown(() => PlayerFactory.setOneTimeUA(''));
    final firstDelegate = _BlockingUserAgentPlayer();
    final secondDelegate = _BlockingUserAgentPlayer();
    final firstPlayer = Player.withDelegate(firstDelegate);
    final secondPlayer = Player.withDelegate(secondDelegate);

    final firstOpen = firstPlayer.openMedia('https://media.example/first.mkv');
    await firstDelegate.setterStarted.future.timeout(
      const Duration(seconds: 1),
    );
    final secondOpen = secondPlayer.openMedia(
      'https://media.example/second.mkv',
    );
    await secondDelegate.setterStarted.future.timeout(
      const Duration(seconds: 1),
    );

    expect(firstDelegate.userAgents, <String>['SingleUseClient/1.0']);
    expect(secondDelegate.userAgents, <String>['']);

    firstDelegate.setterMayComplete.complete();
    secondDelegate.setterMayComplete.complete();
    await Future.wait<void>([firstOpen, secondOpen]);
  });
}

class _UserAgentRecordingPlayer extends Fake implements AbstractPlayer {
  final List<String> userAgents = <String>[];

  @override
  Future<void> setUserAgent(String ua) async => userAgents.add(ua);
}

class _OrderedMediaOpenPlayer extends Fake implements AbstractPlayer {
  _OrderedMediaOpenPlayer(this.setterMayComplete);

  final Completer<void> setterMayComplete;
  final List<String> events = <String>[];

  @override
  Future<void> setUserAgent(String ua) async {
    events.add('setter-start:$ua');
    await setterMayComplete.future;
    events.add('setter-complete');
  }

  @override
  set media(String value) => events.add('media-open:$value');

  @override
  Future<void> openMedia(String value) async {
    media = value;
  }
}

class _FailingUserAgentPlayer extends Fake implements AbstractPlayer {
  final List<String> openedMedia = <String>[];
  bool failUserAgent = true;

  @override
  Future<void> setUserAgent(String ua) async {
    if (failUserAgent) {
      throw StateError('simulated User-Agent failure');
    }
  }

  @override
  set media(String value) => openedMedia.add(value);

  @override
  Future<void> openMedia(String value) async {
    media = value;
  }
}

class _AwaitableMediaOpenPlayer extends Fake implements AbstractPlayer {
  final Completer<void> openMayComplete = Completer<void>();
  final List<String> events = <String>[];

  @override
  Future<void> setUserAgent(String ua) async => events.add('setter:$ua');

  @override
  Future<void> openMedia(String value) async {
    events.add('open-start:$value');
    await openMayComplete.future;
    events.add('open-complete');
  }

  @override
  set media(String value) => events.add('legacy-media-setter:$value');
}

class _SequencedMediaOpenPlayer extends Fake implements AbstractPlayer {
  final List<String> events = <String>[];
  final List<Completer<void>> setterCompletions = <Completer<void>>[];

  @override
  Future<void> setUserAgent(String ua) async {
    events.add('setter-start:$ua');
    final completion = Completer<void>();
    setterCompletions.add(completion);
    await completion.future;
    events.add('setter-complete');
  }

  @override
  set media(String value) => events.add('media-open:$value');

  @override
  Future<void> openMedia(String value) async {
    media = value;
  }
}

class _BlockingUserAgentPlayer extends Fake implements AbstractPlayer {
  final Completer<void> setterStarted = Completer<void>();
  final Completer<void> setterMayComplete = Completer<void>();
  final List<String> userAgents = <String>[];

  @override
  Future<void> setUserAgent(String ua) async {
    userAgents.add(ua);
    setterStarted.complete();
    await setterMayComplete.future;
  }

  @override
  set media(String value) {}

  @override
  Future<void> openMedia(String value) async {
    media = value;
  }
}

String _methodBody(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $startMarker');
  expect(end, greaterThan(start), reason: 'missing $endMarker');
  return source.substring(start, end);
}
