import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';

void main() {
  test('MediaKit maps player UA and HTTP proxy to libmpv options', () {
    final applied = <(String, String)>[];

    applyMediaKitNetworkOptions(
      (key, value) => applied.add((key, value)),
      userAgent: 'PlayerClient/5.0',
      httpProxy: 'http://127.0.0.1:8000',
    );

    expect(
      applied,
      [
        ('user-agent', 'PlayerClient/5.0'),
        ('http-proxy', 'http://127.0.0.1:8000'),
      ],
    );
  });

  test('MediaKit preserves defaults for empty network options', () {
    final cases = <({
      String userAgent,
      String httpProxy,
      List<(String, String)> expected,
    })>[
      (userAgent: '', httpProxy: '', expected: []),
      (
        userAgent: 'PlayerClient/5.0',
        httpProxy: '',
        expected: [('user-agent', 'PlayerClient/5.0')],
      ),
      (
        userAgent: '',
        httpProxy: 'http://127.0.0.1:8000',
        expected: [('http-proxy', 'http://127.0.0.1:8000')],
      ),
    ];

    for (final testCase in cases) {
      final applied = <(String, String)>[];
      applyMediaKitNetworkOptions(
        (key, value) => applied.add((key, value)),
        userAgent: testCase.userAgent,
        httpProxy: testCase.httpProxy,
      );
      expect(applied, testCase.expected);
    }
  });

  test('PlayerFactory passes both network settings to supported adapters', () {
    final factorySource = File(
      'lib/player_abstraction/player_factory.dart',
    ).readAsStringSync();
    final mdkSource = File(
      'lib/player_abstraction/mdk_player_adapter_io.dart',
    ).readAsStringSync();
    final mediaKitSource = File(
      'lib/player_abstraction/media_kit_player_adapter.dart',
    ).readAsStringSync();
    final compactFactory = factorySource.replaceAll(RegExp(r'\s+'), ' ');
    final compactMdk = mdkSource.replaceAll(RegExp(r'\s+'), ' ');
    final compactMediaKit = mediaKitSource.replaceAll(RegExp(r'\s+'), ' ');
    String kernelCase(String current, String next) {
      final start = compactFactory.indexOf('case PlayerKernelType.$current:');
      expect(start, greaterThanOrEqualTo(0));
      final end = compactFactory.indexOf('case PlayerKernelType.$next:', start);
      expect(end, greaterThan(start));
      return compactFactory.substring(start, end);
    }

    final mdkCase = kernelCase('mdk', 'videoPlayer');
    final mediaKitCase = kernelCase('mediaKit', 'erika');

    expect(mdkCase, contains('MdkPlayerAdapter('));
    expect(mdkCase, contains('userAgent: customPlayerUA'));
    expect(mdkCase, contains('httpProxy: httpProxy'));
    expect(mediaKitCase, contains('MediaKitPlayerAdapter('));
    expect(mediaKitCase, contains('userAgent: customPlayerUA'));
    expect(mediaKitCase, contains('httpProxy: httpProxy'));
    expect(
      compactMdk,
      contains('applyMdkHttpProxyProperties(_setStickyProperty, _httpProxy)'),
    );
    expect(
      compactMediaKit,
      contains(
        'applyMediaKitNetworkOptions( _setMpvPropertyOption, '
        'userAgent: _userAgent, httpProxy: _httpProxy, )',
      ),
    );
  });
}
