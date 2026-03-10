# MyNumber Bridge

このリポジトリは、`Android スマホをマイナンバーカードのリーダーにする` ための
beta 実装です。

狙いは 3 つです。

- Android スマホでマイナンバーカードを読む
- その読取結果を macOS のスマートカード経路へ流す
- Mac のマイナポータル / e-Tax を QR 経由より楽に使えるようにする

基本構成はこうです。

1. macOS 上で `vpcd` が仮想 PC/SC リーダーを公開する
2. Android アプリが Bluetooth Classic の受け口を持つ
3. macOS helper がその Android に接続し、ローカルの VPCD ソケットへ転送する
4. Android アプリが `IsoDep` でマイナンバーカードへ APDU を投げる

JPKI 自体を解析するのではなく、`Mac からは普通のスマートカードリーダーに見せる`
方針です。

## 現状

手元では次の環境で確認しています。

- macOS 15.2
- Apple Silicon
- Command Line Tools のみ
- Pixel 8a

また、次の点を確認済みです。

- `vsmartcard` / `virtualsmartcard` の macOS build
- Android 側 `assembleDebug`
- macOS app build
- beta 用 `pkg` build
- GitHub Actions の CI / Release

Android 側の実装は `android/remote-reader` 以下にあり、`JAVA_HOME=/opt/homebrew/opt/openjdk@17`
で `assembleDebug` が通ります。

## 配布物

GitHub Releases には現在、次のファイルを置いています。

- `MyNumber-Reader-android-debug.apk`
  - Android スマホ側アプリ
- `MyNumber-Bridge-macos-beta.pkg`
  - `MyNumber Bridge.app` を `/Applications` に入れる beta 用 pkg
- `MyNumber-Bridge-macos-app.zip`
  - 同じ macOS app bundle の zip
- `MyNumber-Bridge-vpcd-stage-macos.tar.gz`
  - `vpcd` の staged payload 一式

最新の配布物は GitHub Releases を見てください。

## GitHub Actions

workflow は 2 本あります。

- `CI`
  - `push` / `pull_request` で実行
  - Android debug APK を build
  - macOS app bundle を build
- `Release`
  - `v*` tag または手動実行で起動
  - Android debug APK
  - macOS beta pkg
  - macOS app zip
  - staged `vpcd` tarball
  を作って GitHub Release に公開

今は App Store / Play Store 向けではなく、beta 配布向けの構成です。

## クイックスタート

### ローカルで build する

`vpcd` の staged payload を作る:

```sh
bash ./scripts/build_vpcd_macos.sh
```

macOS app を build する:

```sh
bash ./scripts/build_menubar_app_macos.sh
open "./build/mac-app/MyNumber Bridge.app"
```

beta 用 pkg を作る:

```sh
bash ./scripts/build_app_pkg_macos.sh
```

Android 向けの `vpcd://...` URL を表示する:

```sh
bash ./scripts/print_vpcd_urls.sh
```

reader bundle の読み込みトリガーに使える USB デバイス ID を調べる:

```sh
bash ./scripts/list_usb_ids.sh
```

USB vendor/product ID を埋めた `Info.plist` を生成する:

```sh
python3 ./scripts/render_info_plist.py \
  --template build/vsmartcard-stage/usr/local/libexec/SmartCardServices/drivers/ifd-vpcd.bundle/Contents/Info.plist \
  --output /tmp/Info.plist \
  --vendor-id 0x18d1 \
  --product-id 0x4ee1
```

その後、必要なファイルは次です。

- `build/vsmartcard-stage/usr/local/libexec/SmartCardServices/drivers/ifd-vpcd.bundle`
- `build/vsmartcard-stage/usr/local/bin/vpcd-config`

`vpcd` のインストールは `/usr/local/libexec/SmartCardServices` を触るため、今は手動寄りです。
補助スクリプトはあります。

```sh
bash ./scripts/install_vpcd_macos.sh
```

### GitHub Release から入れる

1. Mac に `MyNumber-Bridge-macos-beta.pkg` を入れる
2. Android に `MyNumber-Reader-android-debug.apk` を入れる
3. `MyNumber-Bridge-vpcd-stage-macos.tar.gz` から `vpcd` payload を手動導入する
4. Mac とスマホを Bluetooth で 1 回だけペアリングする
5. `MyNumber Bridge.app` を開き、スマホを選んで `Start Bridge`
6. Mac 側でマイナポータル / e-Tax を開き、スマホにカードを当てる

## 動作確認

`vpcd` を手動導入したあと:

1. `Info.plist` に使った vendor/product ID の USB デバイスを挿す
2. Apple の reader host を再起動する

```sh
sudo killall -SIGKILL -m '.*com.apple.ifdreader'
```

3. reader が見えるか確認する

```sh
system_profiler SPSmartCardsDataType
```

4. Android 側へ渡す URL を出す

```sh
/usr/local/bin/vpcd-config
```

QR が面倒なら、出てきた `vpcd://HOST:PORT` をそのまま Android 側へ入れても動きます。

`adb` が見えている場合は、Android へ直接流し込めます。

```sh
bash ./scripts/push_vpcd_url_android.sh
```

## Bluetooth Classic 経路

Android 側の transport は現在 2 つあります。

- `TCP / Network`
- `Bluetooth Classic (Mac connects to this phone)`

通常は Bluetooth Classic を使います。

1. Mac と Pixel を Bluetooth でペアリング
2. `MyNumber Bridge.app` を開く
3. 使う Pixel を選ぶ
4. `Start Bridge`
5. Android で `MyNumber Reader` を前面に出す
6. Mac 側でカード読取画面を開き、スマホへカードを当てる

低レベルの helper を直接使う場合はこうです。

```sh
./build/bluetooth-helper/rfcomm-vpcd-client --device-address E8:D5:2B:2E:35:B4
```

## 既知のギャップ

- macOS の reader bundle は、まだ実 USB デバイス ID を必要とする
- e-Tax や JPKI の仕様を変えるものではなく、あくまで Android NFC を背後に持つ仮想 reader
- Android 側は upstream ベースで、まだ専用実装へ整理し切っていない
- `MyNumber-Bridge-macos-beta.pkg` は app の導入だけで、`vpcd` bundle の自動導入まではしていない
- macOS app はまだ notarize していない
- Android は Play Store 配布ではなく APK 直配布

## 参考

- `PROTOCOL.md`
- `android/remote-reader/README.md`
- Android NFC reader mode / `IsoDep`
- `vsmartcard` / `virtualsmartcard` / `remote-reader`
