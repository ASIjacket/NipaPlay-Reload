import 'package:flutter/material.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:provider/provider.dart';

typedef EmbySelectionContentBuilder = Widget Function(
  ValueChanged<bool> close,
);

/// Shows media selection inside the standard desktop window surface.
Future<bool?> showEmbyMediaSelectionDialog({
  required BuildContext context,
  required bool Function() isSaving,
  required VoidCallback onDismiss,
  required EmbySelectionContentBuilder contentBuilder,
}) {
  final enableAnimation =
      context.read<AppearanceSettingsProvider>().enablePageAnimation;
  final guardKey = GlobalKey<_EmbySelectionDialogGuardState>();
  return NipaplayWindow.show<bool>(
    context: context,
    enableAnimation: enableAnimation,
    barrierDismissible: false,
    child: Builder(
      builder: (dialogContext) {
        return NipaplayWindowScaffold(
          maxWidth: 960,
          maxHeightFactor: 0.88,
          onClose: () => guardKey.currentState?.dismiss(),
          child: _EmbySelectionDialogGuard(
            key: guardKey,
            isSaving: isSaving,
            onDismiss: onDismiss,
            contentBuilder: contentBuilder,
          ),
        );
      },
    ),
  );
}

class _EmbySelectionDialogGuard extends StatefulWidget {
  const _EmbySelectionDialogGuard({
    super.key,
    required this.isSaving,
    required this.onDismiss,
    required this.contentBuilder,
  });

  final bool Function() isSaving;
  final VoidCallback onDismiss;
  final EmbySelectionContentBuilder contentBuilder;

  @override
  State<_EmbySelectionDialogGuard> createState() =>
      _EmbySelectionDialogGuardState();
}

class _EmbySelectionDialogGuardState extends State<_EmbySelectionDialogGuard> {
  bool _allowPop = false;
  bool _closing = false;

  void dismiss() {
    if (_closing || widget.isSaving()) return;
    widget.onDismiss();
    _complete(false);
  }

  void _complete(bool result) {
    if (_closing) return;
    _closing = true;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop<bool>(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) dismiss();
      },
      child: widget.contentBuilder(_complete),
    );
  }
}
