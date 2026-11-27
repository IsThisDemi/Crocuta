import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/artist.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/services/follows_controller.dart';
import 'package:crocuta/services/storage_service.dart';
import 'package:crocuta/services/youtube_service.dart';

/// Conta le pagine artista chieste alla rete.
class _Counting extends YouTubeService {
  int calls = 0;

  @override
  Future<ArtistPage> getArtistPage(String browseId) async {
    calls++;
    return ArtistPage(
      browseId: browseId,
      name: 'Yeat',
      albums: const [
        AlbumCard(
          browseId: 'MPRE1',
          title: 'Disco',
          subtitle: '2026',
          thumbnailUrl: '',
        ),
      ],
    );
  }
}

void main() {
  test('una sincronizzazione che non cambia chi segui non riscarica', () async {
    final dir = await Directory.systemTemp.createTemp('rel');
    final storage = StorageService();
    await storage.init(path: dir.path);
    await storage.follow(browseId: 'UC1', name: 'Yeat', thumbnailUrl: null);

    final service = _Counting();
    final c = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        youtubeServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(c.dispose);
    final sub = c.listen(latestReleasesProvider, (_, _) {});
    addTearDown(sub.close);

    expect(await c.read(latestReleasesProvider.future), hasLength(1));
    expect(service.calls, 1);

    // Quello che fa runSync a ogni passata.
    c.invalidate(followsProvider);
    c.read(followsProvider);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(latestReleasesProvider).isLoading, isFalse);
    expect(service.calls, 1, reason: 'stessa gente: niente da riscaricare');

    // Un artista in piu', invece, va letto.
    await storage.follow(
      browseId: 'UC2',
      name: 'Nettspend',
      thumbnailUrl: null,
    );
    c.invalidate(followsProvider);
    c.read(followsProvider);
    await c.read(latestReleasesProvider.future);
    expect(service.calls, 3);
  });
}
