# Installing Crocuta

Every build is on the
[Releases page](https://github.com/IsThisDemi/Crocuta/releases/latest). None
of them comes from an app store, so each platform asks for one extra step
the first time. This page covers those steps.

Builds **carry no personal data**: no sync address, no secret, no account.
Everyone sets up their own [sync](SYNC.md) from Settings, so a build can be
handed to a friend as it is.

- [Mac](#-mac)
- [iPhone](#-iphone)
- [Android](#-android)
- [Windows](#-windows)
- [Good to know](#good-to-know)

## 🍎 Mac

Requires an **Apple Silicon** Mac (M1 or later) with **macOS 14** or newer.

1. Download `Crocuta-…-apple-silicon.dmg` and open it.
2. Drag **Crocuta** into the *Applications* folder next to it.
3. Open Crocuta from *Applications*.

The app isn't notarized by Apple, so on the first launch macOS says it
can't verify the developer. Unblock it once, in one of two ways:

- **System Settings → Privacy & Security**: at the bottom, next to
  *"Crocuta was blocked"*, press **Open Anyway** and confirm.
- If macOS instead says the app **"is damaged"**, open Terminal and run
  `xattr -dr com.apple.quarantine /Applications/Crocuta.app`, then open
  Crocuta again.

## 📱 iPhone

Requires **iOS 17** or newer. The `.ipa` is installed with **AltStore
Classic** and a **free Apple ID**: no paid developer account needed.

### 1. Set up AltStore (once)

1. On your Mac, download **AltServer** from <https://altstore.io> and launch
   it: a diamond icon appears in the menu bar.
2. Connect the iPhone with a cable and unlock it. From the AltServer menu
   choose *Install AltStore → [your iPhone]* and sign in with your Apple ID:
   AltServer uses it to sign apps.
3. On the iPhone: *Settings → General → VPN & Device Management →* your
   Apple ID *→ Trust*. Without this, AltStore won't open.

### 2. Install Crocuta

Download `Crocuta-…-iphone.ipa`, then either:

- **From the Mac**: hold **⌥ Option** and click the AltServer icon in the
  menu bar. The *Sideload .ipa…* item only appears while Option is held.
  Pick your iPhone, then the `.ipa`. (Dragging the file onto the icon does
  nothing.)
- **From the iPhone**: with the Mac and the phone on the **same Wi-Fi**,
  send the `.ipa` to the phone (AirDrop or iCloud Drive), open AltStore,
  tap **+** in the top left and pick the file.

The `.ipa` is unsigned on purpose: AltStore signs it with your Apple ID
while installing.

### Free Apple ID limits

| Limit | Value | What it means |
|---|---|---|
| Signature | **7 days** | After a week the app stops opening until it's re-signed |
| Sideloaded apps | **3 at a time** | Apple allows no more than 3 apps signed with a free Apple ID per device |
| New App IDs | **~10 every 7 days** | Only matters if you change the bundle ID often while developing |

**Keeping it alive:** AltStore renews the signature in the background **as
long as AltServer is running on the Mac and both are on the same Wi-Fi**.
Keep AltServer open and launch AltStore on the phone now and then. If more
than 7 days pass, reinstall: your likes, playlists and stats stay on the
device.

> **AltStore PAL** (the EU marketplace) **can't** install personal `.ipa`
> files: it only distributes apps notarized by Apple. Use AltStore Classic.

## 🤖 Android

Requires **Android 7** or newer on a 64-bit ARM phone (practically every
phone from the last several years).

1. Download `Crocuta-…-android-arm64.apk` on the phone.
2. Open it. Android asks to allow installs from that app (your browser or
   file manager): allow it, go back and tap **Install**.
3. If Play Protect warns about an unknown app, choose **Install anyway**.

From a computer with `adb` you can also run
`adb install -r Crocuta-…-android-arm64.apk`.

Lock-screen and notification controls aren't there yet on Android.

## 🖥️ Windows

Requires **Windows 10** or newer, 64-bit.

- **Installer**: run `Crocuta-…-windows-setup.exe`.
- **Portable**: unzip `Crocuta-…-windows-portable.zip` anywhere and launch
  `Crocuta.exe`.

The app isn't signed with a paid certificate, so SmartScreen may say it
protected your PC: click **More info → Run anyway**.

## Good to know

- **Updating**: install the new version over the old one. Your library,
  history and settings are kept.
- **Sync** between your devices is optional and runs on your own Google
  Drive: see [SYNC.md](SYNC.md).
- **When playback stops working** for every song, YouTube has probably
  changed something on its side: a new release usually fixes it.
- **CarPlay**: on iOS 26 Crocuta is available as a widget. A full CarPlay
  app needs an entitlement Apple grants only on request. Apple Watch isn't
  supported.
