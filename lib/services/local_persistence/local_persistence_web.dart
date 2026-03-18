// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'local_persistence.dart';

class WebLocalPersistence implements LocalPersistence {
  static const _key = 'sxzppp_data_v1';

  @override
  Future<bool> exists() async {
    return html.window.localStorage.containsKey(_key);
  }

  @override
  Future<String?> read() async {
    return html.window.localStorage[_key];
  }

  @override
  Future<void> write(String content) async {
    html.window.localStorage[_key] = content;
  }
}

LocalPersistence createLocalPersistence() => WebLocalPersistence();