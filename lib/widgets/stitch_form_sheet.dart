import 'package:flutter/material.dart';

import '../utils/app_strings.dart';

class StitchFormSheet extends StatelessWidget {
  const StitchFormSheet({
    super.key,
    required this.title,
    required this.content,
    required this.onCancel,
    required this.onConfirm,
    required this.confirmLabel,
  });

  final String title;
  final Widget content;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = media.size.height * 0.9 - media.viewInsets.bottom;

    return Material(
      key: const ValueKey('stitch-form-sheet'),
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: maxHeight.clamp(280, 900).toDouble(),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              16 + media.viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.of(context, 'btn_close'),
                      onPressed: onCancel,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: content,
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cancelButton = TextButton(
                      onPressed: onCancel,
                      child: Text(AppStrings.of(context, 'btn_cancel')),
                    );
                    final confirmButton = FilledButton(
                      onPressed: onConfirm,
                      child: Text(confirmLabel),
                    );
                    if (constraints.maxWidth < 420) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          confirmButton,
                          Align(
                            alignment: Alignment.centerRight,
                            child: cancelButton,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [cancelButton, const Spacer(), confirmButton],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
