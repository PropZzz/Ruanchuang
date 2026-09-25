import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    'getThemeMode preserves an unimplemented remote endpoint error',
    () async {
      final error = RemoteUnavailableException(
        'Theme endpoint is unavailable.',
      );
      final local = _ThemeModeDataService(themeMode: 'dark');
      final remote = _ThemeModeDataService(getThemeModeError: error);

      await expectLater(
        composite(local: local, remote: remote).getThemeMode(),
        throwsA(same(error)),
      );

      expect(local.getThemeModeCalls, 0);
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
    'remote unavailable contract error does not attempt local write',
    () async {
      final error = RemoteUnavailableException('Remote endpoint unavailable.');
      final local = _ThemeModeDataService(
        setThemeModeError: StateError('Local cache write failed.'),
      );
      final remote = _ThemeModeDataService(setThemeModeError: error);

      await expectLater(
        composite(local: local, remote: remote).setThemeMode('dark'),
        throwsA(same(error)),
      );

      expect(local.setThemeModeCalls, 0);
    },
  );

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
    'an unsupported real remote endpoint is preserved without local fallback',
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

      await expectLater(
        composite(local: local, remote: remote).getThemeMode(),
        throwsA(isA<RemoteUnavailableException>()),
      );
      expect(local.getThemeModeCalls, 0);
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

  final fallbackErrors = <Object>[
    const SocketException('network unreachable'),
    http.ClientException('connection failed'),
    TimeoutException('remote timed out'),
    for (final status in [500, 502, 503, 504])
      ApiException('HTTP $status', statusCode: status),
  ];
  for (final error in fallbackErrors) {
    test('read falls back once for ${error.runtimeType} $error', () async {
      final local = _ThemeModeDataService(themeMode: 'dark');
      final remote = _ThemeModeDataService(getThemeModeError: error);

      expect(
        await composite(local: local, remote: remote).getThemeMode(),
        'dark',
      );
      expect(local.getThemeModeCalls, 1);
    });

    test('write falls back once for ${error.runtimeType} $error', () async {
      final local = _ThemeModeDataService();
      final remote = _ThemeModeDataService(setThemeModeError: error);

      await composite(local: local, remote: remote).setThemeMode('dark');

      expect(local.setThemeModeCalls, 1);
    });
  }

  final preservedErrors = <Object>[
    for (final status in [401, 403, 409, 422, 501])
      ApiException('HTTP $status', statusCode: status),
    const FormatException('invalid JSON'),
    RemoteDataException('response contract failed'),
    RemoteUnavailableException('reserved endpoint'),
    const ApiException('statusless API error'),
  ];
  for (final error in preservedErrors) {
    test('read preserves ${error.runtimeType} $error', () async {
      final local = _ThemeModeDataService(themeMode: 'dark');
      final remote = _ThemeModeDataService(getThemeModeError: error);

      await expectLater(
        composite(local: local, remote: remote).getThemeMode(),
        throwsA(same(error)),
      );
      expect(local.getThemeModeCalls, 0);
    });

    test('write preserves ${error.runtimeType} $error', () async {
      final local = _ThemeModeDataService();
      final remote = _ThemeModeDataService(setThemeModeError: error);

      await expectLater(
        composite(local: local, remote: remote).setThemeMode('dark'),
        throwsA(same(error)),
      );
      expect(local.setThemeModeCalls, 0);
    });
  }

  test('remote login failure never invokes local authentication', () async {
    final error = http.ClientException('network unavailable');
    final local = _IdentityDataService();
    final remote = _IdentityDataService(loginError: error);

    await expectLater(
      composite(local: local, remote: remote).login('alice', 'password'),
      throwsA(same(error)),
    );

    expect(local.loginCalls, 0);
    expect(local.activateAuthenticatedUserCalls, 0);
  });

  final authFailures = <Object>[
    const ApiException('unauthorized', statusCode: 401),
    http.ClientException('network unavailable'),
    TimeoutException('authentication timed out'),
    for (final status in [500, 502, 503, 504])
      ApiException('authentication $status', statusCode: status),
  ];
  for (final operation in ['login', 'register']) {
    for (final error in authFailures) {
      test(
        '$operation preserves $error without local authentication',
        () async {
          final local = _IdentityDataService();
          final remote = _IdentityDataService(
            loginError: operation == 'login' ? error : null,
            registerError: operation == 'register' ? error : null,
          );
          final service = composite(local: local, remote: remote);

          final authentication = operation == 'login'
              ? service.login('alice@example.com', 'password')
              : service.registerAccount(
                  username: 'alice@example.com',
                  password: 'password',
                );
          await expectLater(authentication, throwsA(same(error)));

          expect(local.loginCalls, 0);
          expect(local.registerCalls, 0);
          expect(local.activateAuthenticatedUserCalls, 0);
        },
      );
    }
  }

  test('valid remote login activates the stable local user id', () async {
    const user = UserAccount(
      userId: 'server-user-1',
      contactAddress: 'alice@example.com',
      displayName: 'Alice',
      identityState: ClientIdentityState.remoteAuthenticated,
    );
    final local = _IdentityDataService();
    final remote = _IdentityDataService(loginResult: true, currentUser: user);

    expect(
      await composite(
        local: local,
        remote: remote,
      ).login('alice@example.com', 'password'),
      isTrue,
    );

    expect(local.activatedUser?.userId, 'server-user-1');
    expect(local.activateAuthenticatedUserCalls, 1);
    expect(local.loginCalls, 0);
  });

  test(
    'remote login without a stable user id clears the remote session',
    () async {
      final local = _IdentityDataService();
      final remote = _IdentityDataService(
        loginResult: true,
        currentUser: const UserAccount(
          contactAddress: 'alice@example.com',
          displayName: 'Alice',
          identityState: ClientIdentityState.remoteAuthenticated,
        ),
      );

      await expectLater(
        composite(
          local: local,
          remote: remote,
        ).login('alice@example.com', 'password'),
        throwsA(isA<RemoteDataException>()),
      );

      expect(local.activateAuthenticatedUserCalls, 0);
      expect(remote.continueAsGuestCalls, 1);
    },
  );

  test(
    'local identity activation failure rolls back the remote client session',
    () async {
      final activationError = StateError('session persistence failed');
      final local = _IdentityDataService(activationError: activationError);
      final remote = _IdentityDataService(
        loginResult: true,
        currentUser: const UserAccount(
          userId: 'server-user-1',
          contactAddress: 'alice@example.com',
          displayName: 'Alice',
          identityState: ClientIdentityState.remoteAuthenticated,
        ),
      );

      await expectLater(
        composite(
          local: local,
          remote: remote,
        ).login('alice@example.com', 'password'),
        throwsA(same(activationError)),
      );

      expect(remote.continueAsGuestCalls, 1);
    },
  );

  test(
    'valid remote registration activates the stable local user id',
    () async {
      const user = UserAccount(
        userId: 'registered-user',
        contactAddress: 'new@example.com',
        displayName: 'New user',
        identityState: ClientIdentityState.remoteAuthenticated,
      );
      final local = _IdentityDataService();
      final remote = _IdentityDataService(
        registerResult: true,
        currentUser: user,
      );

      expect(
        await composite(
          local: local,
          remote: remote,
        ).registerAccount(username: 'new@example.com', password: 'password'),
        isTrue,
      );
      expect(local.activatedUser?.userId, 'registered-user');
      expect(local.registerCalls, 0);
    },
  );

  final logoutErrors = <Object>[
    http.ClientException('network unavailable'),
    TimeoutException('logout timeout'),
    for (final status in [403, 500, 502, 503, 504])
      ApiException('logout $status', statusCode: status),
  ];
  for (final error in logoutErrors) {
    test(
      'logout preserves $error after switching local state to guest',
      () async {
        final order = <String>[];
        final local = _IdentityDataService(order: order);
        final remote = _IdentityDataService(logoutError: error, order: order);

        await expectLater(
          composite(local: local, remote: remote).logout(),
          throwsA(same(error)),
        );

        expect(order, ['remote.logout', 'local.activateGuest']);
        expect(local.activateGuestCalls, 1);
      },
    );
  }

  test(
    'logout keeps the remote error primary if local guest switching fails',
    () async {
      final remoteError = http.ClientException('network unavailable');
      final localError = StateError('local session write failed');
      final local = _IdentityDataService(activateGuestError: localError);
      final remote = _IdentityDataService(logoutError: remoteError);

      await expectLater(
        composite(local: local, remote: remote).logout(),
        throwsA(same(remoteError)),
      );
      expect(local.activateGuestCalls, 1);
    },
  );

  test(
    'continueAsGuest clears remote client state and activates local guest',
    () async {
      final order = <String>[];
      final local = _IdentityDataService(order: order);
      final remote = _IdentityDataService(order: order);

      await composite(local: local, remote: remote).continueAsGuest();

      expect(order, ['remote.continueAsGuest', 'local.activateGuest']);
    },
  );
}

