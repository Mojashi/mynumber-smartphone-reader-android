# MyNumber Bridge

This repo is a beta implementation of one specific idea:

- use an Android phone as the card reader for a My Number card
- bridge that phone into macOS smart card flows
- make MynaPortal / e-Tax on Mac less dependent on QR handoff flows

The working architecture is:

1. `vpcd` exposes a virtual PC/SC reader on macOS.
2. The Android app exposes a Bluetooth Classic endpoint.
3. A macOS helper connects to that paired Android endpoint and forwards bytes into the local VPCD TCP port.
4. The Android app forwards APDUs to a physical My Number card via `IsoDep`.

This avoids reverse-engineering JPKI itself. The Mac side only sees a smart
card reader and opaque APDU traffic.

## Current status

Verified locally on:

- macOS 15.2
- Apple Silicon
- Command Line Tools only, no full Xcode
- Pixel 8a
- `vsmartcard` `virtualsmartcard` builds successfully once `SDKROOT`,
  `CPPFLAGS`, and `LDFLAGS` are pinned explicitly

The practical phone-side implementation is the forked `remote-reader` app under
`mynumber-bridge/android/remote-reader`. The Android SDK and Gradle wrapper are
working in this workspace with `JAVA_HOME=/opt/homebrew/opt/openjdk@17`, and
`assembleDebug` succeeds.

## GitHub Actions

This repo ships with two workflows:

- `CI`
  - runs on `push` and `pull_request`
  - builds the Android debug APK on Ubuntu
  - builds the macOS app bundle on macOS
- `Release`
  - runs on pushed tags like `v0.1.0` or via `workflow_dispatch`
  - builds:
    - Android debug APK
    - macOS beta pkg
    - macOS app bundle zip
    - staged `vpcd` payload tarball
  - publishes them to a GitHub Release

At the moment the release workflow is aimed at beta distribution, not App Store
or Play Store delivery.

## Release assets

Current beta releases contain:

- `MyNumber-Reader-android-debug.apk`
  - Android phone app
- `MyNumber-Bridge-macos-beta.pkg`
  - installs `MyNumber Bridge.app` into `/Applications`
  - does not yet install the `vpcd` bundle automatically
- `MyNumber-Bridge-macos-app.zip`
  - same macOS app bundle as a zip
- `MyNumber-Bridge-vpcd-stage-macos.tar.gz`
  - staged `vpcd` payload for manual install

The latest release is published on GitHub Releases for this repo.

## Quick start

### Local build

Build a staged `vpcd` bundle and helper binaries:

```sh
bash ./scripts/build_vpcd_macos.sh
```

Build the macOS app bundle:

```sh
bash ./scripts/build_menubar_app_macos.sh
open "./build/mac-app/MyNumber Bridge.app"
```

Build a beta pkg for the macOS app:

```sh
bash ./scripts/build_app_pkg_macos.sh
```

Print only the `vpcd://...` URLs for the Android app:

```sh
bash ./scripts/print_vpcd_urls.sh
```

List candidate USB devices that can be used to trigger the macOS reader bundle:

```sh
bash ./scripts/list_usb_ids.sh
```

Render a patched `Info.plist` for your chosen USB device:

```sh
python3 ./scripts/render_info_plist.py \
  --template build/vsmartcard-stage/usr/local/libexec/SmartCardServices/drivers/ifd-vpcd.bundle/Contents/Info.plist \
  --output /tmp/Info.plist \
  --vendor-id 0x18d1 \
  --product-id 0x4ee1
```

At that point you can manually install:

- the bundle payload from
  `build/vsmartcard-stage/usr/local/libexec/SmartCardServices/drivers/ifd-vpcd.bundle`
- the helper binary
  `build/vsmartcard-stage/usr/local/bin/vpcd-config`

The install step is intentionally manual because it writes into
`/usr/local/libexec/SmartCardServices` and restarts the Apple smart card stack.
There is a helper for that:

```sh
bash ./scripts/install_vpcd_macos.sh
```

### Beta install from GitHub Release

1. Install `MyNumber-Bridge-macos-beta.pkg` on your Mac.
2. Install `MyNumber-Reader-android-debug.apk` on your Android phone.
3. Manually install the staged `vpcd` payload from `MyNumber-Bridge-vpcd-stage-macos.tar.gz`.
4. Pair the phone and Mac over Bluetooth once.
5. Open `MyNumber Bridge.app`, pick the phone, and press `Start Bridge`.
6. Open MynaPortal or e-Tax on the Mac and touch the My Number card to the phone.

## Smoke test

After manual install:

1. Plug the USB device whose vendor/product ID you used in `Info.plist`.
2. Restart the Apple reader host:

```sh
sudo killall -SIGKILL -m '.*com.apple.ifdreader'
```

3. Confirm the reader is visible:

```sh
system_profiler SPSmartCardsDataType
```

4. Print the QR or URL for the Android side:

```sh
/usr/local/bin/vpcd-config
```

If the QR route is annoying, the output URL is just `vpcd://HOST:PORT`. Enter
that directly into the Android app.

If `adb` sees your Pixel, you can push the configuration without touching the
phone UI:

```sh
bash ./scripts/push_vpcd_url_android.sh
```

That launches Android's `VIEW` intent for the first advertised `vpcd://` URL.

## Bluetooth Classic path

The Android app now supports two transport modes:

- `TCP / Network`
- `Bluetooth Classic (Mac connects to this phone)`

To use the Bluetooth path from the menu bar app:

1. Pair your Pixel and Mac in the system Bluetooth settings once.
2. Build and open the app bundle:

```sh
bash ./scripts/build_menubar_app_macos.sh
open "./build/mac-app/MyNumber Bridge.app"
```

3. In `MyNumber Bridge`:
   - select the paired Pixel
   - start the bridge
   - open logs if needed
4. Keep the usual macOS `vpcd` reader installed so the local PC/SC side can wake
   `127.0.0.1:35963` when MynaPortal or e-Tax opens the reader.
5. On Android, leave transport set to `Bluetooth Classic (Mac connects to this phone)`.
6. Bring `MyNumber Reader` to the front and touch the My Number card when the
   Mac app asks for it.

To use the lower-level CLI path directly:

1. Pair your Pixel and Mac in the system Bluetooth settings once.
2. Run the RFCOMM client helper:

```sh
./build/bluetooth-helper/rfcomm-vpcd-client --device-address E8:D5:2B:2E:35:B4
```

3. Keep the usual macOS `vpcd` listener alive on `127.0.0.1:35963`.
4. On Android, set transport to `Bluetooth Classic (Mac connects to this phone)`.

## Known gaps

- The macOS bundle still needs a real USB device ID to get loaded by
  CryptoTokenKit.
- Nothing here changes e-Tax or JPKI behavior; this only gives macOS a virtual
  reader backed by Android NFC.
- The imported Android app is upstream-based and not yet reworked into a fresh
  minimal codebase.
- The macOS beta pkg currently installs the app only. It does not yet install
  the `vpcd` bundle automatically.
- The macOS app is not notarized yet.
- Android is still distributed as a direct APK, not through Play Store.

## References

- `PROTOCOL.md`
- `android/remote-reader/README.md`
- Android NFC reader mode and `IsoDep`
- `vsmartcard` `virtualsmartcard` and `remote-reader`
