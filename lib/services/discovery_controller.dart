import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../providers.dart';
import 'discovery.dart';
import 'smart_playlists.dart';

/// Discover Weekly e i Daily Mix, pronti da mostrare.
///
/// Si calcolano in background, qualche secondo dopo l'avvio per non
/// rubare la rete alla musica, e si salvano: Discover Weekly vale fino al
/// lunedi' dopo, i Daily Mix fino a domani. Servono una ventina di
/// richieste a YouTube, una per brano di partenza.
class DiscoveryController extends Notifier<List<SmartPlaylist>> {
  bool _running = false;

  @override
  List<SmartPlaylist> build() {
    final cached = ref.read(storageServiceProvider).discovery;
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      Timer(const Duration(seconds: 15), refresh);
    }
    return _fromCache(cached);
  }

  List<SmartPlaylist> _fromCache(Map? data) {
    if (data == null) return const [];
    List<Track> tracks(Object? raw) => [
      for (final t in (raw as List? ?? const []))
        Track.fromJson(Map<String, dynamic>.from(t as Map)),
    ];
    final weekly = tracks(data['weekly']);
    final mixes = (data['mixes'] as List? ?? const []);
    return [
      if (weekly.length >= 5) SmartPlaylist(SmartKind.discoverWeekly, weekly),
      for (var i = 0; i < mixes.length; i++)
        if (tracks((mixes[i] as Map)['tracks']) case final list
            when list.length >= 8)
          SmartPlaylist(
            SmartKind.dailyMix,
            list,
            id: 'dailyMix${i + 1}',
            title: 'Daily Mix ${i + 1}',
            subtitle: (mixes[i] as Map)['subtitle'] as String?,
            colors: dailyMixColors[i % dailyMixColors.length],
          ),
    ];
  }

  /// Rifa' cio' che e' scaduto; con [force] tutto.
  Future<void> refresh({bool force = false}) async {
    if (_running) return;
    _running = true;
    try {
      final storage = ref.read(storageServiceProvider);
      final now = DateTime.now();
      final old = storage.discovery ?? const {};
      final weekStale = force || old['week'] != weekKey(now);
      final dayStale = force || old['day'] != dayKey(now);
      if (!weekStale && !dayStale) return;

      final log = storage.playLog;
      final favorites = ref.read(favoritesProvider);
      final tracks = {
        ...storage.statTracks,
        for (final t in favorites) t.id: t,
      };
      // Cio' che conosci: mai proporlo come "nuovo".
      final heard = <String>{
        for (final (id, _, _) in log) id,
        for (final t in favorites) t.id,
        for (final p in ref.read(playlistsProvider))
          for (final t in p.tracks) t.id,
        for (final t in ref.read(recentlyPlayedProvider)) t.id,
      };
      Map<String, int> playsSince(int days) {
        final since = now.subtract(Duration(days: days));
        final out = <String, int>{};
        for (final (id, at, _) in log) {
          if (at.isAfter(since)) out[id] = (out[id] ?? 0) + 1;
        }
        return out;
      }

      final service = ref.read(youtubeServiceProvider);
      final radios = <String, List<Track>>{};
      Future<List<Track>> radioOf(Track seed) async {
        final hit = radios[seed.id];
        if (hit != null) return hit;
        try {
          final r = await service.getUpNext(seed.id, artist: seed.author);
          return radios[seed.id] = r;
        } catch (_) {
          return radios[seed.id] = const [];
        }
      }

      var weekly = old['weekly'];
      if (weekStale) {
        final plays = playsSince(60);
        final top = (plays.keys.where(tracks.containsKey).toList()
          ..sort((a, b) => plays[b]!.compareTo(plays[a]!)));
        // Pochi ascolti ancora: si parte dai preferiti.
        final seeds = [
          for (final id in top.take(10)) tracks[id]!,
          if (top.length < 5) ...favorites.take(10 - top.length),
        ];
        final lists = [for (final s in seeds) await radioOf(s)];
        final picked = pickDiscover(lists, heard);
        weekly = [for (final t in picked) t.toJson()];
        debugPrint(
          'scoperta: Discover Weekly, ${picked.length} brani da '
          '${seeds.length} punti di partenza',
        );
      }

      var mixes = old['mixes'];
      if (dayStale) {
        final plays = playsSince(30);
        final built = <Map<String, Object?>>[];
        for (final (artist, seeds) in mixArtists(plays, tracks)) {
          final lists = [for (final s in seeds) await radioOf(s)];
          final mix = buildMix(seeds: seeds, radios: lists, heard: heard);
          if (mix.length < 8) continue;
          // Chi c'e' dentro: l'artista del mix e i due piu' presenti dopo
          // di lui, come fa Spotify sotto i Daily Mix.
          final others = <String, int>{};
          for (final t in mix) {
            final a = mainArtist(t);
            if (a.toLowerCase() != artist.toLowerCase()) {
              others[a] = (others[a] ?? 0) + 1;
            }
          }
          final names = [
            artist,
            ...(others.keys.toList()
                  ..sort((a, b) => others[b]!.compareTo(others[a]!)))
                .take(2),
          ];
          built.add({
            'subtitle': '${names.join(', ')} and more',
            'tracks': [for (final t in mix) t.toJson()],
          });
        }
        mixes = built;
        debugPrint('scoperta: ${built.length} Daily Mix');
      }

      final data = <String, Object?>{
        'week': weekKey(now),
        'day': dayKey(now),
        'weekly': weekly,
        'mixes': mixes,
      };
      await storage.saveDiscovery(data);
      state = _fromCache(data);
    } catch (e) {
      debugPrint('scoperta: non riuscita ($e)');
    } finally {
      _running = false;
    }
  }
}

final discoveryProvider =
    NotifierProvider<DiscoveryController, List<SmartPlaylist>>(
      DiscoveryController.new,
    );
