import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'remote_data_service.dart';

enum ServiceSource { remote, local, unknown }

enum ServiceFailureKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  conflict,
  validation,
  reserved,
  server,
  http,
  parsing,
  contract,
  unexpected,
}

/// Unknown is deliberate: a lost response is not proof that a write failed.
enum ServiceCommitState { notApplicable, notSaved, unknown }

/// Diagnostic cause/stack are never user-facing response bodies.
class ServiceProblem {
  const ServiceProblem({
    required this.cause,
    required this.stackTrace,
    required this.source,
    required this.commitState,
  });

  final Object cause;
  final StackTrace stackTrace;
  final ServiceSource source;
  final ServiceCommitState commitState;

  ServiceFailureKind get kind => switch (cause) {
    ApiException(statusCode: 401) => ServiceFailureKind.unauthorized,
    ApiException(statusCode: 403) => ServiceFailureKind.forbidden,
    ApiException(statusCode: 409) => ServiceFailureKind.conflict,
    ApiException(statusCode: 422) => ServiceFailureKind.validation,
    ApiException(statusCode: 501) => ServiceFailureKind.reserved,
    ApiException(statusCode: final code?) when code >= 500 =>
      ServiceFailureKind.server,
    ApiException() => ServiceFailureKind.http,
    TimeoutException() => ServiceFailureKind.timeout,
    SocketException() ||
    http.ClientException() ||
    RemoteUnavailableException() => ServiceFailureKind.network,
    FormatException() => ServiceFailureKind.parsing,
    RemoteDataException() ||
    TypeError() ||
    StateError() => ServiceFailureKind.contract,
    _ => ServiceFailureKind.unexpected,
  };

  /// Safe presentation key and default copy; pages may localize by [kind].
  String get message => switch (kind) {
    ServiceFailureKind.unauthorized => 'Please sign in again.',
    ServiceFailureKind.forbidden => 'This account does not have permission.',
    ServiceFailureKind.conflict =>
      'The data changed or conflicts with this request.',
    ServiceFailureKind.validation => 'The submitted fields were rejected.',
    ServiceFailureKind.reserved => 'This capability is not implemented.',
    ServiceFailureKind.network => 'The service could not be reached.',
    ServiceFailureKind.timeout => 'The request timed out.',
    ServiceFailureKind.parsing => 'The service response could not be parsed.',
    ServiceFailureKind.contract =>
      'The service response violated its contract.',
    ServiceFailureKind.server => 'The service returned a server error.',
    _ => 'The operation could not be completed.',
  };

  String get nextAction => switch (kind) {
    ServiceFailureKind.unauthorized => 'Sign in, then retry.',
    ServiceFailureKind.forbidden => 'Use an account with permission.',
    ServiceFailureKind.conflict => 'Refresh and compare before saving again.',
    ServiceFailureKind.validation => 'Correct the fields and retry.',
    ServiceFailureKind.reserved => 'Use an available manual alternative.',
    _ when commitState == ServiceCommitState.unknown =>
      'Refresh to check whether the write was saved before retrying.',
    _ => 'Keep your input and retry or report the diagnostic error.',
  };
}

sealed class ServiceResult<T> {
  const ServiceResult();

  /// Compatibility boundary: preserve the original exception and its stack.
  T unwrap() => switch (this) {
    ServiceSuccess<T>(:final value) => value,
    ServiceFailure<T>(:final problem) => Error.throwWithStackTrace(
      problem.cause,
      problem.stackTrace,
    ),
  };
}

final class ServiceSuccess<T> extends ServiceResult<T> {
  const ServiceSuccess(
    this.value, {
    required this.source,
    this.fallbackCause,
    this.cacheWarning,
    this.remoteCommitUncertain = false,
  });
  final T value;
  final ServiceSource source;
  final ServiceProblem? fallbackCause;
  final ServiceProblem? cacheWarning;
  final bool remoteCommitUncertain;
  bool get offline => fallbackCause != null;
}

final class ServiceFailure<T> extends ServiceResult<T> {
  const ServiceFailure(this.problem, {this.fallbackCause});
  final ServiceProblem problem;
  final ServiceProblem? fallbackCause;
}

bool allowsLocalFallback(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is http.ClientException ||
    error is RemoteUnavailableException ||
    (error is ApiException &&
        const {500, 502, 503, 504}.contains(error.statusCode));

ServiceProblem serviceProblem(
  Object error,
  StackTrace stack,
  ServiceSource source, {
  required bool write,
}) => ServiceProblem(
  cause: error,
  stackTrace: stack,
  source: source,
  commitState: !write
      ? ServiceCommitState.notApplicable
      : error is ApiException &&
            error.statusCode != null &&
            error.statusCode! >= 400 &&
            error.statusCode! < 500
      ? ServiceCommitState.notSaved
      : ServiceCommitState.unknown,
);
