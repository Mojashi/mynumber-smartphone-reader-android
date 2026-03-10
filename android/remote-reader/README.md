# Remote Smart Card Reader Fork

This is a workspace-local fork of the upstream `vsmartcard` Android app.

Purpose here:

- use a Pixel as an NFC-backed reader for a My Number card
- connect to macOS `vpcd`
- avoid QR scanning by using manual host/port entry or a `vpcd://HOST:PORT`
  deeplink

What already works in this codebase:

- manual `hostname` and `port` settings
- import via `vpcd://...` deep link
- NFC reader mode with `IsoDep`
- `vpcd` socket protocol

What is not yet done here:

- local APK build in this workspace
- app-specific UX cleanup for My Number flows

## Build prerequisites

This project was checked with:

- `JAVA_HOME=/opt/homebrew/opt/openjdk@17`
- Gradle wrapper `8.10`

The current blocking item for `assembleDebug` is only the Android SDK path.
Create `local.properties` from `local.properties.example` and point it at your
SDK, for example:

```sh
cp local.properties.example local.properties
sed -i '' "s#__SDK_DIR__#$HOME/Library/Android/sdk#" local.properties
JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug
```

Useful commands from the workspace root:

```sh
bash ./mynumber-bridge/scripts/print_vpcd_urls.sh
bash ./mynumber-bridge/scripts/push_vpcd_url_android.sh
```

Upstream project:

- https://github.com/frankmorgner/vsmartcard
