import 'package:flutter/material.dart';

class FatalErrorDialog extends StatelessWidget {
  const FatalErrorDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        '\u64cd\u4f5c\u672a\u5b8c\u6210',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '\u5e94\u7528\u9047\u5230\u5f02\u5e38\uff0c\u5df2\u81ea\u52a8\u8bb0\u5f55\u3002\u8bf7\u8fd4\u56de\u540e\u91cd\u8bd5\uff1b\u5982\u679c\u95ee\u9898\u6301\u7eed\uff0c\u8bf7\u5230\u201c\u6211\u7684 > \u8bca\u65ad\u201d\u67e5\u770b\u65e5\u5fd7\u3002',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('\u5173\u95ed'),
        ),
      ],
    );
  }
}
