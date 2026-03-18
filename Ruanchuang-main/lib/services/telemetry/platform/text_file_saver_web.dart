// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

class SaveTextResult {
  final String? path;
  final String? error;

  const SaveTextResult({this.path, this.error});
}

class TextFileSaver {
  static Future<SaveTextResult> save(
    String content, {
    required String fileName,
  }) async {
    try {
      final bytes = utf8.encode(content);
      final blob = html.Blob([bytes], 'text/plain;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);

      final a = html.AnchorElement(href: url)
        ..download = fileName
        ..style.display = 'none';

      html.document.body?.children.add(a);
      a.click();
      a.remove();

      html.Url.revokeObjectUrl(url);
      return const SaveTextResult(path: 'download');
    } catch (e) {
      return SaveTextResult(error: e.toString());
    }
  }
}