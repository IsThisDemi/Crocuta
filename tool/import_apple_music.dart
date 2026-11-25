// Trova su YouTube Music i brani di una libreria Apple Music.
//
// Legge l'elenco esportato dal lettore web di Apple Music (titolo, artista,
// durata, dal piu' recente) e scrive, per ognuno, il brano di YouTube Music
// che gli corrisponde — o niente, se non c'e' con sicurezza. Non tocca la
// libreria di Crocuta: quello lo fa un secondo passo, dopo aver guardato
// cosa non e' stato trovato.
//
//   dart run tool/import_apple_music.dart <apple.json> <uscita.json>
//
// L'uscita si riscrive dopo ogni brano: se si interrompe, rilanciarlo
// riparte da dove era arrivato invece di rifare tutte le ricerche.

import 'dart:convert';
import 'dart:io';

import 'package:yeen_music/services/youtube_service.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('uso: import_apple_music.dart <apple.json> <uscita.json>');
    exit(64);
  }
  final songs = (jsonDecode(File(args[0]).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final outFile = File(args[1]);
  final done = <String, Map<String, dynamic>>{
    if (outFile.existsSync())
      for (final r in (jsonDecode(outFile.readAsStringSync()) as List))
        (r as Map)['apple']['id'] as String: r.cast<String, dynamic>(),
  };

  final yt = YouTubeService();
  var found = done.values.where((r) => r['track'] != null).length;

  Future<void> one(Map<String, dynamic> s) async {
    final title = s['name'] as String;
    final artist = s['artist'] as String;
    final ms = s['ms'] as int?;
    final duration = ms == null ? null : Duration(milliseconds: ms);
    Map<String, dynamic>? track;
    try {
      // Prima col solo primo interprete; se non basta, con tutti: su
      // YouTube Music un brano a due nomi a volte e' schedato sotto il
      // secondo.
      final t =
          await yt.findCatalogSong(title, artist, duration: duration) ??
          await yt.findCatalogSong(
            title,
            artist,
            duration: duration,
            query: '$artist ${YouTubeService.stripFeaturing(title)}',
          );
      track = t?.toJson();
    } catch (e) {
      stderr.writeln('errore su "$title": $e');
      return; // non registrato: al prossimo giro si riprova
    }
    if (track != null) found++;
    done[s['id'] as String] = {'apple': s, 'track': track};
  }

  final todo = [
    for (final s in songs)
      if (!done.containsKey(s['id'])) s,
  ];
  stdout.writeln('${songs.length} brani, ${todo.length} da cercare');
  for (var i = 0; i < todo.length; i += 3) {
    await Future.wait(todo.skip(i).take(3).map(one));
    // Nell'ordine di Apple, non in quello in cui finiscono le ricerche.
    outFile.writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert([
        for (final s in songs)
          if (done[s['id']] case final r?) r,
      ]),
    );
    stdout.writeln('${done.length}/${songs.length}, trovati $found');
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  yt.dispose();
}
