import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/content_width.dart';
import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../models/artist.dart';
import '../navigation.dart';
import '../models/track.dart';
import '../providers.dart';
import '../shortcuts.dart';
import '../widgets/large_title.dart';
import '../widgets/empty_state.dart';
import '../widgets/media_card.dart';
import '../widgets/section_header.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/track_tile.dart';
import '../widgets/video_card.dart';
import 'album_screen.dart';
import 'browse_screens.dart';
import 'artist_screen.dart';
import 'playlist_screen.dart';
import '../widgets/voice_sheet.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  List<String> _suggestions = [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _submit(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    _query = q;
    FocusScope.of(context).unfocus();
    ref.read(searchProvider.notifier).search(q);
  }

  void _onChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    // Debounce: fetch suggestions only after a short pause in typing.
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final s = await ref.read(youtubeServiceProvider).getSuggestions(v.trim());
      if (mounted && _controller.text.trim() == v.trim()) {
        setState(() => _suggestions = s);
      }
    });
  }

  void _pickSuggestion(String s) {
    _controller.text = s;
    _controller.selection = TextSelection.collapsed(offset: s.length);
    setState(() => _suggestions = []);
    _submit(s);
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchProvider);

    // Il titolo grande e il campo scorrono con la pagina, come nelle altre
    // schede: "Search" si stringe nel titolo piccolo in cima. Una sola
    // lista di sliver e non il campo fisso sopra una lista: col campo
    // fermo il titolo non avrebbe niente con cui scorrere.
    //
    // Il campo sta in uno sliver singolo, che resta costruito anche quando
    // e' scorso fuori dallo schermo — un elenco pigro lo butterebbe via —
    // cosi' ⌘F trova sempre il suo nodo, e il campo che riceve il fuoco si
    // riporta in vista da solo.
    //
    // La cornice sta fuori dalla SafeArea: deve vedere l'area sicura vera
    // per mettere il titolo piccolo sotto l'orologio.
    return CollapsingTitleFrame(
      title: 'Search',
      child: SafeArea(
        bottom: false,
        // Colonna centrata: i risultati si stiravano su tutta la finestra.
        child: ContentWidth(
          maxWidth: ContentWidth.wide,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: topWindowInset(context)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.gutter,
                          AppSpacing.md,
                          AppSpacing.gutter,
                          AppSpacing.sm,
                        ),
                        child: LargeTitle('Search'),
                      ),
                      // Lo stesso margine del contenuto sotto: il campo
                      // stava a 16 e titoli e tessere a 20, e il bordo
                      // sinistro non tornava per quattro pixel.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.gutter,
                          0,
                          AppSpacing.gutter,
                          AppSpacing.xs,
                        ),
                        child: _field(),
                      ),
                    ],
                  ),
                ),
              ),
              ..._buildBody(search),
              SliverPadding(
                padding: EdgeInsets.only(
                  bottom: listBottomPadding(context, ref),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field() {
    // Il campo e' una riga grande col carattere dei titoli: in Macchia
    // cercare e' scrivere sul nero, non riempire una capsula. La linea
    // sotto si accende del colore del brano quando ci sei dentro.
    final big = context.texts.headlineMedium?.copyWith(fontSize: 34);
    return SearchFieldShortcuts(
      child: SizedBox(
        child: TextField(
          controller: _controller,
          focusNode: ref.watch(searchFocusProvider),
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
          onChanged: _onChanged,
          textAlignVertical: TextAlignVertical.center,
          // No spell-check squiggles under the typed text.
          enableSuggestions: false,
          autocorrect: false,
          spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
          style: big,
          cursorColor: context.colors.accent,
          decoration: InputDecoration(
            // Cosa si puo' cercare, e non da dove arriva: "su YouTube"
            // parlava del motore, non della musica.
            hintText: 'Artists, songs, lyrics…',
            hintStyle: big?.copyWith(color: context.colors.textFaint),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 30,
              color: context.colors.accentMuted,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 46),
            suffixIcon: _query.isEmpty
                ? IconButton(
                    tooltip: 'Ask with your voice',
                    color: context.colors.accent,
                    icon: const Icon(Icons.mic_rounded, size: 26),
                    onPressed: () => showVoiceSheet(context),
                  )
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _debounce?.cancel();
                      _controller.clear();
                      setState(() {
                        _query = '';
                        _suggestions = [];
                      });
                      ref.read(searchProvider.notifier).clear();
                    },
                  ),
            border: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: context.colors.accent, width: 2),
            ),
            filled: false,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  /// Il corpo sotto il campo, come sliver della stessa lista.
  List<Widget> _buildBody(SearchResult search) {
    // Un messaggio a meta' dello spazio che resta, non in cima.
    List<Widget> centered(Widget child) => [
      SliverFillRemaining(hasScrollBody: false, child: Center(child: child)),
    ];

    // Suggestions take over while the typed query hasn't been submitted yet.
    if (_suggestions.isNotEmpty && search.query != _query.trim()) {
      return [
        SliverList.builder(
          itemCount: _suggestions.length,
          itemBuilder: (context, i) {
            final s = _suggestions[i];
            return ListTile(
              leading: const Icon(Icons.search, color: Colors.white54),
              title: Text(s),
              onTap: () => _pickSuggestion(s),
            );
          },
        ),
      ];
    }
    if (search.isLoading) {
      return centered(const CircularProgressIndicator());
    }
    if (search.error != null) {
      return centered(
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(search.error!, textAlign: TextAlign.center),
        ),
      );
    }
    // Finche' non si e' scritto niente, la pagina non e' vuota: ci sono le
    // ricerche di prima e cosa gira adesso. Sparisce tutto al primo
    // carattere, perche' da li' in poi si sta cercando qualcos'altro.
    if (search.query.isEmpty && _query.isEmpty) {
      return [_Landing(onPick: _pickSuggestion)];
    }
    if (search.query.isEmpty) {
      return centered(
        const EmptyState(
          icon: Icons.music_note_rounded,
          title: 'Listen to your music',
          message: 'Search for an artist, an album or a song.',
        ),
      );
    }
    if (search.tracks.isEmpty &&
        search.artists.isEmpty &&
        search.albums.isEmpty &&
        search.playlists.isEmpty &&
        search.videos.isEmpty) {
      return centered(const Text('No results.'));
    }

    return [_ResultsView(search: search)];
  }
}

