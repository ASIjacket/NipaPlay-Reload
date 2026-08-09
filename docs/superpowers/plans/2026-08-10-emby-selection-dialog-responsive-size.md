# Emby Selection Dialog Responsive Size Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Windows Emby version-and-track dialog compact and responsive without changing the iOS sheet or selection behavior.

**Architecture:** Add one pure layout calculation beside the Windows dialog wrapper. The wrapper reads `MediaQuery.sizeOf`, calculates safe width and height limits, and passes them to the existing `NipaplayWindowScaffold`; the shared selector keeps its existing `720px` two-column breakpoint.

**Tech Stack:** Flutter, Dart records, `flutter_test`

## Global Constraints

- Width target is `72%`, capped at `680–860px`, with the available screen width overriding the lower bound on smaller windows.
- Height target is `78%`, capped at `560–760px`, with a `20px` margin on each edge taking priority on shorter windows.
- Do not modify the iOS bottom sheet, shared window scaffold, selection persistence, or playback logic.
- Tests precede production changes.

---

### Task 1: Responsive Windows dialog metrics

**Files:**
- Modify: `lib/themes/nipaplay/widgets/emby_media_selection_dialog.dart`
- Create: `test/emby_selection_dialog_layout_test.dart`
- Verify: `test/emby_media_selection_panel_test.dart`

**Interfaces:**
- Consumes: `Size screenSize` from `MediaQuery.sizeOf(context)`.
- Produces: `({double maxWidth, double maxHeightFactor}) calculateEmbySelectionDialogMetrics(Size screenSize)`.

- [ ] **Step 1: Write failing metric tests**

```dart
test('caps a large desktop dialog', () {
  final metrics = calculateEmbySelectionDialogMetrics(const Size(1920, 1080));
  expect(metrics.maxWidth, 860);
  expect(metrics.maxHeightFactor, closeTo(760 / 1080, 0.0001));
});

test('scales continuously for a normal window', () {
  final metrics = calculateEmbySelectionDialogMetrics(const Size(1024, 768));
  expect(metrics.maxWidth, closeTo(1024 * 0.72, 0.0001));
  expect(metrics.maxHeightFactor, closeTo(0.78, 0.0001));
});

test('keeps forty pixels of safety margin on a small window', () {
  final metrics = calculateEmbySelectionDialogMetrics(const Size(600, 480));
  expect(metrics.maxWidth, 560);
  expect(metrics.maxHeightFactor, closeTo(440 / 480, 0.0001));
});
```

- [ ] **Step 2: Verify the tests fail**

Run:

```powershell
flutter test test/emby_selection_dialog_layout_test.dart
```

Expected: compilation failure because `calculateEmbySelectionDialogMetrics` does not exist.

- [ ] **Step 3: Implement the pure calculation and use it in the wrapper**

```dart
({double maxWidth, double maxHeightFactor})
    calculateEmbySelectionDialogMetrics(Size screenSize) {
  const margin = 20.0;
  final availableWidth = math.max(0.0, screenSize.width - margin * 2);
  final availableHeight = math.max(0.0, screenSize.height - margin * 2);
  final targetWidth = (screenSize.width * 0.72).clamp(680.0, 860.0);
  final targetHeight = (screenSize.height * 0.78).clamp(560.0, 760.0);
  return (
    maxWidth: math.min(targetWidth, availableWidth),
    maxHeightFactor: screenSize.height <= 0
        ? 0.0
        : math.min(targetHeight, availableHeight) / screenSize.height,
  );
}
```

Inside the dialog `Builder`, calculate the metrics from `MediaQuery.sizeOf(dialogContext)` and replace the fixed `960` and `0.88` values.

- [ ] **Step 4: Run focused and wrapper tests**

```powershell
flutter test test/emby_selection_dialog_layout_test.dart test/emby_media_selection_panel_test.dart
dart analyze lib/themes/nipaplay/widgets/emby_media_selection_dialog.dart test/emby_selection_dialog_layout_test.dart
```

Expected: all tests pass and analyzer reports no errors or warnings.

- [ ] **Step 5: Review and commit**

```powershell
git add lib/themes/nipaplay/widgets/emby_media_selection_dialog.dart test/emby_selection_dialog_layout_test.dart
git commit -m "fix: resize Emby selection dialog responsively"
```

- [ ] **Step 6: Push and build**

Push `feat/emby-media-selection`, dispatch `build-windows.yml` with `portable_only=true`, and verify exactly one artifact named `NipaPlay-Windows-x64-portable`.

