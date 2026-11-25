/// A single lyric line with its timestamp.
class LyricsLine {
  final Duration time;
  final String text;

  const LyricsLine({required this.time, required this.text});
}

/// Parsed lyrics (LRC format) for a track.
class Lyrics {
  final String title;
  final String artist;
  final List<LyricsLine> lines;

  const Lyrics({
    required this.title,
    required this.artist,
    this.lines = const [],
  });

  /// Per salvarlo: righe come (millisecondi, testo), nell'ordine in cui
  /// sono. Non in LRC: un testo senza tempi ha tutte le righe a zero, e
  /// riordinarle rileggendolo non garantirebbe di ritrovarle in ordine.
  Map<String, Object> toJson() => {
    'title': title,
    'artist': artist,
    'lines': [
      for (final l in lines) [l.time.inMilliseconds, l.text],
    ],
  };

  factory Lyrics.fromJson(Map json) => Lyrics(
    title: json['title'] as String? ?? '',
    artist: json['artist'] as String? ?? '',
    lines: [
      for (final l in (json['lines'] as List? ?? const []))
        LyricsLine(
          time: Duration(milliseconds: (l as List)[0] as int),
          text: l[1] as String,
        ),
    ],
  );

  bool get isSynced =>
      lines.isNotEmpty && lines.any((l) => l.time > Duration.zero);

  /// Parses a raw LRC string into [Lyrics].
  factory Lyrics.parse(
    String raw, {
    required String title,
    required String artist,
  }) {
    final lines = <LyricsLine>[];
    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // [mm:ss.xx]text — possibly multiple timestamps per line.
      final timestamps = <Duration>[];
      var rest = line;
      final timeRe = RegExp(r'^\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
      while (true) {
        final m = timeRe.firstMatch(rest);
        if (m == null) break;
        final minutes = int.parse(m.group(1)!);
        final seconds = int.parse(m.group(2)!);
        var millisStr = m.group(3) ?? '0';
        if (millisStr.length == 2) millisStr = '${millisStr}0';
        if (millisStr.length == 1) millisStr = '${millisStr}00';
        timestamps.add(
          Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: int.parse(millisStr),
          ),
        );
        rest = rest.substring(m.end);
      }
      if (timestamps.isEmpty || rest.isEmpty) continue;
      for (final t in timestamps) {
        lines.add(LyricsLine(time: t, text: rest.trim()));
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return Lyrics(title: title, artist: artist, lines: lines);
  }
}