/// Results grouped in sections like the major music apps: Artisti, Canzoni,
/// Album, Playlist.
class _ResultsView extends ConsumerWidget {
  final SearchResult search;

  const _ResultsView({required this.search});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // I video: una categoria a parte, prima dei brani quando il risultato
    // principale e' un video (un remix uscito solo su YouTube), dopo
    // altrimenti. Toccandone uno lo si ascolta, con gli altri video in coda.
    final videos = search.videos.isEmpty
        ? const <Widget>[]
        : <Widget>[
            const SectionHeader(title: 'Videos'),
            VideoRail(
              videos: search.videos,
              onPlay: (v) => ref
                  .read(playerProvider.notifier)
                  .playTrack(v, queue: search.videos),
            ),
          ];
    final children = <Widget>[
      if (search.topIsVideo) ...videos,
      if (search.artists.isNotEmpty) ...[
        const SectionHeader(title: 'Artists'),
        MediaCardRail(
          height: 150,
          itemCount: search.artists.length,
          itemBuilder: (_, i) => MediaCard(
            width: 96,
            circle: true,
            imageUrl: search.artists[i].thumbnailUrl,
            title: search.artists[i].title,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ArtistScreen(
                  browseId: search.artists[i].browseId,
                  name: search.artists[i].title,
                ),
              ),
            ),
          ),
        ),
      ],
      if (search.tracks.isNotEmpty) ...[
        const SectionHeader(title: 'Songs'),
        for (final track in search.tracks) _SongRow(track: track),
      ],
      if (!search.topIsVideo) ...videos,
      if (search.albums.isNotEmpty) ...[
        const SectionHeader(title: 'Albums'),
        MediaCardRail(
          itemCount: search.albums.length,
          itemBuilder: (_, i) => MediaCard(
            imageUrl: search.albums[i].thumbnailUrl,
            title: search.albums[i].title,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AlbumScreen(
                  browseId: search.albums[i].browseId,
                  title: search.albums[i].title,
                ),
              ),
            ),
          ),
        ),
      ],
      if (search.playlists.isNotEmpty) ...[
        const SectionHeader(title: 'Playlists'),
        MediaCardRail(
          itemCount: search.playlists.length,
          itemBuilder: (_, i) => MediaCard(
            imageUrl: search.playlists[i].thumbnailUrl,
            title: search.playlists[i].title,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlaylistScreen(
                  browseId: search.playlists[i].browseId,
                  title: search.playlists[i].title,
                ),
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 32),
    ];

    // Il margine in fondo — tab bar e mini player galleggiano sopra — lo
    // aggiunge la lista della pagina, dopo questo sliver.
    return SliverList.list(children: children);
  }
}

