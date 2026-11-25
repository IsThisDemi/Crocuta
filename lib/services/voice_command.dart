/// Cosa vuole chi parla, capito da una frase.
///
/// Regole e non un modello: le frasi per la musica sono poche e sempre
/// quelle — un verbo, un titolo, forse un artista — e una regola sbagliata
/// si vede e si corregge, un modello no. L'italiano prima, l'inglese per
/// chi parla cosi'.
sealed class VoiceCommand {
  const VoiceCommand();
}

/// "Metti Hope di XXXTentacion": un brano, o un artista se la frase e' solo
/// un nome — lo decide chi esegue, guardando cosa trova.
class PlayQuery extends VoiceCommand {
  final String query;

  /// L'artista, se la frase lo dice ("... di Yeat").
  final String? artist;

  const PlayQuery(this.query, {this.artist});

  @override
  bool operator ==(Object other) =>
      other is PlayQuery && other.query == query && other.artist == artist;

  @override
  int get hashCode => Object.hash(query, artist);

  @override
  String toString() => 'PlayQuery($query, artist: $artist)';
}

/// "Qualcosa di Yeat", "musica di Yeat": l'artista, i suoi brani migliori.
class PlayArtist extends VoiceCommand {
  final String name;
  const PlayArtist(this.name);

  @override
  bool operator ==(Object other) => other is PlayArtist && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'PlayArtist($name)';
}

/// "La playlist Palestra".
class PlayPlaylist extends VoiceCommand {
  final String name;
  const PlayPlaylist(this.name);

  @override
  bool operator ==(Object other) => other is PlayPlaylist && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'PlayPlaylist($name)';
}

/// "La radio di TUMMY".
class StartRadio extends VoiceCommand {
  final String query;
  const StartRadio(this.query);

  @override
  bool operator ==(Object other) => other is StartRadio && other.query == query;

  @override
  int get hashCode => query.hashCode;

  @override
  String toString() => 'StartRadio($query)';
}

/// I comandi del player, senza argomenti.
enum PlayerAction {
  favorites,
  pause,
  resume,
  next,
  previous,
  louder,
  quieter,
  like,
  shuffle,
}

class Control extends VoiceCommand {
  final PlayerAction action;
  const Control(this.action);

  @override
  bool operator ==(Object other) => other is Control && other.action == action;

  @override
  int get hashCode => action.hashCode;

  @override
  String toString() => 'Control($action)';
}

/// Una frase che non si e' capita.
class NotUnderstood extends VoiceCommand {
  const NotUnderstood();
}

