import 'dart:io';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/erika_player_adapter.dart';

String _configuredErikaRef() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match = RegExp(
    r'^  erika_flutter:\s*$.*?^      ref:\s*([^\s#]+)',
    multiLine: true,
    dotAll: true,
  ).firstMatch(pubspec);
  expect(match, isNotNull, reason: 'pubspec.yaml must pin erika_flutter');
  return match!.group(1)!;
}

String? _workflowEnvironmentValue(String source, String key) {
  return RegExp(
    '^\\s+$key:\\s*["\']?([^\\s"\']+)',
    multiLine: true,
  ).firstMatch(source)?.group(1);
}

void main() {
  test('ErikaPlayerAdapter compiles against the pinned diagnostics API', () {
    expect(ErikaPlayerAdapter, isA<Type>());

    Future<ErikaOutputStatus> readOutputStatus(ErikaPlayer player) =>
        player.getOutputStatus();

    expect(
      readOutputStatus,
      isA<Future<ErikaOutputStatus> Function(ErikaPlayer)>(),
    );
    expect(ErikaOutputMode.extendedLinear.nativeValue, 2);
    expect(
      ErikaEventKind.values,
      containsAll(<ErikaEventKind>[
        ErikaEventKind.videoDecoderChanged,
        ErikaEventKind.audioOutputChanged,
      ]),
    );

    final event = ErikaPlayerEvent.fromMap(const <String, Object?>{});
    expect(event.error, isNull);
    expect(event.message, isNull);
    expect(event.decoder, isNull);
    expect(event.audio, isNull);
    expect(
      ErikaOutputStatus.fromMap(const <String, Object?>{}),
      isA<ErikaOutputStatus>(),
    );
  });

  test('release workflows pin one Erika release for API and native ABI', () {
    final configuredRef = _configuredErikaRef();
    expect(
      configuredRef,
      startsWith('v'),
      reason: 'prebuilt Erika packages must use a published release tag',
    );
    final workflows = <String>[
      '.github/workflows/build-windows.yml',
      '.github/workflows/build-macos.yml',
      '.github/workflows/build-ios.yml',
    ];

    for (final path in workflows) {
      final source = File(path).readAsStringSync();
      expect(
        _workflowEnvironmentValue(source, 'ERIKA_REF'),
        configuredRef,
        reason: '$path must compile against the pinned Erika API',
      );
      expect(
        _workflowEnvironmentValue(source, 'ERIKA_PREBUILT_TAG'),
        configuredRef,
        reason: '$path must package the matching Erika native ABI',
      );
    }
  });
}
