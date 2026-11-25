import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/accent.dart';
import '../design/chrome.dart';
import '../navigation.dart';
import '../providers.dart';
import '../widgets/app_background.dart';
import '../widgets/den_rail.dart';
import '../widgets/word_tab_bar.dart';
import 'home_content.dart';
import 'library_screen.dart';
import 'queue_screen.dart';
import 'search_screen.dart';

/// La shell: quattro sezioni, ognuna col suo navigator, e il brano in
/// ascolto sempre a portata.
///
/// Due forme, secondo la larghezza:
///
/// * Larga (il Mac, l'iPad orizzontale): la "tana" a sinistra, con le
///   sezioni come parole grandi e in fondo il brano in ascolto con i suoi
///   comandi. Il contenuto occupa il resto.
/// * Stretta (il telefono): le stesse parole in basso, con sopra il mini
///   player, su un nero che sfuma verso l'alto.
///
/// Niente vetro: in Macchia la chrome e' nero pieno e il colore lo porta il
/// brano — la macchia accanto alla parola attiva, il tasto play, la
/// copertina. Ogni sezione tiene la sua pila di pagine, e ritoccare la
/// sezione attiva torna alla sua pagina iniziale, come su iOS.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  /// Da questa larghezza in su la navigazione sta nella tana a sinistra.
  static const double railBreakpoint = 860;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _tabCount = 4;

  static const _destinations = [
    DenDestination('Home', Icons.home_rounded),
    DenDestination('Search', Icons.search_rounded),
    DenDestination('Library', Icons.library_music_rounded),
    DenDestination('Queue', Icons.queue_music_rounded),
  ];

  /// Le chiavi stanno in navigation.dart: servono anche a chi apre una
  /// pagina da fuori la shell, per esempio il player.
  List<GlobalKey<NavigatorState>> get _navKeys => tabNavigatorKeys;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
  }

  void _onTabSelected(int i) {
    if (i == ref.read(navTabProvider)) {
      // Ritoccare la sezione su cui sei la riporta alla sua pagina
      // iniziale, come su iOS; se ci sei gia', la porta in cima.
      final nav = _navKeys[i].currentState;
      if (nav != null && nav.canPop()) {
        nav.popUntil((r) => r.isFirst);
      } else if (_navKeys[i].currentContext case final ctx?) {
        scrollFirstListToTop(ctx);
      }
      return;
    }
    ref.read(navTabProvider.notifier).select(i);
  }

  Widget _tabRoot(int i) => switch (i) {
    0 => const HomeContent(),
    1 => const SearchScreen(),
    2 => const LibraryScreen(),
    _ => const QueueScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(navTabProvider);
    // Chi apre una pagina da fuori deve sapere in quale scheda metterla.
    activeTab = index;
    final artwork = ref.watch(
      playerProvider.select((s) => s.current?.thumbnailUrl ?? ''),
    );

    final pages = _SectionFade(
      index: index,
      child: IndexedStack(
        index: index,
        children: [
          for (var i = 0; i < _tabCount; i++)
            Navigator(
              key: _navKeys[i],
              onGenerateRoute: (settings) => MaterialPageRoute(
                settings: settings,
                builder: (_) => _tabRoot(i),
              ),
            ),
        ],
      ),
    );

    // La chrome segue il brano IN ASCOLTO, non la pagina che stai
    // guardando. Album e artista hanno un loro AccentScope piu' in basso
    // nell'albero, quindi il loro colore vince per il proprio contenuto.
    return AccentScope(
      artworkUrl: artwork,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          final nav = _navKeys[ref.read(navTabProvider)].currentState;
          if (nav != null && nav.canPop()) {
            nav.pop();
          } else if (ref.read(navTabProvider) != NavTabController.home) {
            ref.read(navTabProvider.notifier).select(NavTabController.home);
          }
        },
        // Un Material sotto tutto: senza, ogni Text prende lo stile d'errore
        // di Flutter e gli InkWell non hanno dove disegnare.
        child: Material(
          color: AppColors.ink900,
          child: LayoutBuilder(
            builder: (context, box) {
              final rail = box.maxWidth >= AppShell.railBreakpoint;
              if (rail) return _wide(context, box, index, pages);
              return _narrow(context, index, pages);
            },
          ),
        ),
      ),
    );
  }

  Widget _wide(
    BuildContext context,
    BoxConstraints box,
    int index,
    Widget pages,
  ) {
    final mq = MediaQuery.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DenRail(
          destinations: _destinations,
          selected: index,
          onSelected: _onTabSelected,
        ),
        Expanded(
          // Le pagine misurano la finestra per scegliere le colonne: devono
          // vedere lo spazio che hanno davvero, non quello della tana
          // compresa.
          child: MediaQuery(
            data: mq.copyWith(
              size: Size(box.maxWidth - DenRail.width, mq.size.height),
            ),
            child: ChromeLayout(
              rail: true,
              child: Stack(
                fit: StackFit.expand,
                children: [const AppBackground(), pages],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _narrow(BuildContext context, int index, Widget pages) {
    return ChromeLayout(
      rail: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const AppBackground(),
          pages,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: WordTabBar(
              destinations: _destinations,
              selected: index,
              onSelected: _onTabSelected,
            ),
          ),
        ],
      ),
    );
  }
}

/// Il cambio di sezione: una dissolvenza veloce. Le pagine dentro si aprono
/// a macchia; passare da una sezione all'altra e' un gesto diverso, piu'
/// leggero, e qui basta che la sezione nuova compaia senza scatto.
class _SectionFade extends StatefulWidget {
  final int index;
  final Widget child;

  const _SectionFade({required this.index, required this.child});

  @override
  State<_SectionFade> createState() => _SectionFadeState();
}

class _SectionFadeState extends State<_SectionFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );

  @override
  void didUpdateWidget(_SectionFade old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurvedAnimation(
      parent: _c,
      curve: Curves.easeOut,
    ).drive(Tween(begin: 0.0, end: 1.0)),
    child: widget.child,
  );
}
