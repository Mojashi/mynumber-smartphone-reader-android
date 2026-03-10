# MyNumber Bridge PoC

This directory captures the Mac-side work needed to use an Android phone as a
network-backed NFC smart card reader for macOS smart card apps.

The working architecture is:

1. `vpcd` exposes a virtual PC/SC reader on macOS.
2. An Android app speaks the `vpicc` socket protocol over TCP.
3. The Android app forwards APDUs to a physical My Number card via `IsoDep`.

This avoids reverse-engineering JPKI itself. The host only sees a smart card
reader and opaque APDU traffic.

There is now a second host-side path for better UX:

1. `vpcd` still exposes the virtual PC/SC reader on macOS.
2. The Android app advertises a Bluetooth Classic RFCOMM service when a card is present.
3. A tiny macOS helper connects to that paired Android service and forwards bytes into the local VPCD TCP port.
4. The Android app still forwards APDUs to the physical My Number card via `IsoDep`.

There is also a first-cut desktop app on macOS:

1. `MyNumber Bridge.app` wraps the Bluetooth RFCOMM client helper.
2. It shows setup, bridge state, and the current step in one place.
3. It lets you pick a paired Android device, start/stop the bridge, and open logs.

## Current status

Verified on this machine:

- macOS 15.2
- Apple Silicon
- Command Line Tools only, no full Xcode
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
    - macOS app bundle zip
    - staged `vpcd` payload tarball
  - publishes them to a GitHub Release

At the moment the release workflow is aimed at beta distribution, not App Store
or Play Store delivery.

## Quick start

Build a staged `vpcd` bundle and helper binaries:

```sh
bash ./mynumber-bridge/scripts/build_vpcd_macos.sh
```

Build the menu bar app bundle:

```sh
bash ./mynumber-bridge/scripts/build_menubar_app_macos.sh
open "./mynumber-bridge/build/mac-app/MyNumber Bridge.app"
```

Print only the `vpcd://...` URLs for the Android app:

```sh
bash ./mynumber-bridge/scripts/print_vpcd_urls.sh
```

List candidate USB devices that can be used to trigger the macOS reader bundle:

```sh
bash ./mynumber-bridge/scripts/list_usb_ids.sh
```

Render a patched `Info.plist` for your chosen USB device:

```sh
python3 ./mynumber-bridge/scripts/render_info_plist.py \
  --template mynumber-bridge/build/vsmartcard-stage/usr/local/libexec/SmartCardServices/drivers/ifd-vpcd.bundle/Contents/Info.plist \
  --output /tmp/Info.plist \
  --vendor-id 0x18d1 \
  --product-id 0x4ee1
```

At that point you can manually install:

- the bundle payload from
  `mynumber-bridge/build/vsmartcard-stage/usr/local/libexec/SmartCardServices/drivers/ifd-vpcd.bundle`
- the helper binary
  `mynumber-bridge/build/vsmartcard-stage/usr/local/bin/vpcd-config`

The install step is intentionally manual because it writes into
`/usr/local/libexec/SmartCardServices` and restarts the Apple smart card stack.
There is a helper for that:

```sh
bash ./mynumber-bridge/scripts/install_vpcd_macos.sh
```

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
bash ./mynumber-bridge/scripts/push_vpcd_url_android.sh
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
bash ./mynumber-bridge/scripts/build_menubar_app_macos.sh
open "./mynumber-bridge/build/mac-app/MyNumber Bridge.app"
```

3. Use the menu bar icon to:
   - open `Setup & Diagnostics`
   - select the paired Pixel
   - start the bridge
   - copy a diagnostic report or open helper logs if needed
4. Keep the usual macOS `vpcd` reader installed so the local PC/SC side can wake
   `127.0.0.1:35963` when MynaPortal or e-Tax opens the reader.
5. On Android, leave transport set to `Bluetooth Classic (Mac connects to this phone)`.
6. Bring `MyNumber Reader` to the front and touch the My Number card when the
   Mac app asks for it.

To use the lower-level CLI path directly:

1. Pair your Pixel and Mac in the system Bluetooth settings once.
2. Run the RFCOMM client helper:

```sh
/Users/mojashi/longlist/mynumber-bridge/build/bluetooth-helper/rfcomm-vpcd-client --device-address E8:D5:2B:2E:35:B4
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
- The desktop app is still a first cut. It wraps the helper, but does not yet
  install the PC/SC bundle automatically, notarize itself, or ship a polished
  installer.

## References

- `mynumber-bridge/PROTOCOL.md`
- `mynumber-bridge/android/remote-reader/README.md`
- Android NFC reader mode and `IsoDep`
- `vsmartcard` `virtualsmartcard` and `remote-reader`
