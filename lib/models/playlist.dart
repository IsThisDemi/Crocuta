import 'track.dart';

/// A playlist with its track list.
class Playlist {
  final String browseId;
  final String title;
  final String thumbnailUrl;
  final List<Track> tracks;

  const Playlist({
    required this.browseId,
    required this.title,
    required this.thumbnailUrl,
    this.tracks = const [],
  });
}
