import 'package:flutter/material.dart';

import 'models/artist.dart';
import 'screens/album_screen.dart';
import 'screens/playlist_screen.dart';
import 'screens/section_screen.dart';
import 'screens/artist_screen.dart';

/// Pushes for the two destinations reachable from a track.
///
/// They live here rather than in the context menu so that menu code does not
/// have to import the screens, which import the track row, which builds the
/// menu. It is also the natural seam if a router ever arrives.

/// Il navigator radice, quello di MaterialApp: per aprire qualcosa sopra
/// tutto anche da dove non c'e' un context, come l'assistente vocale
/// chiesto da un collegamento.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Quante schede ha la shell.
const int tabCount = 4;

/// I navigator delle schede.
///
/// Stanno qui e non dentro la shell perche' servono anche da fuori: una
/// pagina aperta dal player deve finire *dentro* una scheda, non sopra di
/// essa, altrimenti nasce senza barra delle schede e senza il brano in
/// riproduzione.
final List<GlobalKey<NavigatorState>> tabNavigatorKeys = List.generate(
  tabCount,
  (_) => GlobalKey<NavigatorState>(),
);

/// La scheda visibile adesso. La aggiorna la shell.
///
/// Serve a non dover passare un `WidgetRef` a ogni funzione di apertura:
/// chi apre una pagina non ha motivo di sapere come sono fatte le schede.
int activeTab = 0;

/// Apre [page] dentro la scheda corrente, chiudendo il player se e' aperto.
///
/// Il player vive sul navigator radice e copre la chrome, quindi tutto cio'
/// che apriva nasceva senza barra delle schede e senza il brano in
/// riproduzione. Aprendo nella scheda la pagina le eredita entrambe.
///
/// Chiudere il player e' anche cio' che evita il giro chiuso: senza,
/// player -> album -> player -> album impilerebbe una coppia di schermate
/// per ogni giro, e il tasto indietro ci passerebbe attraverso una a una.
/// Cosi' invece il player lascia il posto alla pagina, e per tornarci c'e'
/// la barra in riproduzione — che e' anche come si comporta Apple Music.
void openInTab(BuildContext context, Widget page) {
  final root = Navigator.of(context, rootNavigator: true);
  final tab = tabNavigatorKeys[activeTab].currentState;
  if (tab == null) {
    // Nessuna scheda montata (test, o finestra in chiusura): meglio aprire
    // dove si puo' che non aprire.
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    return;
  }
  if (root.canPop()) root.pop();
  tab.push(MaterialPageRoute(builder: (_) => page));
}

void openArtist(BuildContext context, String browseId, String name) {
  openInTab(context, ArtistScreen(browseId: browseId, name: name));
}

void openAlbum(BuildContext context, String browseId, {String title = ''}) {
  openInTab(context, AlbumScreen(browseId: browseId, title: title));
}

/// Una playlist di YouTube Music: le classifiche sono playlist.
void openPlaylist(BuildContext context, String browseId, String title) {
  openInTab(context, PlaylistScreen(browseId: browseId, title: title));
}

/// La versione completa di una sezione della pagina artista.
void openSection(BuildContext context, SectionLink link) {
  openInTab(context, SectionScreen(link: link));
}

/// Porta in cima la prima lista verticale sotto [context].
///
/// Serve al ritocco della scheda quando sei gia' alla sua pagina iniziale:
/// su iOS e' il gesto per tornare in cima. Si cerca la lista nell'albero
/// invece di passarle un controller perche' le quattro schede vivono in un
/// IndexedStack e restano tutte montate: un controller condiviso sarebbe
/// attaccato a quattro liste insieme, e muoverlo le muoverebbe tutte.
///
/// La prima *verticale*: la Home e' piena di file orizzontali di schede, e
/// quelle non c'entrano. In profondita' la prima che si incontra e' la
/// lista della pagina, che contiene le altre.
///
/// Restituisce se ha trovato qualcosa da muovere.
bool scrollFirstListToTop(BuildContext context) {
  ScrollableState? found;
  void visit(Element e) {
    if (found != null) return;
    if (e is StatefulElement && e.state is ScrollableState) {
      final state = e.state as ScrollableState;
      if (axisDirectionToAxis(state.axisDirection) == Axis.vertical) {
        found = state;
        return;
      }
    }
    e.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  final position = found?.position;
  if (position == null || position.pixels <= position.minScrollExtent) {
    return false;
  }
  position.animateTo(
    position.minScrollExtent,
    duration: const Duration(milliseconds: 380),
    curve: Curves.easeOutCubic,
  );
  return true;
}
