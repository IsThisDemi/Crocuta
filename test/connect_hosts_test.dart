import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/services/connect.dart';

void main() {
  test('prima gli indirizzi della rete di casa, per ultimi i link-local', () {
    // Come si annuncia il Mac col cavo dell'iPhone attaccato: il
    // link-local arrivava per primo e il collegamento scadeva.
    final hosts = connectHosts([
      '169.254.12.76',
      '127.0.0.1',
      'fe80::1',
      '192.168.0.81',
    ], 'MacBook-Pro-di-Alex-2.local.');
    expect(hosts.first, '192.168.0.81');
    expect(hosts, isNot(contains('127.0.0.1')));
    expect(hosts.indexOf('169.254.12.76'), greaterThan(0));
    expect(hosts.last, 'MacBook-Pro-di-Alex-2.local.');
  });

  test('le reti private sono tutte "di casa", i doppioni spariscono', () {
    final hosts = connectHosts([
      '100.64.0.2',
      '172.20.1.5',
      '10.0.0.7',
      '10.0.0.7',
    ], null);
    expect(hosts.take(2), containsAll(['172.20.1.5', '10.0.0.7']));
    expect(hosts.last, '100.64.0.2');
    expect(hosts.length, 3);
  });
}
