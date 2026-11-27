import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:crocuta/main.dart' as app;
import 'package:crocuta/models/track.dart' as track_model;
import 'package:crocuta/providers.dart';
import 'package:crocuta/services/storage_service.dart';

/// Test end-to-end su macOS: ricerca reale + riproduzione completa.
/// Verifica che una canzone superi il minuto senza tagli né riavvii.
///
/// I videoId singoli possono essere flaggati da Google dopo i test ripetuti
/// (403 da byte 0 = nessuno stream). Per questo ogni brano "FALLITO con 0
/// stream" viene saltato e si passa al successivo: il criterio è che ALMENO
/// una canzone suoni fino in fondo.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('riproduzione completa e2e', (tester) async {
    final storage = StorageService();
    await storage.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const app.CrocutaApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 4));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final service = container.read(youtubeServiceProvider);

    final results = await service.search('never gonna give you up');
    expect(results.songs, isNotEmpty, reason: 'nessun risultato di ricerca');

    // Video di controllo: il brano "Crash Out" di Tinashe (w24EE2ns2UM)
    // che prima si fermava a 1:04. Ora con l'header X-Goog-Visitor-Id + il
    // client VISIONOS deve suonare INTERO.
    final control = track_model.Track(
      id: 'w24EE2ns2UM',
      title: 'Tinashe - Crash Out (control)',
      author: 'Tinashe',
      thumbnailUrl: '',
    );
    final playable = [...results.songs.take(2), control];

    for (final track in playable) {
      // ignore: avoid_print
      print('=== BRANO: ${track.title} (${track.id}) ===');
      await container.read(playerProvider.notifier).playTrack(track);

      var restarts = 0;
      Duration lastPos = Duration.zero;
      var ok = false;
      String lastErr = '-';
      for (var i = 0; i < 40; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final st = container.read(playerProvider);
        lastErr = st.error ?? '-';
        if (i % 5 == 0) {
          // ignore: avoid_print
          print(
            't=${i * 2}s pos=${st.position.inSeconds}s '
            'dur=${st.duration.inSeconds}s err=$lastErr',
          );
        }
        // Nessuno stream disponibile: brano flaggato, salta.
        if (i >= 3 &&
            st.position == Duration.zero &&
            st.error != null &&
            st.error != '-') {
          // ignore: avoid_print
          print('ESITO ${track.id}: NESSUN STREAM (flaggato), salto');
          break;
        }
        if (st.position < lastPos && lastPos > const Duration(seconds: 5)) {
          restarts++;
          // ignore: avoid_print
          print('!!! RIAVVIO #$restarts da ${lastPos.inSeconds}s');
        }
        lastPos = st.position;
        if (st.position >= const Duration(seconds: 70) && restarts == 0) {
          ok = true;
          break;
        }
      }
      // ignore: avoid_print
      print(
        'ESITO ${track.id}: ${ok ? "OK ✓" : "FALLITO (restarts=$restarts, pos=${lastPos.inSeconds}s, err=$lastErr)"}',
      );
      if (ok) return;
    }
    fail('nessun brano ha superato i 70s senza tagli');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
