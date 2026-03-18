// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

class IcsSaveResult {
  final String label;
  final String? path;

  const IcsSaveResult({required this.label, this.path});
}

class IcsFileSaver {
  static Future<IcsSaveResult> save(String ics, {required String fileName}) async {
    final bytes = utf8.encode(ics);
    final blob = html.Blob([bytes], 'text/calendar;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final a = html.AnchorElement(href: url)
      ..download = fileName
      ..style.display = 'none';

    html.document.body?.append(a);
    a.click();
    a.remove();

    html.Url.revokeObjectUrl(url);

    return const IcsSaveResult(label: 'download');
  }
}