class _SongRow extends ConsumerWidget {
  final Track track;

  /// La coda da far partire toccando la riga. Di norma i risultati della
  /// ricerca; nella pagina d'ingresso sono invece i brani del momento, che
  /// non stanno in `searchProvider`.
  final List<Track>? queue;

  const _SongRow({required this.track, this.queue});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(searchProvider);
    final player = ref.watch(playerProvider);
    final isCurrent = player.current?.id == track.id;

    return TrackTile(
      track: track,
      isCurrent: isCurrent,
      isPlaying: isCurrent && player.isPlaying,
      onTap: () {
        final p = ref.read(playerProvider.notifier);
        p.playTrack(track, queue: queue ?? search.tracks);
      },
      onArtistTap: track.artistId != null
          ? () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ArtistScreen(browseId: track.artistId!, name: track.author),
              ),
            )
          : null,
      // Un solo "…", come in Apple, al posto di tre icone per riga: cuore,
      // coda e playlist ripetuti per ogni risultato erano una colonna di
      // pulsanti che si leggeva prima dei titoli. Le stesse azioni — e le
      // altre — stanno nel menu del brano, che si apre anche col clic
      // destro o tenendo premuto.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (track.playsShort case final plays?)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Text(
                plays,
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.textFaint,
                  fontFeatures: AppTypography.tabular,
                ),
              ),
            ),
          Builder(
            builder: (buttonContext) => IconButton(
              icon: Icon(
                Icons.more_horiz_rounded,
                color: context.colors.textMuted,
              ),
              tooltip: 'More',
              onPressed: () {
                final box = buttonContext.findRenderObject() as RenderBox;
                showTrackMenu(
                  context,
                  ref,
                  track,
                  globalPosition: box.localToGlobal(
                    box.size.bottomCenter(Offset.zero),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// La pagina della ricerca prima che si scriva qualcosa.
///
/// Le ricerche recenti stavano in Home, dove erano l'unica cosa che non
/// c'entrava con l'ascolto: un elenco di parole scritte da te appartiene
/// al posto dove le riscriveresti. Sotto, quello che ogni app musicale
/// mette al posto di una pagina vuota — cosa gira adesso, le classifiche,
/// le uscite — che qui arriva da YouTube Music.
class _Landing extends ConsumerWidget {
  /// Una ricerca recente toccata: va anche scritta nel campo, non solo
  /// eseguita, altrimenti il campo resta vuoto sopra i risultati.
  final ValueChanged<String> onPick;

  const _Landing({required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider);
    final explore = ref.watch(exploreProvider);

    return SliverList.list(
      children: [
        if (history.isNotEmpty) ...[
          // Le ricerche di prima, dalla piu' recente: "Clear" le toglie tutte.
          SectionHeader(
            title: 'Recently searched',
            trailing: TextButton(
              onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
              child: Text(
                'Clear',
                style: TextStyle(color: context.colors.accent),
              ),
            ),
          ),
          // Le parole cercate, sparse come parole e non in un elenco:
          // si riconoscono a colpo d'occhio, e la piu' recente e' la piu'
          // grande. La crocetta compare col mouse sopra.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                for (final (i, q) in history.take(8).indexed)
                  _RecentWord(
                    text: q,
                    size: (34 - i * 3).clamp(20, 34).toDouble(),
                    onTap: () => onPick(q),
                    onRemove: () =>
                        ref.read(searchHistoryProvider.notifier).remove(q),
                  ),
              ],
            ),
          ),
        ],

        // Le categorie da sfogliare, come nella ricerca di Apple: la cosa
        // da fare quando non sai ancora cosa cercare.
        if (ref.watch(categoriesProvider).valueOrNull case final groups?
            when groups.isNotEmpty) ...[
          SectionHeader(
            title: 'Browse',
            onTitleTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CategoriesScreen())),
          ),
          CategoryGrid(
            // Due righe piene, con quante colonne entrano: quante tessere
            // servono lo sa solo la griglia, che conosce la larghezza.
            rows: 2,
            // Un po' di umori e un po' di generi, non solo i primi: i
            // primi sono tutti umori. Alternati, cosi' il miscuglio regge
            // qualunque sia il numero di tessere che entrano.
            items: [
              for (var i = 0; i < groups.first.items.length; i++) ...[
                groups.first.items[i],
                if (groups.length > 1 && i < groups[1].items.length)
                  groups[1].items[i],
              ],
              if (groups.length > 1)
                ...groups[1].items.skip(groups.first.items.length),
            ],
          ),
        ],

        explore.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: AppSpacing.huge),
            child: Center(child: CircularProgressIndicator()),
          ),
          // Una pagina che non si carica torna a essere quella di prima,
          // invece di mostrare un errore per qualcosa che nessuno ha
          // chiesto: qui si era venuti per cercare.
          error: (e, _) => const Padding(
            padding: EdgeInsets.only(top: AppSpacing.huge),
            child: EmptyState(
              icon: Icons.music_note_rounded,
              title: 'Listen to your music',
              message: 'Search for an artist, an album or a song.',
            ),
          ),
          data: (page) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (page.trending.isNotEmpty) ...[
                const SectionHeader(title: 'Trending now'),
                // Cinque e non venti: sotto ci sono le classifiche e le
                // uscite, e un elenco lungo le spingerebbe fuori schermo —
                // cioe' nasconderebbe proprio le sezioni per cui questa
                // pagina esiste.
                for (final track in page.trending.take(5))
                  _SongRow(track: track, queue: page.trending),
              ],
              _ChartRail(title: 'Charts', cards: page.charts),
              _ChartRail(title: 'Global charts', cards: page.globalCharts),
              if (page.newReleases.isNotEmpty) ...[
                const SectionHeader(title: 'New releases'),
                MediaCardRail(
                  itemCount: page.newReleases.length.clamp(0, 20),
                  itemBuilder: (_, i) => MediaCard(
                    imageUrl: page.newReleases[i].thumbnailUrl,
                    title: page.newReleases[i].title,
                    subtitle: page.newReleases[i].subtitle,
                    onTap: () => openAlbum(
                      context,
                      page.newReleases[i].browseId,
                      title: page.newReleases[i].title,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ChartRail extends StatelessWidget {
  final String title;
  final List<AlbumCard> cards;

  const _ChartRail({required this.title, required this.cards});

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        MediaCardRail(
          itemCount: cards.length,
          itemBuilder: (_, i) => MediaCard(
            imageUrl: cards[i].thumbnailUrl,
            title: cards[i].title,
            subtitle: cards[i].subtitle,
            onTap: () =>
                openPlaylist(context, cards[i].browseId, cards[i].title),
          ),
        ),
      ],
    );
  }
}

/// Una ricerca recente, come parola.
class _RecentWord extends StatefulWidget {
  final String text;
  final double size;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _RecentWord({
    required this.text,
    required this.size,
    required this.onTap,
    required this.onRemove,
  });

  @override
  State<_RecentWord> createState() => _RecentWordState();
}

class _RecentWordState extends State<_RecentWord> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onRemove,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              widget.text,
              style: context.texts.headlineMedium?.copyWith(
                fontSize: widget.size,
                color: _hover ? colors.accent : colors.accentMuted,
              ),
            ),
            // La crocetta solo col mouse sopra, e senza occupare posto
            // quando non c'e': sul telefono le parole stanno vicine, e si
            // tolgono tenendo premuto.
            if (_hover)
              IconButton(
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: colors.textFaint,
                ),
                onPressed: widget.onRemove,
              ),
          ],
        ),
      ),
    );
  }
}
