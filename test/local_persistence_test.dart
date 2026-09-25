import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/services/local_persistence/local_persistence.dart';

void main() {
  test('local persistence namespace encoding is stable and path safe', () {
    const rawNamespace = r'user:../张三\data';

    final encoded = encodeLocalPersistenceNamespace(rawNamespace);

    expect(encoded, 'dXNlcjouLi_lvKDkuIlcZGF0YQ');
    expect(encoded, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(encoded, isNot(contains('..')));
    expect(encoded, isNot(contains('/')));
    expect(encoded, isNot(contains(r'\')));
  });

  test('in-memory persistence isolates logical namespaces', () async {
    final persistence = InMemoryLocalPersistence();

    await persistence.write('guest-value', namespace: 'guest');
    await persistence.write('user-value', namespace: 'user:abc');

    expect(await persistence.read(namespace: 'guest'), 'guest-value');
    expect(await persistence.read(namespace: 'user:abc'), 'user-value');
    expect(await persistence.exists(namespace: 'guest'), isTrue);
    expect(await persistence.exists(namespace: 'user:missing'), isFalse);
  });

  test('default persistence namespace remains the legacy slot', () async {
    final persistence = InMemoryLocalPersistence();

    await persistence.write('legacy-value');
    await persistence.write('guest-value', namespace: 'guest');

    expect(await persistence.read(), 'legacy-value');
    expect(
      await persistence.read(namespace: legacyLocalNamespace),
      'legacy-value',
    );
    expect(await persistence.read(namespace: 'guest'), 'guest-value');
  });
}
