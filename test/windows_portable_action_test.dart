import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual Windows builds publish one directly runnable artifact', () {
    final workflow =
        File('.github/workflows/build-windows.yml').readAsStringSync();
    final triggerDefinition = workflow.split('jobs:').first;
    final triggerSections = triggerDefinition.split('workflow_call:');

    expect(
      workflow,
      contains(r'portable-only: ${{ inputs.portable_only }}'),
    );
    expect(triggerSections, hasLength(2));
    expect(triggerSections.first, contains('default: true'));
    expect(triggerSections.last, contains('default: false'));
    expect(workflow, contains('name: Upload portable Windows artifact'));
    expect(
      workflow,
      contains('if: inputs.portable_only == true'),
    );
    expect(
      workflow,
      contains('path: build/windows/x64/runner/Release/'),
    );
    expect(
      workflow,
      contains('if: inputs.portable_only != true'),
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
}
