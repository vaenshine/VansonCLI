# Installation

This guide covers the local build and package flow for VansonCLI.

## Requirements

- macOS with Xcode Command Line Tools (`xcode-select --install`)
- Theos installed locally
- `THEOS` environment variable pointing to the Theos directory
- iOS SDK available to Theos
- arm64 iOS target toolchain
- `clang`, `make`, `ldid`, and `dpkg-deb`
- MobileSubstrate / Substitute / ElleKit compatible target environment
- Authorized test device, app, account, and system

## Makefile Target

The current package is configured as:

- `TARGET := iphone:clang:latest:14.0`
- `ARCHS = arm64`
- Package architecture: `iphoneos-arm`

## Build

Build the release package:

```bash
./scripts/build_release.sh
```

The build script runs:

```bash
make package FINALPACKAGE=1 DEBUG=0
```

Expected artifacts:

- `release/VansonCLI_1.0.dylib`
- `packages/com.vanson.cli_1.0_iphoneos-arm.deb`

The script prints SHA-256 hashes for generated artifacts.

## Install Flow

1. Build the `.deb` package.
2. Transfer `packages/com.vanson.cli_1.0_iphoneos-arm.deb` to the authorized test device.
3. Install it through your package manager or deployment workflow.
4. Restart the target app.
5. Open the floating VansonCLI entry and configure AI providers in Settings.

## AI Provider Setup

The Settings page supports:

- Base URL
- API version
- Endpoint mode
- API key
- Role preset
- Active model
- Token limit
- GPT reasoning depth
- Model fetching
- Test call
- Call logs

Use a dedicated test API key. Rotate the key after demos, contests, or shared-device testing.

## Troubleshooting

- **No floating entry**: verify the tweak filter, injection environment, and target app restart.
- **AI chat fails**: open Settings, confirm endpoint, API key, endpoint mode, model name, and test call logs.
- **No network records**: confirm the target traffic uses supported URLSession / URLProtocol / WebSocket paths.
- **Replay has empty fields**: open the request modal and check Info, Params, Headers, Body, and Replay tabs.
- **Patch does not apply**: confirm class name, selector, object lifetime, capability guard, and safe mode state.
- **Build fails**: confirm Theos, SDK paths, arm64 target toolchain, and `THEOS` environment variable.

## Clean Generated Artifacts

Generated build artifacts are ignored by `.gitignore`.

```bash
rm -rf .theos release packages tmp output
```
