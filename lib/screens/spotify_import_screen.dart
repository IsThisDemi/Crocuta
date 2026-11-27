import 'dart:async';
import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/spot.dart';
import '../design/chrome.dart';
import '../models/track.dart';
import '../providers.dart';
import '../services/apple_music_import_controller.dart';
import '../services/apple_music_library.dart' show AppleMusicReader;
import '../services/spotify_api.dart';
import '../services/spotify_auth.dart';
import '../services/spotify_import.dart';
import '../services/spotify_import_controller.dart';
import '../widgets/content_width.dart';
import '../widgets/glass_surfaces.dart';
import '../widgets/sub_page.dart';
import '../widgets/thumbnail.dart';
import '../widgets/toast.dart';

const _spotifyGreen = Color(0xFF1DB954);
const _appleRed = Color(0xFFFA2D48);

/// Da dove si importa.
enum ImportService { spotify, appleMusic }

/// Porta in Crocuta la libreria di Apple Music: la stessa pagina di
/// Spotify, con un primo passo diverso (vedi [SpotifyImportScreen]).
class AppleMusicImportScreen extends StatelessWidget {
  const AppleMusicImportScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const SpotifyImportScreen(service: ImportService.appleMusic);
}

/// Porta in Crocuta la libreria di Spotify (o di Apple Music), scegliendo
/// cosa.
///
/// Quattro momenti nella stessa pagina, uno alla volta: come leggere la
/// libreria (per Spotify il Client ID con le istruzioni per crearlo, per
/// Apple Music l'app Musica o un file esportato), la scelta di cosa
/// importare, l'avanzamento, il riepilogo coi brani non trovati. Quale
/// mostrare lo dice lo stato del controller, che vive fuori dalla pagina:
/// chiudendola l'import continua, e riaprendola si ritrova dov'era.
class SpotifyImportScreen extends ConsumerStatefulWidget {
  final ImportService service;

  const SpotifyImportScreen({super.key, this.service = ImportService.spotify});

  @override
  ConsumerState<SpotifyImportScreen> createState() =>
      _SpotifyImportScreenState();
}

class _SpotifyImportScreenState extends ConsumerState<SpotifyImportScreen> {
  late final TextEditingController _clientId;

  bool get _apple => widget.service == ImportService.appleMusic;

  NotifierProvider<LibraryImportController, SpotifyImportView> get _provider =>
      _apple ? appleMusicImportProvider : spotifyImportProvider;

  LibraryImportController get _ctrl => ref.read(_provider.notifier);

  /// Solo per Spotify: l'accesso.
  SpotifyImportController get _spotify =>
      ref.read(spotifyImportProvider.notifier);

  Color get _brand => _apple ? _appleRed : _spotifyGreen;

  String get _brandName => _apple ? 'Apple Music' : 'Spotify';

  @override
  void initState() {
    super.initState();
    final view = ref.read(_provider);
    _clientId = TextEditingController(text: view.clientId ?? '');
    // Collegati ma senza libreria (pagina appena aperta): la si legge.
    if (view.connected &&
        view.library == null &&
        !view.loadingLibrary &&
        view.job == null) {
      scheduleMicrotask(_ctrl.loadLibrary);
    }
  }

  @override
  void dispose() {
    _clientId.dispose();
    super.dispose();
  }

  Future<bool> _saveClientId() async {
    final id = _clientId.text.trim();
    if (!isSpotifyClientId(id)) {
      _ctrl.showError(
        'That does not look like a Client ID: it is 32 letters and digits, '
        'on the Basic Information page of your Spotify app.',
      );
      return false;
    }
    await _spotify.setClientId(id);
    return true;
  }