/// Minuscolo, senza accenti ne' punteggiatura, spazi singoli: come la frase
/// si confronta. Il riconoscimento vocale mette maiuscole e punti a caso.
String normalizeSpeech(String s) {
  const accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', //
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  };
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(accents[ch] ?? ch);
  }
  return b
      .toString()
      .replaceAll(RegExp(r"[^\p{L}\p{N}' ]", unicode: true), ' ')
      .replaceAll("'", ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Le parole di cortesia e il nome dell'app, che non dicono niente su cosa
/// suonare: "ehi crocuta per favore metti...".
final _filler = RegExp(
  r'^(?:(?:ehi|hey|ok|okay|allora|senti)(?:\s+|$))*(?:crocuta(?:\s+|$))?'
  r'|\s+(?:per favore|perfavore|grazie|please|su crocuta)$',
);

const _playVerbs = [
  'fammi sentire',
  'fammi ascoltare',
  'fai partire',
  'voglio sentire',
  'voglio ascoltare',
  'vorrei sentire',
  'riproduci',
  'mettimi',
  'metti',
  'suona',
  'suonami',
  'ascolta',
  'ascoltiamo',
  'avvia',
  'play',
  'put on',
];

/// Gli articoli che il verbo si porta dietro: "metti *la* canzone", "metti
/// *un po' di*".
final _leadingArticles = RegExp(
  r'^(?:(?:un po di|un po|un pezzo di|il brano|la canzone|la traccia|il pezzo|'
  r'the song|song|il|lo|la|i|gli|le|l|un|una|uno|the|a|some)\s+)+',
);

VoiceCommand parseVoiceCommand(String raw) {
  var s = normalizeSpeech(raw);
  for (var i = 0; i < 3; i++) {
    s = s.replaceAll(_filler, '').trim();
  }
  if (s.isEmpty) return const NotUnderstood();

  // I comandi del player: la frase intera, o il suo inizio. Mai la fine:
  // "metti Don't Stop" finisce con "stop" ed e' un brano da suonare.
  bool any(List<String> options) =>
      options.any((o) => s == o || s.startsWith('$o '));

  if (any([
    'pausa',
    'metti in pausa',
    'ferma',
    'fermati',
    'stop',
    'basta',
    'pause',
  ])) {
    return const Control(PlayerAction.pause);
  }
  if (any([
    'prossima',
    'prossimo',
    'avanti',
    'salta',
    'next',
    'skip',
    'canzone successiva',
    'brano successivo',
    'la prossima',
    'il prossimo',
  ])) {
    return const Control(PlayerAction.next);
  }
  if (any([
    'indietro',
    'precedente',
    'previous',
    'canzone precedente',
    'brano precedente',
    'torna indietro',
  ])) {
    return const Control(PlayerAction.previous);
  }
  if (any([
    'alza',
    'alza il volume',
    'piu forte',
    'volume su',
    'louder',
    'turn it up',
  ])) {
    return const Control(PlayerAction.louder);
  }
  if (any([
    'abbassa',
    'abbassa il volume',
    'piu piano',
    'volume giu',
    'quieter',
    'turn it down',
  ])) {
    return const Control(PlayerAction.quieter);
  }
  if (any([
    'mi piace',
    'metti mi piace',
    'aggiungi ai preferiti',
    'salva nei preferiti',
    'like',
    'like this',
  ])) {
    return const Control(PlayerAction.like);
  }
  if (any(['mescola', 'casuale', 'shuffle', 'riproduzione casuale'])) {
    return const Control(PlayerAction.shuffle);
  }
  if (any(['riprendi', 'continua', 'play', 'riparti', 'resume', 'vai'])) {
    if (!_playVerbs.any((v) => s.startsWith('$v ')) || s == 'play') {
      return const Control(PlayerAction.resume);
    }
  }

  // Il verbo, se c'e': "metti", "fammi sentire"... Senza, la frase e' gia'
  // cosa suonare: "Hope di XXXTentacion".
  for (final v in _playVerbs) {
    if (s == v) return const Control(PlayerAction.resume);
    if (s.startsWith('$v ')) {
      s = s.substring(v.length + 1);
      break;
    }
  }

  // I preferiti.
  final fav = RegExp(
    r'^(?:(?:tutti\s+)?(?:i\s+)?(?:miei\s+)?(?:brani\s+|canzoni\s+)?)?'
    r'(?:preferiti|preferite|brani che mi piacciono|canzoni che mi piacciono|'
    r'my favorites|my favourites|favorites|liked songs|my liked songs)$',
  );
  if (fav.hasMatch(s)) return const Control(PlayerAction.favorites);

  // La radio: "la radio di X", "radio X", "una radio basata su X".
  final radio = RegExp(
    r'^(?:(?:la|una)\s+)?radio\s+(?:(?:di|da|basata su|simile a|tipo|of|like)\s+)?(.+)$',
  ).firstMatch(s);
  if (radio != null) return StartRadio(_clean(radio.group(1)!));
  final like = RegExp(
    r'^(?:(?:qualcosa|musica|canzoni|brani)\s+)(?:simil[ei]\s+a|tipo|come)\s+(.+)$',
  ).firstMatch(s);
  if (like != null) return StartRadio(_clean(like.group(1)!));

  // Una playlist: "la playlist Palestra", "la mia playlist Palestra".
  final pl = RegExp(
    r'^(?:(?:la|una)\s+)?(?:mia\s+)?playlist\s+(?:(?:che si chiama|chiamata|called)\s+)?(.+)$',
  ).firstMatch(s);
  if (pl != null) return PlayPlaylist(_clean(pl.group(1)!));

  // L'artista: "qualcosa di Yeat", "musica di Yeat", "le canzoni di Yeat".
  final artist = RegExp(
    r'^(?:(?:qualcosa|un po|musica|canzoni|brani|pezzi|le canzoni|i brani|i pezzi|'
    r'le migliori|il meglio|something|music|songs)\s+)+(?:di|da|by|from)\s+(.+)$',
  ).firstMatch(s);
  if (artist != null) return PlayArtist(_clean(artist.group(1)!));

  s = s.replaceFirst(_leadingArticles, '').trim();
  if (s.isEmpty) return const NotUnderstood();

  // Un titolo, forse con l'artista: "Hope di XXXTentacion". L'ultimo "di"
  // separa, cosi' "Il cielo di Milano di Lazza" tiene il titolo intero.
  final by = RegExp(r'^(.+)\s+(?:di|by|dei|degli|delle)\s+(.+)$').firstMatch(s);
  if (by != null) {
    return PlayQuery(_clean(by.group(1)!), artist: _clean(by.group(2)!));
  }
  return PlayQuery(_clean(s));
}

String _clean(String s) => s.replaceFirst(_leadingArticles, '').trim();
