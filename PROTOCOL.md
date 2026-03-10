# VPCD Socket Protocol Notes

The host-side contract is simple enough to reimplement without touching JPKI.

## Transport framing

`vpcd` and the phone-side app exchange:

- a 2-byte big-endian payload length
- followed by that many payload bytes

There is no extra session header.

## Control packets

A payload of length `1` is a reader control command:

- `0x00`: power off
- `0x01`: power on
- `0x02`: warm reset
- `0x04`: fetch ATR

For `0x04`, the phone returns the ATR bytes in a normal framed response.

## APDU packets

Any payload longer than 1 byte is treated as a C-APDU. The phone forwards the
APDU to the card and returns the raw R-APDU bytes.

The host does not need to understand My Number APDUs. It only needs to relay
them losslessly.

## Android-side primitives

The minimum Android implementation uses:

- `NfcAdapter.enableReaderMode(...)`
- `Tag`
- `IsoDep`
- `IsoDep.connect()`
- `IsoDep.transceive(apdu)`
- `IsoDep.getHistoricalBytes()`

The upstream `remote-reader` app maps contactless card data into a synthetic
PC/SC ATR:

- Type A: use historical bytes from ATS
- Type B: use application data + protocol info + MBLI

That is sufficient for the host to see a contactless smart card via PC/SC.

## macOS-side constraints

Recent macOS versions do not expose a generic PCSC-Lite reader drop-in path.
`vpcd` works by pretending to be a USB smart card reader bundle, so:

- the bundle needs an `Info.plist`
- the plist must match a real USB vendor/product ID
- plugging that USB device triggers the bundle load

## Practical implication

The hard part is not APDU relay. The hard part is getting macOS to load the
reader bundle. Once `vpcd` is loaded, the phone-side protocol is small.
