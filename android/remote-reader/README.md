# Remote Smart Card Reader Fork

このディレクトリは、upstream `vsmartcard` Android アプリの
workspace ローカル fork です。

この fork の目的は次です。

- Pixel をマイナンバーカード用の NFC reader として使う
- macOS 側の `vpcd` と接続する
- `vpcd://HOST:PORT` の deeplink や手入力を使い、QR 依存を減らす

この codebase ですでに動いているもの:

- `hostname` / `port` の手動設定
- `vpcd://...` deep link での取込
- `IsoDep` を使った NFC reader mode
- `vpcd` socket protocol

まだ整理し切れていないもの:

- MyNumber 専用 UX への全面的な整理
- upstream 由来コードの縮小と専用化

## Build 前提

確認した build 環境:

- `JAVA_HOME=/opt/homebrew/opt/openjdk@17`
- Gradle wrapper `8.10`

`assembleDebug` で必要なのは Android SDK path です。
`local.properties.example` から `local.properties` を作り、SDK を指してください。
例えば:

```sh
cp local.properties.example local.properties
sed -i '' "s#__SDK_DIR__#$HOME/Library/Android/sdk#" local.properties
JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew assembleDebug
```

workspace root から便利なコマンド:

```sh
bash ./mynumber-bridge/scripts/print_vpcd_urls.sh
bash ./mynumber-bridge/scripts/push_vpcd_url_android.sh
```

upstream project:

- https://github.com/frankmorgner/vsmartcard
