import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual Windows builds publish one directly runnable artifact', () {
    final workflow =
        File('.github/workflows/build-windows.yml').readAsStringSync();
    final triggerDefinition = workflow.split('jobs:').first;
    final triggerSections = triggerDefinition.split('workflow_call:');
    final pushSection = triggerDefinition
        .substring(
          triggerDefinition.indexOf('  push:'),
          triggerDefinition.indexOf('  workflow_dispatch:'),
        )
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('#'))
        .join('\n')
        .trim();
    final portableUpload = workflow.substring(
      workflow.indexOf('- name: Upload portable Windows artifact'),
      workflow.indexOf('- name: Upload Windows release artifacts'),
    );
    final releaseUpload = workflow.substring(
      workflow.indexOf('- name: Upload Windows release artifacts'),
      workflow.indexOf(
        '- name: Upload Dart debug symbols (for de-obfuscating crash stacks)',
      ),
    );
    final symbolsUpload = workflow.substring(
      workflow.indexOf(
        '- name: Upload Dart debug symbols (for de-obfuscating crash stacks)',
      ),
    );

    expect(
      pushSection,
      'push:\n    branches:\n      - build/ua-latest-windows-20260819',
    );
    expect(
      workflow,
      contains(
        r"portable-only: ${{ github.event_name == 'push' || inputs.portable_only }}",
      ),
    );
    expect(triggerSections, hasLength(2));
    expect(triggerSections.first, contains('default: true'));
    expect(triggerSections.last, contains('default: false'));
    expect(workflow, contains('name: Upload portable Windows artifact'));
    expect(
      portableUpload,
      contains(
        "if: github.event_name == 'push' || inputs.portable_only == true",
      ),
    );
    expect(
      portableUpload,
      contains('path: build/windows/x64/runner/Release/'),
    );
    expect(
      releaseUpload,
      contains(
        "if: github.event_name != 'push' && inputs.portable_only != true",
      ),
    );
    expect(
      symbolsUpload,
      contains(
        "if: always() && github.event_name != 'push' && inputs.portable_only != true",
      ),
    );
    expect(
      RegExp(r'uses:\s+actions/upload-artifact@v4')
          .allMatches(workflow)
          .length,
      3,
    );
  });

  test('portable mode skips distribution packaging', () {
    final action =
        File('.github/actions/build-windows/action.yml').readAsStringSync();

    expect(action, contains('portable-only:'));
    expect(
      action,
      contains("if: inputs.portable-only != 'true'"),
    );
    for (final step in <String>[
      'Create Windows ZIP package',
      'Install Inno Setup',
      'Ensure Inno Setup Chinese language file',
      'Create Windows installer with Inno Setup',
      'Update msix_version to match app version',
      'Build MSIX package',
    ]) {
      expect(action, contains('- name: $step'));
    }
  });

  test('Windows builds prefer a VS2022-compatible MDK SDK release', () {
    final action =
        File('.github/actions/build-windows/action.yml').readAsStringSync();
    final mdkSection = action.substring(
      action.indexOf(r'$mdkSdkPkg ='),
      action.indexOf('# Extract using 7-Zip'),
    );
    final firstCandidate = RegExp(
      r'\$candidates = @\(\s*"([^"]+)"',
      multiLine: true,
    ).firstMatch(mdkSection)?.group(1);

    expect(
      mdkSection,
      contains(
        r'$mdkSdkPkg = "mdk-sdk-windows-desktop-vs2022-x64.7z"',
      ),
    );
    expect(
      firstCandidate,
      r'https://github.com/wang-bin/mdk-sdk/releases/download/v0.35.1/$mdkSdkPkg',
    );
    expect(mdkSection, isNot(contains('/releases/latest')));
  });
}
