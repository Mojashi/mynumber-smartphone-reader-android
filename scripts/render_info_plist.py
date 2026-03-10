#!/usr/bin/env python3

from __future__ import annotations

import argparse
import pathlib
import plistlib


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Patch a staged vpcd Info.plist with a real USB vendor/product ID."
    )
    parser.add_argument("--template", required=True, help="Path to the staged Info.plist")
    parser.add_argument("--output", required=True, help="Path to write the patched plist")
    parser.add_argument("--vendor-id", required=True, help="Hex vendor ID, e.g. 0x18d1")
    parser.add_argument("--product-id", required=True, help="Hex product ID, e.g. 0x4ee1")
    parser.add_argument(
        "--friendly-name",
        default="/dev/null:0x8C7B",
        help="Socket target encoded in the bundle metadata",
    )
    parser.add_argument(
        "--manufacturer-string",
        default="Virtual Smart Card Architecture",
        help="ifdManufacturerString override",
    )
    parser.add_argument(
        "--product-string",
        default="Virtual PCD",
        help="ifdProductString override",
    )
    return parser.parse_args()


def as_array(value: str) -> list[str]:
    return [value]


def main() -> int:
    args = parse_args()

    template_path = pathlib.Path(args.template)
    output_path = pathlib.Path(args.output)

    with template_path.open("rb") as fh:
        plist = plistlib.load(fh)

    plist["ifdVendorID"] = as_array(args.vendor_id)
    plist["ifdProductID"] = as_array(args.product_id)
    plist["ifdFriendlyName"] = as_array(args.friendly_name)
    plist["ifdManufacturerString"] = args.manufacturer_string
    plist["ifdProductString"] = args.product_string

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("wb") as fh:
        plistlib.dump(plist, fh, sort_keys=False)

    print(f"wrote {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
