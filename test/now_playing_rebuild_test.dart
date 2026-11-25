import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/design/app_theme.dart';
import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/screens/now_playing_screen.dart';
import 'package:yeen_music/services/player_controller.dart';
import 'package:yeen_music/services/player_state.dart';
import 'package:yeen_music/services/storage_service.dart';
import 'package:yeen_music/widgets/album_link.dart';
import 'package:yeen_music/widgets/liquid.dart';

/// Un player che si puo' far avanzare durante il test.
class DrivablePlayer extends PlayerController {
  DrivablePlayer(this._state);
  PlayerState _state;

  @override
  PlayerState build() => _state;

  void moveTo(Duration position) {
    _state = _state.copyWith(position: position);
    state = _state;
  }
}

const track = Track(
  id: 'x1',
  title: 'Fame is a Gun',
  author: 'Addison Rae',
  thumbnailUrl: '',
  duration: Duration(seconds: 180),
);

void main() {
  testWidgets('la posizione che avanza non ricostruisce il player', (
    tester,
  ) async {
    late final StorageService storage;
    late final Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('yeen_rebuild');
      storage = StorageService();
      await storage.init(path: dir.path);
    });
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final player = DrivablePlayer(
      const PlayerState(
        queue: [track],
        currentIndex: 0,
        isPlaying: true,
        // Serve alla barra: con totale zero mostra "--:--" e azzera anche
        // il tempo trascorso, quindi l'orologio sembrerebbe fermo per un
        // motivo che non c'entra niente con cio' che si sta verificando.
        duration: Duration(seconds: 180),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          playerProvider.overrideWith(() => player),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const NowPlayingScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Il segnale e' l'identita', non un contatore: se la schermata non si
    // ricostruisce, i widget che il suo `build` costruisce restano gli
    // stessi oggetti. AlbumLink va bene perche' non e' `const` — porta il
    // brano e lo stile, quindi ogni ricostruzione ne fabbrica per forza uno
    // nuovo.
    AlbumLink backdrop() => tester.widget<AlbumLink>(find.byType(AlbumLink));
    final before = backdrop();

    // Mezzo secondo di riproduzione, come lo emette libmpv.
    for (var ms = 100; ms <= 500; ms += 100) {
      player.moveTo(Duration(milliseconds: ms));
      await tester.pump();
    }

    // Prima questa schermata osservava l'intero stato del player: cinque
    // avanzamenti volevano dire cinque ricostruzioni dell'albero intero,
    // sfondo sfocato compreso. A 60fps e' una ricostruzione ogni sei-dodici
    // fotogrammi, e si sentiva come scatti regolari scorrendo.
    expect(
      identical(backdrop(), before),
      isTrue,
      reason: 'il player non deve ricostruirsi al passare del tempo',
    );

    // Ma l'orologio deve continuare a girare, altrimenti gli scatti
    // sarebbero stati "risolti" spegnendo cio' che si muoveva.
    player.moveTo(const Duration(seconds: 42));
    await tester.pump();
    expect(find.text('0:42'), findsOneWidget);
  });

  testWidgets('i tasti fissi sono vetro di sistema, quelli che scorrono no', (
    tester,
  ) async {
    late final StorageService storage;
    late final Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('yeen_glass');
      storage = StorageService();
      await storage.init(path: dir.path);
    });
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          playerProvider.overrideWith(
            () => DrivablePlayer(
              const PlayerState(
                queue: [track],
                currentIndex: 0,
                duration: Duration(seconds: 180),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const NowPlayingScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // In cima non c'e' piu' una freccia ma la barretta del cassetto, come
    // in Apple Music: nessun tasto di vetro.
    expect(find.byIcon(Icons.arrow_back_ios_new), findsNothing);

    // Quelli dentro lo scroll non sono vetro affatto: icone nude, come in
    // Apple Music. Soprattutto non vetro di sistema: una platform view a
    // tasto, spostata a ogni fotogramma, e' un costo che questa schermata
    // non deve riprendersi.
    for (final icon in [Icons.shuffle_rounded, Icons.skip_next_rounded]) {
      expect(
        find.ancestor(
          of: find.byIcon(icon),
          matching: find.byType(GlassCircleIconButton),
        ),
        findsNothing,
      );
    }
  });

  testWidgets('in pausa la copertina si ritira, in riproduzione torna grande', (
    tester,
  ) async {
    late final StorageService storage;
    late final Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('yeen_scale');
      storage = StorageService();
      await storage.init(path: dir.path);
    });
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<double> scaleWhen({
      required bool playing,
      bool loading = false,
    }) async {
      await tester.pumpWidget(
        // Chiave nuova a ogni caso: ripompare un ProviderScope con altri
        // override tiene il contenitore di prima, e si misurerebbe sempre lo
        // stesso player — il test passerebbe a vuoto.
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            playerProvider.overrideWith(
              () => DrivablePlayer(
                PlayerState(
                  queue: const [track],
                  currentIndex: 0,
                  isPlaying: playing,
                  isLoading: loading,
                  duration: const Duration(seconds: 180),
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const NowPlayingScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      return tester
          .widget<AnimatedScale>(find.byType(AnimatedScale).first)
          .scale;
    }

    expect(await scaleWhen(playing: true), 1.0);
    expect(await scaleWhen(playing: false), lessThan(1.0));
    // Durante il caricamento resta grande: fra un brano e l'altro isPlaying
    // e' falso per un istante, e la copertina pulserebbe.
    expect(await scaleWhen(playing: false, loading: true), 1.0);
  });
}
