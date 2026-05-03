#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

make package FINALPACKAGE=1 DEBUG=0

if [[ -f release/VansonCLI_1.0.dylib ]]; then
  shasum -a 256 release/VansonCLI_1.0.dylib
fi

if [[ -f packages/com.vanson.cli_1.0_iphoneos-arm.deb ]]; then
  shasum -a 256 packages/com.vanson.cli_1.0_iphoneos-arm.deb
fi
