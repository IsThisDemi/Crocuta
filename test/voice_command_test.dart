import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/services/voice_command.dart';

void main() {
  VoiceCommand p(String s) => parseVoiceCommand(s);

  test('un brano, con o senza artista', () {
    expect(
      p('Metti Hope di XXXTentacion'),
      const PlayQuery('hope', artist: 'xxxtentacion'),
    );
    expect(p('fammi sentire la canzone Passion'), const PlayQuery('passion'));
    expect(p('Riproduci TUMMY.'), const PlayQuery('tummy'));
    expect(
      p('Hope di XXXTentacion'),
      const PlayQuery('hope', artist: 'xxxtentacion'),
    );
    // L'ultimo "di" separa titolo e artista.
    expect(
      p('metti Il cielo di Milano di Lazza'),
      const PlayQuery('cielo di milano', artist: 'lazza'),
    );
    expect(p('play Taste by Tyga'), const PlayQuery('taste', artist: 'tyga'));
  });

  test('il nome dell app e la cortesia non contano', () {
    expect(p('Ehi Crocuta metti Hope per favore'), const PlayQuery('hope'));
    expect(p('ok crocuta pausa'), const Control(PlayerAction.pause));
  });

  test('un artista', () {
    expect(p('metti qualcosa di Yeat'), const PlayArtist('yeat'));
    expect(p('suona musica di Anna'), const PlayArtist('anna'));
    expect(p('fammi sentire le canzoni di Lazza'), const PlayArtist('lazza'));
  });

  test('preferiti, playlist, radio', () {
    expect(p('metti i miei preferiti'), const Control(PlayerAction.favorites));
    expect(p('riproduci i preferiti'), const Control(PlayerAction.favorites));
    expect(p('metti la playlist Palestra'), const PlayPlaylist('palestra'));
    expect(p('la mia playlist chiamata Notte'), const PlayPlaylist('notte'));
    expect(p('avvia la radio di TUMMY'), const StartRadio('tummy'));
    expect(p('metti qualcosa simile a Hope'), const StartRadio('hope'));
  });

  test('i comandi del player', () {
    expect(p('pausa'), const Control(PlayerAction.pause));
    expect(p('metti in pausa'), const Control(PlayerAction.pause));
    expect(p('prossima'), const Control(PlayerAction.next));
    expect(p('salta questa'), const Control(PlayerAction.next));
    expect(p('torna indietro'), const Control(PlayerAction.previous));
    expect(p('alza il volume'), const Control(PlayerAction.louder));
    expect(p('più piano'), const Control(PlayerAction.quieter));
    expect(p('mi piace'), const Control(PlayerAction.like));
    expect(p('riprendi'), const Control(PlayerAction.resume));
    expect(p('play'), const Control(PlayerAction.resume));
  });

  test('un titolo che finisce come un comando resta un titolo', () {
    expect(p("metti Don't Stop"), const PlayQuery('don t stop'));
    expect(p('play Next to Me'), const PlayQuery('next to me'));
  });

  test('niente di sensato', () {
    expect(p(''), isA<NotUnderstood>());
    expect(p('ehi crocuta'), isA<NotUnderstood>());
  });
}
