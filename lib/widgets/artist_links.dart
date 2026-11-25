import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../models/artist_names.dart';
import '../models/track.dart';
import '../navigation.dart';
import '../providers.dart';
import 'toast.dart';

/// Il campo "artista" di un brano, con ogni nome cliccabile per conto suo.
///
/// Un brano in feat porta piu' artisti in un'unica stringa, ma il modello ha
/// un solo `artistId` — quello dell'interprete principale. Qui la stringa
/// viene divisa e, per i nomi senza id, l'artista si risolve cercandolo:
/// meglio una ricerca che un nome morto su cui si clicca invano.
class ArtistLinks extends ConsumerWidget {
  /// I nomi da rendere cliccabili, nell'ordine in cui si leggono.
  final List<String> names;

  /// L'id del primo nome, quando si conosce: senza, per aprirlo si cerca.
  final String? primaryId;

  final TextStyle? style;
  final TextAlign align;

  /// Dagli artisti di un brano: campo artista piu' gli ospiti nel titolo.
  ArtistLinks({
    super.key,
    required Track track,
    this.style,
    this.align = TextAlign.center,
  }) : names = allArtists(track).isEmpty ? [track.author] : allArtists(track),
       primaryId = track.artistId;

  /// Da un elenco gia' pronto: lo usa la pagina dell'album, che ha il nome
  /// dell'artista del disco ma non un brano da cui ricavarlo.
  const ArtistLinks.names({
    super.key,
    required this.names,
    this.primaryId,
    this.style,
    this.align = TextAlign.center,
  });

  /// Delegano al file puro: la lettura dei nomi serve anche al servizio,
  /// che non puo' importare un widget. Restano esposte qui perche' sono il
  /// punto di ingresso naturale per chi lavora sulla UI.
  static List<String> splitArtists(String author) =>
      ArtistNames.splitArtists(author);

  static List<String> featuredFromTitle(String title) =>
      ArtistNames.featuredFromTitle(title);

  /// Tutti gli artisti del brano, senza ripetizioni.
  ///
  /// Lo stesso nome puo' comparire sia nel campo artista sia nel titolo, e
  /// il titolo stesso puo' ripetere lo stesso gruppo due volte.
  static List<String> allArtists(Track track) {
    final seen = <String>{};
    final out = <String>[];
    for (final n in [
      ...splitArtists(track.author),
      ...featuredFromTitle(track.title),
    ]) {
      if (seen.add(n.toLowerCase())) out.add(n);
    }
    return out;
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    String name,
    bool isPrimary,
  ) async {
    // L'interprete principale ha gia' il suo id: nessuna ricerca da fare.
    if (isPrimary && primaryId != null) {
      openArtist(context, primaryId!, name);
      return;
    }

    final nav = Navigator.of(context);
    try {
      final results = await ref.read(youtubeServiceProvider).search(name);
      if (results.artists.isEmpty) {
        showToast('No Page for $name', icon: Icons.person_off_rounded);
        return;
      }
      final artist = results.artists.first;
      openArtist(nav.context, artist.browseId, artist.title);
    } catch (e) {
      showToast("Couldn't Open $name", icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = style ?? context.texts.bodyLarge;

    if (names.length <= 1) {
      final name = names.isEmpty ? '' : names.first;
      if (name.isEmpty) return const SizedBox.shrink();
      return _LinkText(
        text: name,
        style: base,
        onTap: () => _open(context, ref, name, true),
      );
    }

    return Wrap(
      alignment: align == TextAlign.center
          ? WrapAlignment.center
          : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < names.length; i++) ...[
          if (i > 0)
            Text(', ', style: base?.copyWith(color: context.colors.textMuted)),
          _LinkText(
            text: names[i],
            style: base,
            onTap: () => _open(context, ref, names[i], i == 0),
          ),
        ],
      ],
    );
  }
}

class _LinkText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final VoidCallback onTap;

  const _LinkText({
    required this.text,
    required this.style,
    required this.onTap,
  });

  @override
  State<_LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<_LinkText> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: widget.style?.copyWith(
            // Sottolineatura solo al passaggio: un testo sempre sottolineato
            // in mezzo ai comandi del player sarebbe rumore.
            decoration: _hover ? TextDecoration.underline : null,
            decorationColor: widget.style?.color,
          ),
        ),
      ),
    );
  }
}
