import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../services/api_client.dart';
import '../services/remote_data_service.dart';

/// Turn transport failures into a next step without displaying response bodies
/// or claiming that an unsuccessful request was saved locally.
String serviceFailureMessage(
  BuildContext context,
  Object? error, {
  required String fallback,
}) {
  final zh = Localizations.localeOf(context).languageCode.startsWith('zh');
  if (error is TimeoutException) {
    return zh
        ? '请求超时，请检查连接后重试。'
        : 'The request timed out. Check your connection and retry.';
  }
  if (error is RemoteUnavailableException || error is http.ClientException) {
    return zh
        ? '当前无法连接服务，请检查网络后重试。'
        : 'Cannot reach the service. Check your network and retry.';
  }
  if (error is! ApiException) return fallback;
  return switch (error.statusCode) {
    401 => zh ? '请到“我的”重新登录后重试。' : 'Sign in again from Profile, then retry.',
    403 =>
      zh
          ? '当前账号没有此项权限，请切换有权限的账号。'
          : 'This account does not have permission. Switch to an authorized account.',
    409 =>
      zh
          ? '数据已变化或发生冲突，请刷新后比较并重试。'
          : 'The data changed or conflicts. Refresh, compare the changes, and retry.',
    422 =>
      zh
          ? '提交内容未通过校验，请检查输入后重试。'
          : 'The input was rejected. Check the fields and retry.',
    501 =>
      zh
          ? '此功能尚未接入，当前操作未完成。'
          : 'This feature is not connected yet. The operation did not complete.',
    final code? when code >= 500 =>
      zh
          ? '服务暂时不可用，请稍后重试。'
          : 'The service is temporarily unavailable. Please retry later.',
    _ => fallback,
  };
}
