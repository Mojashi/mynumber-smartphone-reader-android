# VPCD Socket Protocol メモ

host 側の契約はかなり小さいので、JPKI に触らなくても再実装できます。

## 転送フォーマット

`vpcd` とスマホ側アプリの間では、次をやり取りします。

- 2 バイトの big-endian payload length
- 続けてその長さぶんの payload bytes

追加のセッションヘッダはありません。

## 制御パケット

payload 長が `1` のときは reader 制御コマンドです。

- `0x00`: power off
- `0x01`: power on
- `0x02`: warm reset
- `0x04`: ATR 取得

`0x04` に対しては、スマホ側が通常の framed response として ATR bytes を返します。

## APDU パケット

payload 長が 2 以上なら C-APDU として扱います。スマホ側はそれをカードへ送り、
生の R-APDU bytes を返します。

host 側はマイナンバーカードの APDU 内容を理解する必要はなく、`ロスなく中継する`
だけで足ります。

## Android 側で最低限使うもの

最小実装では次を使います。

- `NfcAdapter.enableReaderMode(...)`
- `Tag`
- `IsoDep`
- `IsoDep.connect()`
- `IsoDep.transceive(apdu)`
- `IsoDep.getHistoricalBytes()`

upstream の `remote-reader` は、contactless card の情報から synthetic な PC/SC ATR を作ります。

- Type A: ATS の historical bytes を使う
- Type B: application data + protocol info + MBLI を使う

これで host 側からは contactless smart card が PC/SC reader 配下に見えます。

## macOS 側の制約

最近の macOS は generic な PCSC-Lite reader drop-in を素直には出していません。
`vpcd` は USB smart card reader bundle のふりをして読ませるので、次が必要です。

- bundle に `Info.plist` があること
- plist が実在する USB vendor/product ID と一致すること
- その USB デバイスを挿すと bundle load が走ること

## 実務上の意味

難しいのは APDU relay 自体ではありません。難しいのは `macOS に reader bundle を読ませること`
です。`vpcd` が読まれてしまえば、スマホ側の protocol はかなり小さいです。
