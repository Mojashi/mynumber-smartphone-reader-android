#!/usr/bin/env bash

set -euo pipefail

if [[ "${LC_ALL:-}" == "C.UTF-8" ]]; then
  unset LC_ALL
fi
export LANG="en_US.UTF-8"

system_profiler SPUSBDataType | awk '
  /Product ID:/ {
    product = $3
  }
  /Vendor ID:/ {
    vendor = $3
  }
  /Manufacturer:/ {
    sub(/.*: /, "")
    manufacturer = $0
  }
  /Location ID:/ {
    sub(/.*: /, "")
    if (vendor != "" && product != "") {
      printf "%s:%s %s (%s)\n", vendor, product, $0, manufacturer
    }
    product = ""
    vendor = ""
    manufacturer = ""
  }
'
