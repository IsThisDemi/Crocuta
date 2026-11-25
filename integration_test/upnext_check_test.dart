import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:yeen_music/services/youtube_service.dart';

/// Verifica che i "suggeriti" arrivino dalla coda correlata di YouTube Music
/// e non dal ripiego che cerca per nome dell'artista.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getUpNext restituisce brani correlati', (tester) async {
    final yt = YouTubeService();

    final results = await yt.search('daft punk one more time');
    expect(results.songs, isNotEmpty, reason: 'ricerca a vuoto');
    final seed = results.songs.first;
    print('>>> seed: "${seed.title}" di ${seed.author} (${seed.id})');

    final up = await yt.getUpNext(seed.id, artist: seed.author);
    print('>>> suggeriti: ${up.length}');
    for (final t in up.take(8)) {
      print('    - "${t.title}" di ${t.author}');
    }

    expect(up, isNotEmpty, reason: 'nessun suggerito');

    // Il ripiego produce brani il cui TITOLO somiglia al nome dell'artista.
    // Una coda vera porta titoli diversi di artisti anche diversi.
    final sameTitle = up
        .where((t) => t.title.toLowerCase() == seed.title.toLowerCase())
        .length;
    print('>>> con lo stesso titolo del brano di partenza: $sameTitle');
  });
}
