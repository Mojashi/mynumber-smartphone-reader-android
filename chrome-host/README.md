# Chrome Native Host PoC

This directory contains a macOS native messaging host for the Chrome extension
`e-Tax AP`.

The host name expected by the extension is:

`nta.chrome.ext`

Current behavior:

- accept Chrome native messaging connections
- bridge a subset of requests into `CLeTaxWEB://...`
- poll the e-Tax app group container for `data.plist` results
- return Chrome-style chunked `{"JSONDATA":"..."}` responses

Supported direct message names right now:

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

Unknown `MessageType` values are still logged and answered with a structured
error payload. That keeps the extension responsive while we learn the Chrome
flow.

## Install

```sh
bash ./mynumber-bridge/chrome-host/install_chrome_host.sh
```

If your installed extension ID differs from the default, pass it explicitly:

```sh
bash ./mynumber-bridge/chrome-host/install_chrome_host.sh --extension-id YOUR_ID
```

## Logs

Requests and responses are written to:

`~/Library/Logs/mynumber-bridge/nta.chrome.ext.log`

The macOS bridge uses the app group container created by `CLeTaxWEB.app`:

`~/Library/Group Containers/jp.go.nta.eTaxWebGroup`

Each request gets a per-UID folder such as:

`~/Library/Group Containers/jp.go.nta.eTaxWebGroup/<uid>/data.plist`

## Extension

The official `e-Tax AP` CRX can be downloaded from:

`https://dl.e-tax.nta.go.jp/clientweb/jizen_uketsuke/e-Tax-AP.crx`

The host installer does not install the extension itself.

## Local Test

You can exercise the native host without Chrome:

```sh
python3 ./mynumber-bridge/chrome-host/test_native_host.py \
  '{"MessageType":"StartProcess","uid":"probe-cli"}'
```

That should emit a list of native messaging frames, typically one or more
`{"JSONDATA":"..."}` chunks followed by `{"JSONDATA":""}`.
