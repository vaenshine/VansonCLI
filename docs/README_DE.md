# VansonCLI

![VansonCLI Logo](../assets/vansoncli-logo-512.png)

**Injected iOS runtime workspace for AI-assisted debugging, UI inspection, network analysis, memory workflows, and patch experiments in authorized test environments.**

[English](../README.md) | [简体中文](./README_CN.md) | [繁體中文](./README_TW.md) | [العربية](./README_AR.md) | **Deutsch** | [Español](./README_ES.md) | [Français](./README_FR.md) | [日本語](./README_JA.md) | [한국어](./README_KO.md) | [Português](./README_PT.md) | [Русский](./README_RU.md) | [ไทย](./README_TH.md) | [Tiếng Việt](./README_VI.md)

![Platform](https://img.shields.io/badge/Platform-iOS%2014.0%2B-black)
![Build](https://img.shields.io/badge/Build-Theos-blue)
![Package](https://img.shields.io/badge/Package-dylib%20%2B%20deb-purple)
![License](https://img.shields.io/badge/License-MIT-green)

> [![Join Telegram](https://img.shields.io/badge/Join-Telegram%20Channel-blue?logo=telegram&logoWidth=20&labelColor=26A5E4&color=white)](https://t.me/VansonCLI)

---

## Introduction

**VansonCLI** turns an injected iOS process into a live runtime workspace. It brings AI chat, Objective-C runtime inspection, UIKit view picking, network capture, memory scanning, patch management, artifacts, and diagnostics into one compact floating panel.

## Compatibility Notes

- **Target platform**: iOS 14.0+, arm64, MobileSubstrate-compatible injection environment.
- **Build environment**: macOS, Theos, and an iOS arm64 toolchain.
- **AI providers**: OpenAI-compatible Chat Completions / Responses, Anthropic, Gemini, and custom compatible providers.
- **Runtime scope**: behavior depends on the target app, injection method, sandbox state, system version, and entitlements.

## Navigation

- **AI Chat**: chat with current app context, run tool calls, inspect verification details, and manage provider/model state.
- **Inspect**: browse Objective-C runtime metadata, modules, strings, and live instances.
- **Network**: capture HTTP/HTTPS/WebSocket traffic, inspect formatted params and bodies, replay requests, and export HAR.
- **Artifacts**: review screenshots, logs, diagnostics, and tool outputs.
- **Patches and Memory**: manage hooks, value patches, network rules, memory scans, and controlled writes.
- **Settings**: configure providers, endpoint mode, API version, API key, model list, token limits, and reasoning depth.

## Highlights

- Structured AI tool access to UIKit, network, runtime, memory, patches, traces, and artifacts.
- Provider editor with model sync, test calls, call logs, role presets, and GPT reasoning depth.
- Touch-based UI picking, hierarchy inspection, view editing, and optional pick highlight borders.
- Network request modal with Info, Params, Headers, Body, and Replay tabs.
- Compact chat bubbles, reference cards, stop control, retryable tool blocks, and context usage tracking.

## Screenshots


### Vertikale Geräte-Screenshots

<table>
  <tr>
    <td align="center"><img src="screenshots/IMG_0173.PNG" alt="VansonCLI live phone screenshot 1" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0174.PNG" alt="VansonCLI live phone screenshot 2" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0175.PNG" alt="VansonCLI live phone screenshot 3" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0176.PNG" alt="VansonCLI live phone screenshot 4" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0177.PNG" alt="VansonCLI live phone screenshot 5" width="180"></td>
  </tr>
</table>


## Build and Docs

```bash
./scripts/build_release.sh
```

- [Installation](../INSTALL.md)
- [Architecture](./ARCHITECTURE.md)
- [Safety](./SAFETY.md)
- [Screenshots](./SCREENSHOTS.md)
- [Changelog](../CHANGELOG.md)

## Disclaimer

VansonCLI is provided for lawful testing, debugging, learning, and technical exchange. Use it only on apps, devices, accounts, and systems you own or are authorized to test.
