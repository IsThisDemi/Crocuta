/// Lettura dei nomi degli artisti dai campi di YouTube Music.
///
/// Sta qui, e non dentro il widget che li rende cliccabili, perche' serve
/// anche al servizio che costruisce i brani: un servizio non deve importare
/// un widget per normalizzare una stringa.
class ArtistNames {
  const ArtistNames._();

  /// Separatori usati da YouTube Music fra piu' interpreti. Le forme con
  /// spazi attorno evitano di spezzare nomi che contengono "x" o "and".
  static final _splitter = RegExp(
    // Il confine di parola va SUBITO dopo le lettere: con `\bfeat\.?\b` il
    // punto restava fuori dal separatore e finiva incollato al nome
    // successivo (". Caio"). "e" ed "x" separano solo fra spazi, altrimenti
    // spezzerebbero qualsiasi nome che li contiene.
    r'\s*(?:,|&|;|/|·|\bfeat\b\.?|\bft\b\.?|\bfeaturing\b|\bcon\b|\sx\s|\se\s|\band\b)\s*',
    caseSensitive: false,
  );

  /// Gruppi fra parentesi che elencano gli ospiti: "(con X, Y)",
  /// "(feat. Z)", "(with W)".
  static final _featGroup = RegExp(
    r'[\(\[]\s*(?:con|feat\.?|ft\.?|featuring|with)\s+([^\)\]]+)[\)\]]',
    caseSensitive: false,
  );

  static List<String> splitArtists(String author) => author
      .split(_splitter)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// Gli ospiti spesso non stanno nel campo artista ma nel titolo: YouTube
  /// Music li lascia dove li ha messi chi ha caricato il video. Senza
  /// guardare anche qui, di un brano in feat resterebbe cliccabile solo
  /// l'interprete principale.
  static List<String> featuredFromTitle(String title) {
    final out = <String>[];
    for (final m in _featGroup.allMatches(title)) {
      out.addAll(splitArtists(m.group(1) ?? ''));
    }
    return out;
  }

  /// Il titolo senza i gruppi di feat ripetuti.
  ///
  /// YouTube Music restituisce certi titoli con lo stesso gruppo scritto due
  /// volte, dentro un unico run di testo: "CLUB TEST (con IvanBi, Diss
  /// Gacha) (con IvanBi e Diss Gacha)". Non lo componiamo noi — verificato
  /// sui dati grezzi — ma mostrarlo due volte e' una scelta nostra, e quel
  /// titolo raddoppiato manda a capo ogni riga in cui compare.
  ///
  /// Si toglie un gruppo solo quando i suoi ospiti sono gia' tutti nominati
  /// da uno precedente: "(con A, B) (con C)" resta intatto, perche' C non e'
  /// nominato altrove. Nessun nome puo' quindi sparire dal titolo.
  static String dedupeFeatGroups(String title) {
    final groups = _featGroup.allMatches(title).toList();
    if (groups.length < 2) return title;

    final kept = <Set<String>>[];
    final drop = <RegExpMatch>[];
    for (final g in groups) {
      final names = splitArtists(
        g.group(1) ?? '',
      ).map((n) => n.toLowerCase()).toSet();
      if (names.isEmpty) continue;
      if (kept.any((k) => names.difference(k).isEmpty)) {
        drop.add(g);
      } else {
        kept.add(names);
      }
    }
    if (drop.isEmpty) return title;

    final buffer = StringBuffer();
    var cursor = 0;
    for (final g in drop) {
      buffer.write(title.substring(cursor, g.start));
      cursor = g.end;
    }
    buffer.write(title.substring(cursor));
    // Tolto un gruppo di mezzo restano due spazi attaccati.
    return buffer.toString().replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }
}
