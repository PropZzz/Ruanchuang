import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shixuzhipei/services/api_client.dart';
import 'package:shixuzhipei/services/composite_data_service.dart';
import 'package:shixuzhipei/services/data_service.dart';
import 'package:shixuzhipei/services/local_data_service.dart';
import 'package:shixuzhipei/services/local_persistence/local_persistence.dart';
import 'package:shixuzhipei/services/remote_data_service.dart';
import 'package:shixuzhipei/services/service_result.dart';
import 'package:shixuzhipei/services/service_operations.dart';

void main() {
  test(
    'typed favorite preference uses the same explicit local route as legacy',
    () async {
      final composite = CompositeDataService(
        local: LocalDataService.forPersistence(InMemoryLocalPersistence()),
        remote: RemoteDataService(),
      );
      final operations = ServiceOperations(composite);
      final saved = await operations.setFavoriteDevice('device-1');
      expect((saved as ServiceSuccess).source, ServiceSource.local);
      expect(saved.offline, isFalse);
      expect(await composite.getFavoriteDevice(), 'device-1');
      final loaded = await operations.getFavoriteDevice();
      expect((loaded as ServiceSuccess<String?>).value, 'device-1');
      expect(loaded.source, ServiceSource.local);
      expect(loaded.offline, isFalse);
    },
  );
  LocalDataService local() =>
      LocalDataService.forPersistence(InMemoryLocalPersistence());
  RemoteDataService remote(Future<http.Response> Function(http.Request) send) =>
      RemoteDataService(
        apiClient: ApiClient(
          baseUrl: 'https://server.test',
          httpClient: MockClient(send),
        ),
      );

  test(
    'save failure retains a separate draft even if the writer mutates its copy',
    () async {
      final draft = <String>['unsaved title'];
      final operations = ServiceOperations(
        CompositeDataService(
          local: local(),
          remote: _Reject(const ApiException('Conflict', statusCode: 409)),
        ),
      );
      final saved = await operations.saveDraft(
        draft: draft,
        copy: (value) => List<String>.of(value),
        save: (service, value) async {
          final title = value.single;
          value.clear();
          await service.setThemeMode(title);
        },
      );
      draft.clear();
      expect(saved.draft, ['unsaved title']);
      expect(
        (saved.result as ServiceFailure).problem.kind,
        ServiceFailureKind.conflict,
      );
      expect(
        (saved.result as ServiceFailure).problem.commitState,
        ServiceCommitState.notSaved,
      );
    },
  );

  test(
    'retained draft can be retried and read back from actual local storage',
    () async {
      final persistence = InMemoryLocalPersistence();
      final service = LocalDataService.forPersistence(persistence);
      final operations = ServiceOperations(service);
      final failed =
          await ServiceOperations(
            CompositeDataService(
              local: local(),
              remote: _Reject(const ApiException('Rejected', statusCode: 422)),
            ),
          ).saveDraft(
            draft: 'dark',
            copy: (value) => value,
            save: (s, value) => s.setThemeMode(value),
          );
      expect(failed.result, isA<ServiceFailure<void>>());
      final saved = await operations.saveDraft(
        draft: failed.draft,
        copy: (value) => value,
        save: (s, value) => s.setThemeMode(value),
      );
      expect(saved.result, isA<ServiceSuccess<void>>());
      expect((saved.result as ServiceSuccess).source, ServiceSource.local);
      expect((saved.result as ServiceSuccess).offline, isFalse);
      final reloaded = LocalDataService.forPersistence(persistence);
      final result = await ServiceOperations(
        reloaded,
      ).read((s) => s.getThemeMode());
      expect((result as ServiceSuccess<String>).value, 'dark');
    },
  );

  test(
    'remote commit with failed cache returns success and disables stale fallback',
    () async {
      final error = StateError('cache failed');
      final service = CompositeDataService(
        local: _Reject(error),
        remote: remote(
          (request) async => request.method == 'PUT'
              ? http.Response('{}', 200)
              : http.Response('offline', 503),
        ),
      );
      final result = await service.writeResult((s) => s.setThemeMode('dark'));
      final success = result as ServiceSuccess<void>;
      expect(success.source, ServiceSource.remote);
      expect(success.cacheWarning?.cause, same(error));
      expect(success.offline, isFalse);
      final read = await service.readResult((s) => s.getThemeMode());
      expect((read as ServiceFailure).problem.source, ServiceSource.remote);
    },
  );

  test('concurrent reads keep distinct source and offline metadata', () async {
    final delayed = Completer<http.Response>();
    final service = CompositeDataService(
      local: local(),
      remote: remote(
        (request) async => request.url.path == '/settings'
            ? delayed.future
            : http.Response('offline', 503),
      ),
    );
    final first = service.readResult((s) => s.getThemeMode());
    final second = await service.readResult((s) => s.getGoals());
    delayed.complete(http.Response('{"themeMode":"dark"}', 200));
    final remoteResult = (await first) as ServiceSuccess;
    expect(remoteResult.source, ServiceSource.remote);
    expect(remoteResult.offline, isFalse);
    final localResult = second as ServiceSuccess;
    expect(localResult.source, ServiceSource.local);
    expect(localResult.offline, isTrue);
  });

  test(
    'explicit guest mode returns local success without being offline',
    () async {
      final service = CompositeDataService(
        local: local(),
        remote: RemoteDataService(),
      );
      await service.startGuestSession();
      final result = await ServiceOperations(
        service,
      ).write((s) => s.setThemeMode('dark'));
      expect((result as ServiceSuccess).source, ServiceSource.local);
      expect(result.offline, isFalse);
    },
  );

  test('success and successful empty data keep their remote source', () async {
    final service = CompositeDataService(
      local: local(),
      remote: remote((_) async => http.Response('[]', 200)),
    );
    final result = await service.readResult((s) => s.getGoals());
    expect(result, isA<ServiceSuccess>());
    final success = result as ServiceSuccess;
    expect(success.value, isEmpty);
    expect(success.source, ServiceSource.remote);
    expect(success.offline, isFalse);
  });

  final failures = <Object, ServiceFailureKind>{
    const ApiException('private response', statusCode: 401):
        ServiceFailureKind.unauthorized,
    const ApiException('private response', statusCode: 403):
        ServiceFailureKind.forbidden,
    const ApiException('private response', statusCode: 409):
        ServiceFailureKind.conflict,
    const ApiException('private response', statusCode: 422):
        ServiceFailureKind.validation,
    const ApiException('private response', statusCode: 501):
        ServiceFailureKind.reserved,
    const ApiException('private response', statusCode: 505):
        ServiceFailureKind.server,
    const FormatException('secret invalid json'): ServiceFailureKind.parsing,
    RemoteDataException('secret wrong shape'): ServiceFailureKind.contract,
  };
  for (final entry in failures.entries) {
    test('${entry.value} returns a real failure on read and write', () async {
      final cache = local();
      await cache.setThemeMode('dark');
      final service = CompositeDataService(
        local: cache,
        remote: _Reject(entry.key),
      );
      final read = await service.readResult((s) => s.getThemeMode());
      final write = await service.writeResult((s) => s.setThemeMode('light'));
      for (final result in [read, write]) {
        final problem = (result as ServiceFailure).problem;
        expect(problem.kind, entry.value);
        expect(problem.cause, same(entry.key));
        expect(problem.message, isNot(contains('secret')));
        expect(problem.message, isNot(contains('private response')));
        expect(problem.nextAction, isNotEmpty);
      }
      expect(await cache.getThemeMode(), 'dark');
    });
  }

  for (final error in <Object>[
    const SocketException('unreachable'),
    TimeoutException('timeout'),
    http.ClientException('connection failed'),
    const ApiException('retry', statusCode: 500),
    const ApiException('retry', statusCode: 502),
    const ApiException('retry', statusCode: 503),
    const ApiException('retry', statusCode: 504),
  ]) {
    test('$error uses an explicitly offline local result', () async {
      final cache = local();
      final service = CompositeDataService(
        local: cache,
        remote: _Reject(error),
      );
      final write = await service.writeResult((s) => s.setThemeMode('dark'));
      final success = write as ServiceSuccess<void>;
      expect(success.source, ServiceSource.local);
      expect(success.offline, isTrue);
      expect(success.fallbackCause?.cause, same(error));
      expect(success.remoteCommitUncertain, isTrue);
      final read = await service.readResult((s) => s.getThemeMode());
      expect((read as ServiceSuccess<String>).value, 'dark');
      expect(read.offline, isTrue);
    });
  }

  test(
    'real HTTP invalid JSON and invalid collection do not fall back',
    () async {
      for (final body in [
        '{broken',
        jsonEncode({'wrong': 'shape'}),
      ]) {
        final service = CompositeDataService(
          local: local(),
          remote: remote((_) async => http.Response(body, 200)),
        );
        final result = await service.readResult((s) => s.getGoals());
        expect(result, isA<ServiceFailure>());
      }
    },
  );

  test(
    'malformed write response preserves both draft and unchanged cache',
    () async {
      final cache = local();
      await cache.setThemeMode('light');
      final service = CompositeDataService(
        local: cache,
        remote: remote((_) async => http.Response('{broken', 200)),
      );
      final saved = await ServiceOperations(service).saveDraft(
        draft: 'dark',
        copy: (s) => s,
        save: (s, value) => s.setThemeMode(value),
      );
      expect(saved.draft, 'dark');
      final failure = saved.result as ServiceFailure;
      expect(failure.problem.kind, ServiceFailureKind.parsing);
      expect(failure.problem.commitState, ServiceCommitState.unknown);
      expect(await cache.getThemeMode(), 'light');
    },
  );

  test(
    'local fallback failure retains original and fallback diagnostic causes',
    () async {
      final offline = TimeoutException('remote timeout');
      final disk = FileSystemException('disk full');
      final result = await CompositeDataService(
        local: _Reject(disk),
        remote: _Reject(offline),
      ).writeResult((s) => s.setThemeMode('dark'));
      final failure = result as ServiceFailure;
      expect(failure.problem.source, ServiceSource.local);
      expect(failure.problem.cause, same(disk));
      expect(failure.fallbackCause?.cause, same(offline));
    },
  );

  test(
    'remote-only operation exposes transport failure without inventing local success',
    () async {
      final result = await ServiceOperations(
        remote((_) async => throw const SocketException('offline')),
      ).write((s) => s.setThemeMode('dark'));
      final failure = result as ServiceFailure;
      expect(failure.problem.kind, ServiceFailureKind.network);
      expect(failure.problem.source, ServiceSource.remote);
      expect(failure.problem.commitState, ServiceCommitState.unknown);
    },
  );
}

class _Reject implements DataService {
  _Reject(this.error);
  final Object error;
  @override
  Future<String> getThemeMode() async => throw error;
  @override
  Future<void> setThemeMode(String value) async => throw error;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
