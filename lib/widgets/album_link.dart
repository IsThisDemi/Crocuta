import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../models/track.dart';
import '../navigation.dart';

/// Il nome dell'album del brano, cliccabile come lo sono gli artisti.
///
/// Sta fra il titolo e gli interpreti perche' e' un dato del brano, non di
/// chi lo suona: leggendo dall'alto si ha titolo, dove sta, e di chi e'.
///
/// Non si nasconde quando l'album non e' ancora noto: resta assente finche'
/// non arriva, e appare senza spostare nulla, perche' la riga la occupa
/// comunque il blocco sottostante.
class AlbumLink extends StatelessWidget {
  final Track track;
  final TextStyle? style;

  const AlbumLink({super.key, required this.track, this.style});

  @override
  Widget build(BuildContext context) {
    final name = track.albumName;
    if (name == null || name.trim().isEmpty) return const SizedBox.shrink();

    final id = track.albumId;
    final base =
        style ??
        context.texts.bodyMedium?.copyWith(color: context.colors.textMuted);

    // Senza browseId il nome resta scritto ma spento: una riga che sparisce
    // appena l'informazione arriva sposterebbe tutto il blocco.
    if (id == null) {
      return Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base?.copyWith(color: context.colors.textFaint),
      );
    }

    // Stesso bianco dei nomi degli interpreti: sono due righe della stessa
    // scheda e colorarne una sola la faceva sembrare di un altro genere.
    return GestureDetector(
      onTap: () => openAlbum(context, id, title: name),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: base,
        ),
      ),
    );
  }
}
