import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/api_client.dart';
import 'package:shixuzhipei/services/composite_data_service.dart';
import 'package:shixuzhipei/services/data_service.dart';
import 'package:shixuzhipei/services/remote_data_service.dart';

void main() {
  CompositeDataService composite({
    required DataService local,
    required DataService remote,
  }) => CompositeDataService(
    local: local,
    remote: remote,
    preferRemoteReads: true,
  );

  test(
    'getThemeMode falls back locally for an unimplemented remote endpoint',
    () async {
      final local = _ThemeModeDataService(themeMode: 'dark');
      final remote = _ThemeModeDataService(
        getThemeModeError: RemoteUnavailableException(
          'Theme endpoint is unavailable.',
        ),
      );

      final result = await composite(
        local: local,
        remote: remote,
      ).getThemeMode();

      expect(result, 'dark');
      expect(local.getThemeModeCalls, 1);
    },
  );

  test('getThemeMode rethrows a remote 401 without calling local', () async {
    final error = ApiException('Unauthorized', statusCode: 401);
    final local = _ThemeModeDataService(themeMode: 'dark');
    final remote = _ThemeModeDataService(getThemeModeError: error);

    await expectLater(
      composite(local: local, remote: remote).getThemeMode(),
      throwsA(same(error)),
    );

    expect(local.getThemeModeCalls, 0);
  });

  test(
    'getThemeMode rethrows a remote ApiException without a status code without calling local',
    () async {
      final error = ApiException('Transport failure');
      final local = _ThemeModeDataService(themeMode: 'dark');
      final remote = _ThemeModeDataService(getThemeModeError: error);

      await expectLater(
        composite(local: local, remote: remote).getThemeMode(),
        throwsA(same(error)),
      );

      expect(local.getThemeModeCalls, 0);
    },
  );

  test(
    'getThemeMode rethrows a remote StateError without calling local',
    () async {
      final error = StateError('Remote response violated its contract.');
      final local = _ThemeModeDataService(themeMode: 'dark');
      final remote = _ThemeModeDataService(getThemeModeError: error);

      await expectLater(
        composite(local: local, remote: remote).getThemeMode(),
        throwsA(same(error)),
      );

      expect(local.getThemeModeCalls, 0);
    },
  );

  test('getThemeMode falls back locally for a remote 500', () async {
    final local = _ThemeModeDataService(themeMode: 'dark');
    final remote = _ThemeModeDataService(
      getThemeModeError: ApiException('Server error', statusCode: 500),
    );

    final result = await composite(local: local, remote: remote).getThemeMode();

    expect(result, 'dark');
    expect(local.getThemeModeCalls, 1);
  });

  test('setThemeMode rethrows a remote 401 without calling local', () async {
    final error = ApiException('Unauthorized', statusCode: 401);
    final local = _ThemeModeDataService();
    final remote = _ThemeModeDataService(setThemeModeError: error);

    await expectLater(
      composite(local: local, remote: remote).setThemeMode('dark'),
      throwsA(same(error)),
    );

    expect(local.setThemeModeCalls, 0);
  });

  test(
    'setThemeMode succeeds when remote commits but local synchronization fails',
    () async {
      final local = _ThemeModeDataService(
        setThemeModeError: StateError('Local cache write failed.'),
      );
      final remote = _ThemeModeDataService();

      await composite(local: local, remote: remote).setThemeMode('dark');

      expect(remote.setThemeModeCalls, 1);
      expect(local.setThemeModeCalls, 1);
    },
  );

  test(
    'login preserves the remote result when local synchronization fails',
    () async {
      final local = _ThemeModeDataService(
        loginError: StateError('Local cache write failed.'),
      );
      final remote = _ThemeModeDataService(loginResult: true);

      final result = await composite(
        local: local,
        remote: remote,
      ).login('alice@example.com', 'secret');

      expect(result, isTrue);
      expect(remote.loginCalls, 1);
      expect(local.loginCalls, 1);
    },
  );

  test('remote unavailable followed by local failure still throws', () async {
    final error = RemoteUnavailableException('Remote endpoint unavailable.');
    final local = _ThemeModeDataService(
      setThemeModeError: StateError('Local cache write failed.'),
    );
    final remote = _ThemeModeDataService(setThemeModeError: error);

    await expectLater(
      composite(local: local, remote: remote).setThemeMode('dark'),
      throwsA(isA<StateError>()),
    );

    expect(local.setThemeModeCalls, 1);
  });

  test('remote contract failure rethrows without calling local', () async {
    final error = RemoteDataException('Expected object response.');
    final local = _ThemeModeDataService(themeMode: 'dark');
    final remote = _ThemeModeDataService(getThemeModeError: error);

    await expectLater(
      composite(local: local, remote: remote).getThemeMode(),
      throwsA(same(error)),
    );

    expect(local.getThemeModeCalls, 0);
  });

  test(
    'getScheduleEntries returns the real remote schedule without calling local',
    () async {
      final remote = RemoteDataService(
        apiClient: ApiClient(
          baseUrl: 'https://example.test',
          httpClient: MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.path, '/schedule');
            return http.Response(
              jsonEncode([
                {'id': 'remote-1', 'title': 'Remote planning'},
              ]),
              200,
            );
          }),
        ),
      );
      final local = _ScheduleDataService();

      final result = await composite(
        local: local,
        remote: remote,
      ).getScheduleEntries();

      expect(result, hasLength(1));
      expect(result.single.id, 'remote-1');
      expect(result.single.title, 'Remote planning');
      expect(local.getScheduleEntriesCalls, 0);
    },
  );

  test(
    'a malformed real schedule collection rethrows without calling local',
    () async {
      final remote = RemoteDataService(
        apiClient: ApiClient(
          baseUrl: 'https://example.test',
          httpClient: MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.path, '/schedule');
            return http.Response(
              jsonEncode([
                {'id': 'remote-1', 'title': 'Remote planning'},
                'malformed schedule entry',
              ]),
              200,
            );
          }),
        ),
      );
      final local = _ScheduleDataService();

      await expectLater(
        composite(local: local, remote: remote).getScheduleEntries(),
        throwsA(
          allOf(
            isA<RemoteDataException>(),
            isNot(isA<RemoteUnavailableException>()),
          ),
        ),
      );

      expect(local.getScheduleEntriesCalls, 0);
    },
  );

  test(
    'an unsupported real remote endpoint is unavailable and falls back locally',
    () async {
      final remote = RemoteDataService(
        apiClient: ApiClient(
          baseUrl: 'https://example.test',
          httpClient: MockClient((_) async {
            throw StateError(
              'Unsupported endpoint must not make an HTTP call.',
            );
          }),
        ),
      );
      final local = _ThemeModeDataService(themeMode: 'dark');

      await expectLater(
        remote.getThemeMode(),
        throwsA(isA<RemoteUnavailableException>()),
      );

      final result = await composite(
        local: local,
        remote: remote,
      ).getThemeMode();

      expect(result, 'dark');
      expect(local.getThemeModeCalls, 1);
    },
  );

  test(
    'a malformed real auth response rethrows without calling local',
    () async {
      final remote = RemoteDataService(
        apiClient: ApiClient(
          baseUrl: 'https://example.test',
          httpClient: MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.path, '/auth/me');
            return http.Response(jsonEncode([]), 200);
          }),
        ),
      );
      final local = _CurrentUserDataService();

      await expectLater(
        composite(local: local, remote: remote).getCurrentUser(),
        throwsA(
          allOf(
            isA<RemoteDataException>(),
            isNot(isA<RemoteUnavailableException>()),
          ),
        ),
      );

      expect(local.getCurrentUserCalls, 0);
    },
  );
}

