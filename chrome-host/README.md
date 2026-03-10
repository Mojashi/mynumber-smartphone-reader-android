# Chrome Native Host PoC

このディレクトリには、Chrome 拡張 `e-Tax AP` 向けの macOS native messaging host が入っています。

拡張が期待する host 名は次です。

`nta.chrome.ext`

現状の動きはこうです。

- Chrome native messaging 接続を受ける
- 一部メッセージを `CLeTaxWEB://...` へ橋渡しする
- e-Tax の app group container から `data.plist` の結果を拾う
- Chrome 風の chunked `{"JSONDATA":"..."}` 応答を返す

現在、直接対応している `MessageType` は次です。

- `StartProcess`
- `PollingProcess`
- `EndProcess`
- `SignRelease`
- `SignLoadInfomation`
- `SignSetCertificateICCard`
- `SignSetCertificateP12`
- `SignToReport`
- `SignToReportEltax`
- `SignToCertificateRegistration`

未知の `MessageType` はログに残しつつ、構造化エラーを返します。

## インストール

```sh
bash ./chrome-host/install_chrome_host.sh
```

拡張 ID がデフォルトと違う場合は、明示的に渡してください。

```sh
bash ./chrome-host/install_chrome_host.sh --extension-id YOUR_ID
```

## ログ

リクエストとレスポンスは次に出ます。

`~/Library/Logs/mynumber-bridge/nta.chrome.ext.log`

macOS bridge は `CLeTaxWEB.app` が作る app group container を使います。

`~/Library/Group Containers/jp.go.nta.eTaxWebGroup`

各 request には `uid` ごとのフォルダが作られます。

`~/Library/Group Containers/jp.go.nta.eTaxWebGroup/<uid>/data.plist`

## 拡張

公式の `e-Tax AP` CRX は次から落とせます。

`https://dl.e-tax.nta.go.jp/clientweb/jizen_uketsuke/e-Tax-AP.crx`

この installer は拡張自体までは入れません。

## ローカルテスト

Chrome を使わずに native host だけ試す場合:

```sh
python3 ./chrome-host/test_native_host.py \
  '{"MessageType":"StartProcess","uid":"probe-cli"}'
```

通常は `{"JSONDATA":"..."}` の chunk が 1 個以上出て、最後に `{"JSONDATA":""}` が返ります。
