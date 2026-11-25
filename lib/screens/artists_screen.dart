import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/spot.dart';
import '../design/chrome.dart';
import '../navigation.dart';
import '../providers.dart';
import '../services/artwork.dart';
import '../services/follows_controller.dart';
import '../services/library_sort.dart';
import '../widgets/artwork_pressable.dart';
import '../widgets/empty_state.dart';
import '../widgets/library_sort_button.dart';
import '../widgets/sub_page.dart';
import '../widgets/thumbnail.dart';

/// Gli artisti che segui, come la voce "Artisti" della libreria di Apple.
///
/// La stella sulla pagina di un artista li salvava gia', ma poi non si
/// vedevano da nessuna parte: li usava solo Siri, per "riproduci" seguito
/// dal nome.
///
/// Una griglia di foto tonde e non un elenco: un elenco di cinque nomi con
/// la freccia in fondo alla riga, su una finestra larga, lasciava la
/// freccia a un metro dal nome e tre quarti di pagina vuoti. Qui l'artista
/// si riconosce dalla faccia prima che dal nome, come nella libreria di
/// Apple Music su Mac e iPad.
///
/// In ordine alfabetico come Musica, senza "The" davanti; oppure dall'ultimo
/// che hai cominciato a seguire.
class ArtistsScreen extends ConsumerStatefulWidget {
  const ArtistsScreen({super.key});

  @override
  ConsumerState<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends ConsumerState<ArtistsScreen> {
  late final _store = LibraryViewStore(
    ref.read(storageServiceProvider),
    'artists',
    options: SortKey.artists,
  );
  late LibraryView _view = _store.load();
  final _sorted = Memo<List<FollowedArtist>>();

  void _setView(LibraryView view) {
    setState(() => _view = view);
    _store.save(view);
  }

  @override
  Widget build(BuildContext context) {
    final follows = ref.watch(followsProvider);
    final artists = _sorted(
      (follows, _view),
      () => sortArtists(
        follows,
        _view,
        followedAt: ref.read(storageServiceProvider).marks('artist'),
      ),
    );

    return SubPage(
      title: 'Artists',
      actions: [
        if (follows.length > 1)
          LibrarySortButton(
            view: _view,
            options: SortKey.artists,
            onChanged: _setView,
          ),
      ],
      child: artists.isEmpty
          ? const EmptyState(
              icon: Icons.person_rounded,
              title: 'No artists yet',
              message: 'Tap the star on an artist page: they show up here.',
            )
          : LayoutBuilder(
              builder: (context, box) {
                // Colonne dalla larghezza: tre su un telefono, sei o sette
                // su un monitor, con foto che restano di una misura umana.
                final columns = (box.maxWidth / 170).floor().clamp(2, 8);
                final tile =
                    (box.maxWidth -
                        AppSpacing.gutter * 2 -
                        AppSpacing.lg * (columns - 1)) /
                    columns;
                return GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.md,
                    AppSpacing.gutter,
                    listBottomPadding(context, ref),
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: AppSpacing.lg,
                    mainAxisSpacing: AppSpacing.lg,
                    mainAxisExtent: tile + 36,
                  ),
                  itemCount: artists.length,
                  itemBuilder: (context, i) {
                    final a = artists[i];
                    final art = a.thumbnailUrl ?? '';
                    // La reazione sulla sola foto, sulla sua macchia: con un
                    // InkWell al passaggio del mouse compariva un quadrato
                    // grigio dietro la forma. Il seme e' l'indirizzo
                    // originale, non quello ingrandito, cosi' l'artista ha la
                    // stessa macchia delle schede nelle altre pagine.
                    return ArtworkPressable(
                      onTap: () => openArtist(context, a.browseId, a.name),
                      builder: (context, state) => Column(
                        children: [
                          SpotMotionBuilder(
                            builder: (context, t) => PressableArtwork(
                              state: state,
                              shape: SpotBorder(
                                seed: art,
                                time: t,
                                music: SpotMotion.musicOf(context),
                              ),
                              child: SizedBox.square(
                                dimension: tile,
                                child: Spot(
                                  seed: art,
                                  rim: Colors.white.withValues(alpha: 0.08),
                                  child: Thumbnail(
                                    url: hiResArtwork(art) ?? art,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: context.texts.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