  /// L'accesso nella web view: la pagina di Spotify, e al ritorno il codice.
  Future<void> _connect() async {
    if (!await _saveClientId() || !mounted) return;
    final login = _spotify.startLogin();
    final result = await Navigator.of(context, rootNavigator: true)
        .push<SpotifyRedirect>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _SpotifyLoginPage(login: login),
          ),
        );
    if (result == null) return;
    if (result.error != null) {
      _ctrl.showError(result.error!);
      return;
    }
    await _spotify.finishLogin(result.code!, login.verifier);
  }

  /// L'accesso nel browser, per chi entra in Spotify con Google o Apple:
  /// quelle pagine non si aprono dentro una web view.
  Future<void> _connectInBrowser() async {
    if (!await _saveClientId() || !mounted) return;
    final login = _spotify.startLogin();
    await Clipboard.setData(ClipboardData(text: login.url.toString()));
    if (!mounted) return;
    final pasted = await showGlassTextPrompt(
      context: context,
      title: 'Log In with Your Browser',
      message:
          'The login link is copied. Paste it in your browser and allow '
          'access. The browser then shows an error page: that is expected. '
          'Copy the address of that page (it starts with '
          '$spotifyRedirectUri) and paste it here.',
      hint: '$spotifyRedirectUri?code=…',
      confirmLabel: 'Connect',
    );
    if (pasted == null) return;
    final result = parseSpotifyRedirect(pasted, expectedState: login.state);
    if (result == null) {
      _ctrl.showError(
        'That is not the address Spotify sent you back to. It starts with '
        '$spotifyRedirectUri.',
      );
      return;
    }
    if (result.error != null) {
      _ctrl.showError(result.error!);
      return;
    }
    await _spotify.finishLogin(result.code!, login.verifier);
  }

  Future<void> _disconnect() async {
    final ok = await showGlassConfirm(
      context: context,
      title: 'Disconnect Spotify?',
      message:
          'Crocuta forgets the Spotify login. What you imported stays in '
          'your library.',
      confirmLabel: 'Disconnect',
      destructive: true,
    );
    if (ok) await _spotify.disconnect();
  }

  Future<void> _discard(SpotifyImportState job) async {
    if (!job.finished) {
      final ok = await showGlassConfirm(
        context: context,
        title: 'Stop This Import?',
        message:
            'What is already in your library stays. The songs not searched '
            'yet are left out.',
        confirmLabel: 'Stop Import',
        destructive: true,
      );
      if (!ok) return;
    }
    await _ctrl.discard();
  }

  Future<void> _searchManually(SpotifyTrack track) async {
    final picked = await showGlassSheet<Track>(
      context: context,
      builder: (_) => _ManualSearch(track: track),
    );
    if (picked == null) return;
    await _ctrl.pick(track.key, picked);
    showToast('Added “${picked.title}”', icon: Icons.check_circle_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(_provider);
    final job = view.job;

    final List<Widget> children;
    if (job != null && view.running) {
      children = _progress(view, job);
    } else if (job != null && !job.finished) {
      children = _paused(view, job);
    } else if (job != null) {
      children = _summary(view, job);
    } else if (!view.connected) {
      children = _apple ? _appleSetup(view) : _setup(view);
    } else {
      children = _chooser(view);
    }

    return SubPage(
      title: 'Import from $_brandName',
      maxWidth: 620,
      actions: [
        if (view.connected && !view.running && !_apple)
          TextButton(onPressed: _disconnect, child: const Text('Disconnect')),
        if (view.connected && !view.running && _apple && view.job == null)
          TextButton(
            onPressed: () =>
                ref.read(appleMusicImportProvider.notifier).disconnect(),
            child: const Text('Change Source'),
          ),
      ],
      child: ContentWidth(
        child: ListView(
          padding: EdgeInsets.only(
            top: AppSpacing.sm,
            bottom: listBottomPadding(context, ref),
          ),
          children: [
            if (view.error != null) _ErrorBanner(message: view.error!),
            ...children,
          ],
        ),
      ),
    );
  }

  // --- Client ID e istruzioni ----------------------------------------------

  List<Widget> _setup(SpotifyImportView view) {
    final muted = context.colors.textMuted;
    Widget step(int n, String title, [Widget? extra]) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _spotifyGreen,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: context.texts.labelMedium?.copyWith(
                color: AppColors.ink900,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.texts.bodyMedium),
                ?extra,
              ],
            ),
          ),
        ],
      ),
    );

    Widget copyable(String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: text));
            showToast('Copied', icon: Icons.content_copy_rounded);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    text,
                    style: context.texts.bodyMedium?.copyWith(
                      fontFamily: 'Menlo',
                      fontFamilyFallback: const ['Consolas', 'monospace'],
                    ),
                  ),
                ),
                Icon(Icons.content_copy_rounded, size: 16, color: muted),
              ],
            ),
          ),
        ),
      ),
    );

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: Text(
          'Bring your Liked Songs, playlists, saved albums and followed '
          'artists into Crocuta. Each song is found on YouTube Music; '
          'nothing changes on Spotify.',
          style: context.texts.bodyMedium?.copyWith(color: muted),
        ),
      ),
      _Section(
        header: 'Once: Create Your Spotify App',
        footer:
            'Spotify only lets an app read your library if you allow it, and '
            'Crocuta has no server of its own: the app is yours, free, and '
            'only you use it. In development mode, Spotify needs the app '
            'owner to have Premium.',
        children: [
          step(
            1,
            'Open developer.spotify.com/dashboard and log in with your '
            'Spotify account. Accept the developer terms if asked.',
            copyable('https://developer.spotify.com/dashboard'),
          ),
          step(
            2,
            'Choose Create App. Any name and description will do, e.g. '
            '“Crocuta Import”. Under Redirect URIs paste exactly this, '
            'then press Add:',
            copyable(spotifyRedirectUri),
          ),
          step(
            3,
            'Under “Which API/SDKs are you planning to use?” tick Web API, '
            'accept the terms and Save.',
          ),
          step(
            4,
            'In the app, open Settings › User Management and add your name '
            'and the email of your Spotify account, if it is not listed '
            'yet. Without this, Spotify refuses with error 403.',
          ),
          step(
            5,
            'In Settings › Basic Information copy the Client ID (not the '
            'Client secret, Crocuta does not need it) and paste it here.',
          ),
        ],
      ),
      _Section(
        header: 'Client ID',
        footer:
            'The Client ID and the login stay on this device and are not '
            'synced.',
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: TextField(
              controller: _clientId,
              autocorrect: false,
              enableSuggestions: false,
              style: context.texts.bodyLarge,
              onSubmitted: (_) => _connect(),
              decoration: InputDecoration(
                hintText: '32 letters and digits',
                isDense: true,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 10,
                ),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.lg,
          AppSpacing.gutter,
          0,
        ),
        child: Column(
          children: [
            _PillButton(
              primary: true,
              icon: Icons.link_rounded,
              label: view.loadingLibrary ? 'Connecting…' : 'Connect to Spotify',
              onPressed: view.loadingLibrary ? null : _connect,
            ),
            const SizedBox(height: AppSpacing.sm),
            _PillButton(
              icon: Icons.open_in_browser_rounded,
              label: 'Log In with Your Browser',
              onPressed: view.loadingLibrary ? null : _connectInBrowser,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Use the browser if you sign in to Spotify with Google, Apple '
              'or Facebook: those pages do not open inside apps.',
              textAlign: TextAlign.center,
              style: context.texts.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    ];
  }

  // --- Cosa importare ------------------------------------------------------

  // --- Apple Music: da dove leggere -------------------------------------------

  Future<void> _openFile() async {
    const group = XTypeGroup(
      label: 'Music library',
      extensions: ['xml', 'json'],
      uniformTypeIdentifiers: ['public.xml', 'public.json'],
      mimeTypes: ['text/xml', 'application/xml', 'application/json'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    await ref
        .read(appleMusicImportProvider.notifier)
        .loadFile(file.name, file.readAsString);
  }

  List<Widget> _appleSetup(SpotifyImportView view) {
    final muted = context.colors.textMuted;
    final native = AppleMusicReader.isSupported;
    final where = Platform.isIOS ? 'this iPhone' : 'this Mac';
    Widget line(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(text, style: context.texts.bodyMedium),
    );

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: Text(
          'Bring your Apple Music library and playlists into Crocuta. Each '
          'song is found on YouTube Music; nothing changes in Apple Music.',
          style: context.texts.bodyMedium?.copyWith(color: muted),
        ),
      ),
      if (native)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.lg,
            AppSpacing.gutter,
            0,
          ),
          child: Column(
            children: [
              _PillButton(
                primary: true,
                icon: Icons.library_music_rounded,
                label: view.loadingLibrary
                    ? 'Reading…'
                    : 'Read the Music Library on ${Platform.isIOS ? 'iPhone' : 'Mac'}',
                onPressed: view.loadingLibrary ? null : _ctrl.loadLibrary,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Crocuta reads the library of the Music app on $where, once '
                'you allow it. With Sync Library on, that is everything you '
                'added from Apple Music.',
                textAlign: TextAlign.center,
                style: context.texts.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      _Section(
        header: native ? 'Or Open an Exported Library' : 'Export Your Library',
        footer:
            'A single playlist works too: File › Library › Export '
            'Playlist…, in XML format.',
        children: [
          line(
            'On a Mac, open Music and choose File › Library › Export '
            'Library…',
          ),
          line(
            'On Windows, open iTunes and choose File › Library › Export '
            'Library… The Apple Music app for Windows cannot export.',
          ),
          line(
            'Save the file (Library.xml) where this device can open it, '
            'then open it here.',
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.md,
          AppSpacing.gutter,
          0,
        ),
        child: _PillButton(
          primary: !native,
          icon: Icons.file_open_rounded,
          label: 'Open a Library File…',
          onPressed: view.loadingLibrary ? null : _openFile,
        ),
      ),
    ];
  }

  List<Widget> _chooser(SpotifyImportView view) {
    final library = view.library;
    final muted = context.colors.textMuted;
    if (library == null) {
      return [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              if (view.loadingLibrary) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Reading your $_brandName library…',
                  style: context.texts.bodyMedium?.copyWith(color: muted),
                ),
              ] else
                _PillButton(
                  primary: true,
                  icon: Icons.refresh_rounded,
                  label: 'Read My Library',
                  onPressed: _ctrl.loadLibrary,
                ),
            ],
          ),
        ),
      ];
    }

    final selected = view.selected;
    final count = library.all.where((s) => selected.contains(s.key)).length;

    Widget group(
      String header,
      SpotifySourceKind kind,
      List<SpotifySource> items, {
      String? footer,
    }) {
      if (items.isEmpty) return const SizedBox.shrink();
      final all = items.every((s) => selected.contains(s.key));
      return _Section(
        header: header,
        footer: footer,
        trailing: TextButton(
          onPressed: () => _ctrl.selectAll(!all, kind: kind),
          child: Text(all ? 'None' : 'All'),
        ),
        children: [
          for (final s in items)
            _SourceRow(
              source: s,
              selected: selected.contains(s.key),
              onTap: () => _ctrl.toggle(s.key),
            ),
        ],
      );
    }

    final restricted = library.playlists.any((p) => p.restricted);
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: Text(
          [
            if (library.user case final user?) 'Signed in as ${user.name}.',
            ?library.note,
            'Choose what to bring over.',
          ].join(' '),
          style: context.texts.bodyMedium?.copyWith(color: muted),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.md,
          AppSpacing.gutter,
          0,
        ),
        child: Column(
          children: [
            _PillButton(
              primary: true,
              icon: Icons.download_rounded,
              label: count == 0
                  ? 'Choose What to Import'
                  : 'Import $count ${count == 1 ? 'Item' : 'Items'}',
              onPressed: count == 0 ? null : _ctrl.start,
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _ctrl.selectAll(true),
                  child: const Text('Select All'),
                ),
                TextButton(
                  onPressed: () => _ctrl.selectAll(false),
                  child: const Text('Select None'),
                ),
              ],
            ),
          ],
        ),
      ),
      _Section(
        header: 'Songs',
        footer: _apple
            ? 'The songs in your library become your favorites in Crocuta, '
                  'newest first, below the ones you already have.'
            : 'Liked Songs become your favorites in Crocuta, newest first, '
                  'below the ones you already have.',
        children: [
          _SourceRow(
            apple: _apple,
            source: library.liked,
            selected: selected.contains(library.liked.key),
            onTap: () => _ctrl.toggle(library.liked.key),
          ),
        ],
      ),
      group(
        'Playlists',
        SpotifySourceKind.playlist,
        library.playlists,
        footer: restricted
            ? 'Spotify only gives the songs of playlists you made or '
                  'collaborate on. To bring one of the others, open it in '
                  'Spotify, select all its songs, add them to a new playlist '
                  'of yours, then read your library again.'
            : 'Each becomes a playlist with the same name, songs in order.',
      ),
      group(
        'Albums',
        SpotifySourceKind.album,
        library.albums,
        footer:
            'Saved albums are found on YouTube Music and their songs added '
            'to your library, like adding an album in Apple Music.',
      ),
      group('Artists', SpotifySourceKind.artist, library.artists),
    ];
  }

  // --- Avanzamento ---------------------------------------------------------

  List<Widget> _progress(SpotifyImportView view, SpotifyImportState job) {
    final p = view.progress;
    final muted = context.colors.textMuted;
    final phase = switch (p?.phase) {
      SpotifyImportPhase.reading => 'Reading from $_brandName',
      SpotifyImportPhase.matching => 'Finding songs on YouTube Music',
      SpotifyImportPhase.albums => 'Finding albums',
      SpotifyImportPhase.artists => 'Finding artists',
      SpotifyImportPhase.saving => 'Adding to your library',
      SpotifyImportPhase.done => 'Done',
      null => 'Starting',
    };
    final total = p?.total ?? 0;
    final done = p?.done ?? 0;
    final fraction = total == 0 ? null : (done / total).clamp(0.0, 1.0);
    final waiting = p?.waitingUntil;

    return [
      _Section(
        header: phase,
        footer:
            'You can leave this page: the import goes on. If Crocuta '
            'closes, it starts again from here.',
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    color: _brand,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  total == 0
                      ? ''
                      : p?.phase == SpotifyImportPhase.matching
                      ? '$done of $total songs · ${job.foundSongs} found'
                      : '$done of $total',
                  style: context.texts.titleSmall,
                ),
                if ((p?.current ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    p!.current,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(color: muted),
                  ),
                ],
                if (waiting != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'YouTube asked to slow down: waiting until '
                    '${TimeOfDay.fromDateTime(waiting).format(context)}.',
                    style: context.texts.bodySmall?.copyWith(
                      color: AppColors.amber,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.lg,
          AppSpacing.gutter,
          0,
        ),
        child: _PillButton(
          icon: Icons.pause_rounded,
          label: 'Pause',
          onPressed: _ctrl.cancel,
        ),
      ),
    ];
  }

  List<Widget> _paused(SpotifyImportView view, SpotifyImportState job) {
    final total = job.totalSongs;
    return [
      _Section(
        header: 'Import Paused',
        footer:
            'Resuming skips what was already found: only the rest is '
            'searched.',
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              total == 0
                  ? '${job.sources.length} items chosen, not started yet.'
                  : '${job.songs.length} of $total songs searched, '
                        '${job.foundSongs} found.',
              style: context.texts.bodyLarge,
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.lg,
          AppSpacing.gutter,
          0,
        ),
        child: Column(
          children: [
            _PillButton(
              primary: true,
              icon: Icons.play_arrow_rounded,
              label: 'Resume Import',
              onPressed: _ctrl.resume,
            ),
            const SizedBox(height: AppSpacing.sm),
            _PillButton(
              icon: Icons.close_rounded,
              label: 'Stop Import',
              onPressed: () => _discard(job),
            ),
          ],
        ),
      ),
    ];
  }

  // --- Riepilogo -----------------------------------------------------------

  List<Widget> _summary(SpotifyImportView view, SpotifyImportState job) {
    final muted = context.colors.textMuted;
    final missing = job.missing;
    final playlists = job.playlistIds.length;
    final albums = job.albums.values.where((a) => a != null).length;
    final artists = job.artists.values.where((a) => a != null).length;
    final unreadable = [
      for (final s in job.sources)
        if (job.unreadable.containsKey(s.key)) s,
    ];
    final hasMissing =
        missing.isNotEmpty ||
        job.missingAlbums.isNotEmpty ||
        job.missingArtists.isNotEmpty ||
        unreadable.isNotEmpty;

    Widget stat(IconData icon, Color color, String title, String value) =>
        _InfoRow(icon: icon, color: color, title: title, value: value);

    return [
      _Section(
        header: 'Imported',
        children: [
          if (job.totalSongs > 0)
            stat(
              Icons.music_note_rounded,
              AppColors.coral,
              'Songs',
              '${job.foundSongs} of ${job.totalSongs}',
            ),
          if (playlists > 0)
            stat(
              Icons.queue_music_rounded,
              const Color(0xFF8B5CF6),
              'Playlists',
              '$playlists',
            ),
          if (job.sources.any((s) => s.kind == SpotifySourceKind.album))
            stat(
              Icons.album_rounded,
              const Color(0xFF3B82F6),
              'Albums',
              '$albums of ${job.sources.where((s) => s.kind == SpotifySourceKind.album).length}',
            ),
          if (job.sources.any((s) => s.kind == SpotifySourceKind.artist))
            stat(
              Icons.person_rounded,
              const Color(0xFFF59E0B),
              'Artists Followed',
              '$artists of ${job.sources.where((s) => s.kind == SpotifySourceKind.artist).length}',
            ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.lg,
          AppSpacing.gutter,
          0,
        ),
        child: Column(
          children: [
            if (hasMissing) ...[
              _PillButton(
                primary: true,
                icon: Icons.refresh_rounded,
                label: 'Search Again for What Is Missing',
                onPressed: _ctrl.retryMissing,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            _PillButton(
              icon: Icons.add_rounded,
              label: 'New Import',
              onPressed: () => _discard(job),
            ),
          ],
        ),
      ),
      if (unreadable.isNotEmpty)
        _Section(
          header: 'Playlists Spotify Did Not Share',
          footer:
              'Spotify only gives the songs of playlists you made or '
              'collaborate on. In Spotify, select all the songs of one of '
              'these, add them to a new playlist of yours, then start a new '
              'import with it.',
          children: [
            for (final s in unreadable)
              _SourceRow(source: s, selected: null, onTap: null),
          ],
        ),
      if (job.missingAlbums.isNotEmpty)
        _Section(
          header: 'Albums Not Found',
          children: [
            for (final s in job.missingAlbums)
              _SourceRow(source: s, selected: null, onTap: null),
          ],
        ),
      if (job.missingArtists.isNotEmpty)
        _Section(
          header: 'Artists Not Found',
          children: [
            for (final s in job.missingArtists)
              _SourceRow(source: s, selected: null, onTap: null),
          ],
        ),
      if (missing.isNotEmpty)
        _Section(
          header: 'Songs Not Found (${missing.length})',
          footer:
              'Not on YouTube Music, or not surely the same song (another '
              'version, a different length). Search to pick it yourself.',
          children: [
            for (final m in missing)
              _MissingRow(
                track: m.track,
                sources: m.sources,
                onSearch: () => _searchManually(m.track),
              ),
          ],
        ),
      if (!hasMissing)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'Everything was found.',
            textAlign: TextAlign.center,
            style: context.texts.bodyMedium?.copyWith(color: muted),
          ),
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Pezzi
// ---------------------------------------------------------------------------

/// Un gruppo come quelli delle Impostazioni: titoletto, righe in un
/// riquadro arrotondato, spiegazione sotto.
class _Section extends StatelessWidget {
  final String header;
  final String? footer;
  final Widget? trailing;
  final List<Widget> children;

  const _Section({
    required this.header,
    this.footer,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.textMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, 0, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    header.toUpperCase(),
                    style: context.texts.labelSmall?.copyWith(
                      color: muted,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ColoredBox(
              color: Colors.white.withValues(alpha: 0.07),
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    children[i],
                    if (i < children.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 56),
                        child: Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                6,
                AppSpacing.md,
                0,
              ),
              child: Text(
                footer!,
                style: context.texts.bodySmall?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// Un comando largo a capsula, come "Riproduci" e "Casuale": pieno
/// d'accento il principale, grigio di vetro l'altro.
class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: FilledButton.styleFrom(
            backgroundColor: primary
                ? accent
                : Colors.white.withValues(alpha: 0.10),
            foregroundColor: primary
                ? AppColors.ink900
                : context.colors.textStrong,
            disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
            disabledForegroundColor: context.colors.textFaint,
            elevation: 0,
            shape: AppRadius.shape(AppRadius.pill),
            textStyle: context.texts.titleMedium,
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.danger,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(message, style: context.texts.bodyMedium)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una cosa da importare: copertina, nome, sottotitolo, e il segno di
/// spunta tondo come nelle liste di scelta di iOS. Senza [selected] la
/// spunta non c'e' (nel riepilogo).
class _SourceRow extends StatelessWidget {
  final SpotifySource source;
  final bool? selected;
  final VoidCallback? onTap;

  /// I brani della libreria di Apple Music, invece dei piaciuti di
  /// Spotify: la nota sul rosso di Apple, non il cuore sul viola.
  final bool apple;

  const _SourceRow({
    required this.source,
    required this.selected,
    required this.onTap,
    this.apple = false,
  });

  String get _subtitle {
    final n = source.count;
    final songs = '$n ${n == 1 ? 'song' : 'songs'}';
    return switch (source.kind) {
      SpotifySourceKind.liked => songs,
      SpotifySourceKind.playlist =>
        source.restricted
            ? 'By ${source.subtitle} · Spotify may not share its songs'
            : source.subtitle.isEmpty
            ? songs
            : '$songs · ${source.subtitle}',
      SpotifySourceKind.album => source.subtitle,
      SpotifySourceKind.artist => 'Artist',
    };
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.textMuted;
    final Widget cover = switch (source.kind) {
      SpotifySourceKind.liked => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: apple
                ? const [Color(0xFFFA2D48), Color(0xFFFF7A8A)]
                : const [Color(0xFF4B33CC), Color(0xFF9E8BFF)],
          ),
        ),
        child: Icon(
          apple ? Icons.music_note_rounded : Icons.favorite_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
      _ => Thumbnail(url: source.imageUrl ?? ''),
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 6,
        ),
        child: Row(
          children: [
            // Playlist e artisti sono macchie come nel resto dell'app,
            // piccole e quindi poco storte; il seme e' l'immagine, o il
            // nome per i "Liked Songs" che un'immagine non ce l'hanno.
            SizedBox.square(
              dimension: 40,
              child: Spot(
                seed: source.imageUrl ?? source.name,
                wobble: 0.6,
                rim: Colors.white.withValues(alpha: 0.08),
                child: cover,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyLarge,
                  ),
                  Text(
                    _subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            if (selected != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(
                selected!
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 24,
                color: selected! ? context.colors.accent : muted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 17, color: Colors.white),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(title, style: context.texts.bodyLarge)),
            Text(
              value,
              style: context.texts.bodyLarge?.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingRow extends StatelessWidget {
  final SpotifyTrack track;
  final List<String> sources;
  final VoidCallback onSearch;

  const _MissingRow({
    required this.track,
    required this.sources,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.textMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 6, AppSpacing.xs, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyLarge,
                ),
                Text(
                  '${track.artist} · in ${sources.join(', ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onSearch, child: const Text('Search')),
        ],
      ),
    );
  }
}

/// Cerca a mano un brano non trovato: la ricerca "Songs" di YouTube Music,
/// gia' scritta con interprete e titolo, e si tocca quello giusto.
class _ManualSearch extends ConsumerStatefulWidget {
  final SpotifyTrack track;

  const _ManualSearch({required this.track});

  @override
  ConsumerState<_ManualSearch> createState() => _ManualSearchState();
}

class _ManualSearchState extends ConsumerState<_ManualSearch> {
  late final TextEditingController _query;
  List<Track>? _results;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(
      text: spotifySongQueries(widget.track).first,
    );
    unawaited(_search());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref.read(youtubeServiceProvider).searchSongs(q);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Search failed. Try again in a moment.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _time(Duration? d) {
    if (d == null) return '';
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.textMuted;
    final t = widget.track;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.name, style: context.texts.titleMedium),
          Text(
            '${t.artist}${t.duration == null ? '' : ' · ${_time(t.duration)}'}'
            '${t.album == null ? '' : ' · ${t.album}'}',
            style: context.texts.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          GlassAlertField(controller: _query, onSubmitted: (_) => _search()),
          const SizedBox(height: AppSpacing.sm),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Text(_error!, style: context.texts.bodyMedium)
          else if (_results != null && _results!.isEmpty)
            Text(
              'No songs for this search.',
              style: context.texts.bodyMedium?.copyWith(color: muted),
            )
          else
            for (final r in _results ?? const <Track>[])
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).pop(r),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 40,
                        child: SpotThumbnail(url: r.thumbnailUrl, wobble: 0.6),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.texts.bodyLarge,
                            ),
                            Text(
                              [
                                r.author,
                                if (r.albumName != null) r.albumName!,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.texts.bodySmall?.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _time(r.duration),
                        style: context.texts.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// La pagina di consenso di Spotify in una web view.
///
/// Spotify, finito, rimanda a [spotifyRedirectUri]: la web view vede
/// l'indirizzo prima di caricarlo, ne prende il codice e chiude. Su quella
/// porta non c'e' niente in ascolto, e non serve. In incognito: niente
/// sessione Spotify lasciata nella web view, e chi vuole entrare con un
/// altro account non si ritrova dentro quello di prima.
class _SpotifyLoginPage extends StatefulWidget {
  final SpotifyLogin login;

  const _SpotifyLoginPage({required this.login});

  @override
  State<_SpotifyLoginPage> createState() => _SpotifyLoginPageState();
}

class _SpotifyLoginPageState extends State<_SpotifyLoginPage> {
  bool _done = false;
  double _progress = 0;

  /// Vero se [url] era il ritorno da Spotify (e la pagina si chiude).
  bool _handle(String? url) {
    if (_done || url == null) return false;
    final result = parseSpotifyRedirect(url, expectedState: widget.login.state);
    if (result == null) return false;
    _done = true;
    // Dopo il fotogramma: la web view sta ancora decidendo della
    // navigazione, e toglierla da sotto a quel punto la fa protestare.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SubPage(
      child: Column(
        children: [
          if (_progress < 1)
            LinearProgressIndicator(
              value: _progress == 0 ? null : _progress,
              minHeight: 2,
              color: _spotifyGreen,
              backgroundColor: Colors.transparent,
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri.uri(widget.login.url)),
              initialSettings: InAppWebViewSettings(
                useShouldOverrideUrlLoading: true,
                incognito: true,
                transparentBackground: true,
              ),
              shouldOverrideUrlLoading: (controller, action) async =>
                  _handle(action.request.url?.toString())
                  ? NavigationActionPolicy.CANCEL
                  : NavigationActionPolicy.ALLOW,
              // Dove il controllo sopra non arriva (un redirect del server
              // su qualche piattaforma), l'indirizzo si vede qui.
              onLoadStart: (controller, url) {
                if (_handle(url?.toString())) controller.stopLoading();
              },
              onReceivedError: (controller, request, error) =>
                  _handle(request.url.toString()),
              onProgressChanged: (controller, p) {
                if (mounted) setState(() => _progress = p / 100);
              },
            ),
          ),
        ],
      ),
    );
  }
}
