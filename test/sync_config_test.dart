import 'package:flutter_test/flutter_test.dart';
import 'package:crocuta/services/sync_service.dart';

void main() {
  test('il codice di configurazione riporta indirizzo e segreto', () {
    final c = SyncConfig(
      'https://script.google.com/macros/s/abc/exec',
      'f00d' * 12,
    );
    final back = SyncConfig.fromSetupCode('  ${c.setupCode}\n');
    expect(back?.url, c.url);
    expect(back?.secret, c.secret);
  });

  test('la maiuscola che la tastiera mette all\'inizio non conta', () {
    final c = SyncConfig(
      'https://script.google.com/macros/s/abc/exec',
      'ab' * 24,
    );
    final typed = 'C${c.setupCode.substring(1)}';
    expect(SyncConfig.fromSetupCode(typed)?.secret, c.secret);
  });

  test('un URL o testo qualunque non e\' un codice', () {
    expect(
      SyncConfig.fromSetupCode('https://script.google.com/x/exec'),
      isNull,
    );
    expect(SyncConfig.fromSetupCode('crocuta:non-base64!!'), isNull);
  });
}