class _ThemeModeDataService implements DataService {
  _ThemeModeDataService({
    this.themeMode = 'system',
    this.getThemeModeError,
    this.setThemeModeError,
    this.loginResult = false,
    this.loginError,
  });

  final String themeMode;
  final Object? getThemeModeError;
  final Object? setThemeModeError;
  final bool loginResult;
  final Object? loginError;
  int getThemeModeCalls = 0;
  int setThemeModeCalls = 0;
  int loginCalls = 0;

  @override
  Future<String> getThemeMode() async {
    getThemeModeCalls++;
    final error = getThemeModeError;
    if (error != null) throw error;
    return themeMode;
  }

  @override
  Future<void> setThemeMode(String themeMode) async {
    setThemeModeCalls++;
    final error = setThemeModeError;
    if (error != null) throw error;
  }

  @override
  Future<bool> login(String account, String password) async {
    loginCalls++;
    final error = loginError;
    if (error != null) throw error;
    return loginResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScheduleDataService implements DataService {
  int getScheduleEntriesCalls = 0;

  @override
  Future<List<ScheduleEntry>> getScheduleEntries() async {
    getScheduleEntriesCalls++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CurrentUserDataService implements DataService {
  int getCurrentUserCalls = 0;

  @override
  Future<UserAccount?> getCurrentUser() async {
    getCurrentUserCalls++;
    return const UserAccount(
      contactAddress: 'local@example.test',
      displayName: 'Local user',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
