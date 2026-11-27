# Building and hacking on Crocuta

Crocuta is a single **Flutter** codebase for macOS, Windows, iPhone and
Android. This page covers building it, how it's put together, and its
known limits. To just install it, see [INSTALL.md](INSTALL.md).

## Requirements

- **Flutter SDK** (3.x): <https://docs.flutter.dev/get-started/install>
- **macOS**: Xcode + `xcode-select --install`
- **iPhone**: a Mac with Xcode
- **Windows**: Visual Studio with the "Desktop development with C++"
  workload; [Inno Setup 6](https://jrsoftware.org/isinfo.php) for the
  installer
- **Android**: the Android SDK and a JDK 17+ (Android Studio brings both)

## Running

```bash
flutter pub get

# The model that splits vocals from the instrumental for AutoMix and
# karaoke (64 MB, kept out of git). The build scripts fetch it on their
# own; by hand:
./tool/fetch_models.sh                                          # Mac
powershell -ExecutionPolicy Bypass -File tool\fetch_models.ps1  # Windows

flutter run -d macos      # on the Mac
flutter run -d windows    # on a Windows PC
flutter run               # on a connected iPhone or Android phone
```

## Building the release files

```bash
./tool/build_macos.sh                                            # Crocuta.app, ad-hoc signed
./tool/build_dmg.sh                                              # the .dmg for Apple Silicon Macs
./tool/build_ipa.sh                                              # unsigned .ipa for AltStore
flutter build apk --release --target-platform android-arm64      # the Android APK
powershell -ExecutionPolicy Bypass -File tool\build_windows.ps1  # installer + portable zip
```

| Script | Output |
|---|---|
| `build_macos.sh` | `build/macos/Build/Products/Release/Crocuta.app` |
| `build_dmg.sh` | `build/dmg/Crocuta-<version>-apple-silicon.dmg` |
| `build_ipa.sh` | `build/ipa/Crocuta.ipa` |
| `flutter build apk` | `build/app/outputs/flutter-apk/app-release.apk` |
| `build_windows.ps1` | `build\windows-dist\` |

If `build_dmg.sh` complains that the nested code is modified, delete
`build/macos/Build/Products/Release/Crocuta.app` and run it again: an
incremental build can leave a stale outer signature.

The Android release is signed with the local **debug key**, which is fine
for sideloading. To update an installed APK, build with the same machine
(or the same key), or uninstall the old one first.

### Your own builds with sync built in

None of the scripts puts a sync address or secret into the build. With
`--with-env` (`-WithEnv` on Windows) they read `.env` (see
[`.env.example`](../.env.example)) and include it as an initial value,
adopted on first launch. That's handy for your own devices, but **don't
share that build**: the values can be extracted from the binary.

## Running on an iPhone without AltStore

### With Xcode

1. `open ios/Runner.xcworkspace`
2. Select the **Runner** target → **Signing & Capabilities**, check
   *Automatically manage signing* and choose your **personal team** (your
   free Apple ID, listed as *"First Last (Personal Team)"*).
3. If you see *"Failed to register bundle identifier"*, change
   `PRODUCT_BUNDLE_IDENTIFIER` to something unique and try again.
4. Connect the iPhone and press ▶. The free Apple ID limits still apply:
   7 days, 3 apps.

### From the terminal

```bash
xcrun devicectl list devices        # find the UDID

cd ios && xcodebuild -workspace Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'id=<UDID>' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

xcrun devicectl device install app --device <UDID> \
  ~/Library/Developer/Xcode/DerivedData/Runner-*/Build/Products/Debug-iphoneos/Runner.app
xcrun devicectl device process launch --device <UDID> dev.riccardo.demuslike
```

`-allowProvisioningUpdates` works with a free Apple ID too, as long as
you're signed in to Xcode (*Settings → Accounts*). The project contains no
preconfigured signing team.

### Bundle IDs

The iOS and Android ID is `dev.riccardo.demuslike` (lowercase, as
provisioning requires). The macOS one is deliberately different
(`com.personal.demusLike`): changing it would move the sandbox container
and orphan the likes, playlists and stats already saved.

The app is set up for **background audio** on iOS
(`UIBackgroundModes: audio`), for access to the local proxy
(`NSAllowsLocalNetworking`) and, on macOS, for network client and server
(the `network.client` + `network.server` entitlements).

## Under the hood

| Component | Choice |
|---|---|
| Framework | **Flutter**: one codebase for macOS, Windows, iPhone and Android |
| Catalog | The **YouTube Music** InnerTube API (WEB_REMIX): search, pages, up-next, videos |
| Stream extraction | `youtube_explode_dart` + 9 rotating InnerTube clients, PO Token via a headless WebView |
| Playback | **`media_kit`** / libmpv, rebuilt with the audio filters AutoMix needs |
| Proxy | `stream_proxy.dart`: a local HTTP server that stitches Google's serving windows back together |
| AutoMix and karaoke | Beat grid, key and phrases in Dart; **UVR-MDX** vocal separation on **ONNX Runtime** (Core ML on Apple) |
| Lyrics | **LRCLIB**, cached for offline |
| Design | **Macchia**: black canvas, spot-shaped covers and controls that move like fluid (one 30 fps clock), accent from the cover; Outfit + Inter |
| Connect | **Bonjour** (`bonsoir`) + WebSocket, authenticated with the sync secret |
| Native on iPhone and Mac | WidgetKit, App Intents, MPNowPlayingInfoCenter |
| State and data | Riverpod, Hive |
| Sync | A Google Apps Script on your Drive (`tool/crocuta_sync.gs`), see [SYNC.md](SYNC.md) |

### libmpv with the audio filters

The libmpv that media_kit downloads only has ffmpeg's `equalizer` filter;
AutoMix needs `volume`, `highpass`, `alimiter`, `atempo` and more. The
frameworks in `third_party/media_kit_libs_{macos,ios}_video` are rebuilt by
`./tool/build_libmpv.sh` (about twenty minutes per platform; needs
`brew install cmake go meson ninja`). Everything it changes is in
`tool/libmpv/crocuta-filters.patch`.

### Project layout

```
lib/
├── main.dart                      # entry point, Hive + media_kit init, session restore
├── shortcuts.dart                 # desktop keyboard shortcuts
├── navigation.dart                # pushes to artist / album
├── providers.dart                 # global Riverpod providers (+ tabs and search focus)
├── design/
│   ├── tokens.dart                # colors, spacing, radii, shadows, motion
│   ├── typography.dart            # Outfit (display) + Inter (text)
│   ├── app_theme.dart             # ThemeData + the accent of the song
│   ├── spot.dart                  # the spot shape, seeded and alive
│   ├── chrome.dart                # sidebar or dock, and the space they take
│   ├── motion.dart                # spot-reveal page transitions
│   └── app_theme_ext.dart         # colors Material doesn't cover
├── models/                        # track, album, artist, playlist, lyrics
├── services/
│   ├── youtube_service.dart       # search, YTM pages, suggestions, lyrics
│   ├── stream_resolver.dart       # stream extraction (9 rotating clients)
│   ├── stream_proxy.dart          # local HTTP proxy, stitches Google's windows
│   ├── pot_service.dart           # PO Token via a headless WebView
│   ├── player_controller.dart     # queue, shuffle, repeat, session
│   ├── song_preloader.dart        # on-disk cache with a cap and LRU eviction
│   ├── automix.dart               # AutoMix: where to mix, how, for how long
│   ├── phrase_analysis.dart       # phrases and sections, for where a mix starts
│   ├── stem_separator.dart        # vocals and instrumental with ONNX Runtime
│   ├── karaoke.dart               # the vocals that fade out
│   ├── smart_reorder.dart         # the queue lined up by tempo and key
│   ├── discovery.dart             # Discover Weekly and Daily Mixes
│   ├── smart_playlists.dart       # On Repeat, Late Night, Forgotten…
│   ├── spotify_import.dart        # likes, playlists, albums, artists from Spotify
│   ├── apple_music_library.dart   # Apple Music library: Music app or exported XML
│   ├── connect.dart               # Crocuta Connect (Bonjour + WebSocket)
│   ├── sync_service.dart          # sync through Google Apps Script
│   ├── siri_service.dart          # the library Siri can name
│   ├── eq_controller.dart         # 10-band equalizer + preamp (libmpv af)
│   ├── now_playing_service.dart   # lock screen / Control Center bridge
│   └── storage_service.dart       # Hive: likes, playlists, stats, session
├── screens/
│   ├── app_shell.dart             # 4 tabs + a navigator per tab
│   ├── home_content.dart          # Top Picks, Made for You, new releases
│   ├── search_screen.dart         # search + suggestions + Browse
│   ├── browse_screens.dart        # categories as clusters of covers
│   ├── library_screen.dart        # Liked / Playlists / Artists / Albums / Stats
│   ├── media_detail_page.dart     # shared page: album, playlist, user playlist
│   ├── artist_screen.dart         # artist page
│   ├── queue_screen.dart          # queue
│   ├── stats_screen.dart          # listening stats
│   ├── lyrics_screen.dart         # synced lyrics
│   ├── eq_screen.dart             # equalizer
│   ├── video_screen.dart          # full-screen music video
│   ├── settings_screen.dart       # settings
│   └── now_playing_screen.dart    # full-screen player
├── widgets/
│   ├── app_background.dart        # canvas; the cover fades in and tints the page
│   ├── word_tab_bar.dart          # the phone dock: cover in the middle, sections as satellites
│   ├── den_rail.dart              # the desktop sidebar, with the docked player
│   ├── spot_controls.dart         # spot play button, spot cover + satellites
│   ├── spot_layouts.dart          # coat, cluster and staggered grid of spots
│   ├── track_tile.dart            # song row (+ context menu everywhere)
│   ├── track_context_menu.dart    # one list of actions, two presentations
│   ├── media_card.dart            # cards and horizontal rails
│   ├── motion_cover.dart          # the living cover
│   └── connect_views.dart         # the Connect sheet and remote
└── dev/readme_shots.dart          # debug-only driver for the README screenshots

ios/Runner/NowPlayingController.swift     # iOS lock screen
macos/Runner/NowPlayingController.swift   # macOS media keys + Control Center
ios/CrocutaWidget/, macos/CrocutaWidget/  # widgets (CarPlay too, on iOS 26)
android/                                  # the Android app
tool/                                     # build scripts, icons, README art, sync script
test/                                     # fast widget tests
integration_test/                         # tests on the real app
```

### Tests

```bash
flutter test
```

### README images

The screenshots come from the app itself, in debug, with a driver that
stages a song and walks through the screens:

```bash
flutter run -d macos --dart-define=README_SHOTS=1 --dart-define=README_SHOTS_SET=phone
```

`README_SHOTS_SET` is `phone`, `wide`, `browse` or `tabs`. In this mode the
app never opens your library: it builds a demo one in a temporary folder
(`lib/dev/readme_demo.dart`), with well-known songs, made-up stats and
searches, so the pictures show nothing of yours. Then
`python3 tool/make_readme_art.py <captures-folder>` composes the images in
`docs/readme/`. The app icons come from `python3 tool/make_icons.py`.

## Siri

It works without any entitlement and without a paid account, which is why
it's built with **App Intents** rather than SiriKit Media: the latter needs
`com.apple.developer.siri`, which a Personal Team can't get.

The price of that choice: **Siri doesn't accept free text in phrases.** It
generates one phrase for every value the app declares, so you can only name
what's *enumerable*. For Crocuta that's your library (likes, playlist
songs, recently played, followed artists), which the app publishes on every
change (`lib/services/siri_service.dart`, up to 600 songs, likes first,
because the tail is what gets cut).

For a song that **isn't** in your library there's "Search on Crocuta": the
phrase doesn't carry the value, Siri asks for it right after, and at that
point the text is free.

The phrases are in Italian ("Riproduci i preferiti su Crocuta") and live in
`ios/Runner/CrocutaIntents.swift`; after installing they also show up in the
Shortcuts app. Requires **iOS 17**.

## Known limitations

- YouTube can change its endpoints overnight. If search or playback stops
  working, first update `youtube_explode_dart` (`flutter pub upgrade`),
  then, if needed, adapt the InnerTube parsing in `youtube_service.dart`
  (especially the `itemSectionRenderer` structure of YouTube Music search).
- YouTube may answer 429 (rate limit) after too many extractions in a row:
  the service retries with backoff and switches client automatically.
- The player runs on **libmpv**, which handles every YouTube format;
  AVPlayer isn't used because it can't play YouTube's fMP4/Opus streams.
- Live videos and streams are filtered out of search: they have no
  extractable audio-only stream.
- In CarPlay, Crocuta is only a **widget** (iOS 26): a real CarPlay app
  needs an entitlement Apple grants only on request. No Apple Watch app.
- On Android there are no lock-screen or notification controls yet.