class _ThemeModeDataService implements DataService {
  _ThemeModeDataService({
    this.themeMode = 'system',
    this.getThemeModeError,
    this.setThemeModeError,
  });

  final String themeMode;
  final Object? getThemeModeError;
  final Object? setThemeModeError;
  int getThemeModeCalls = 0;
  int setThemeModeCalls = 0;

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

class _IdentityDataService implements DataService, LocalIdentityStore {
  _IdentityDataService({
    this.loginResult = false,
    this.registerResult = false,
    this.currentUser,
    this.loginError,
    this.registerError,
    this.activationError,
    this.logoutError,
    this.activateGuestError,
    this.order,
  });

  final bool loginResult;
  final bool registerResult;
  final UserAccount? currentUser;
  final Object? loginError;
  final Object? registerError;
  final Object? activationError;
  final Object? logoutError;
  final Object? activateGuestError;
  final List<String>? order;

  int loginCalls = 0;
  int registerCalls = 0;
  int activateAuthenticatedUserCalls = 0;
  int activateGuestCalls = 0;
  int continueAsGuestCalls = 0;
  UserAccount? activatedUser;

  @override
  Future<bool> login(String account, String password) async {
    loginCalls++;
    final error = loginError;
    if (error != null) throw error;
    return loginResult;
  }

  @override
  Future<bool> registerAccount({
    required String username,
    required String password,
  }) async {
    registerCalls++;
    final error = registerError;
    if (error != null) throw error;
    return registerResult;
  }

  @override
  Future<UserAccount?> getCurrentUser() async => currentUser;

  @override
  Future<void> activateAuthenticatedUser(UserAccount user) async {
    activateAuthenticatedUserCalls++;
    final error = activationError;
    if (error != null) throw error;
    activatedUser = user;
  }

  @override
  Future<void> activateGuest() async {
    activateGuestCalls++;
    order?.add('local.activateGuest');
    final error = activateGuestError;
    if (error != null) throw error;
  }

  @override
  Future<void> logout() async {
    order?.add('remote.logout');
    final error = logoutError;
    if (error != null) throw error;
  }

  @override
  Future<void> continueAsGuest() async {
    continueAsGuestCalls++;
    order?.add('remote.continueAsGuest');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
