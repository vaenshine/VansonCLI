# VansonCLI

![VansonCLI Logo](assets/vansoncli-logo-512.png)

**Injected iOS runtime workspace for AI-assisted debugging, UI inspection, network analysis, memory workflows, and patch experimentation in authorized test environments.**

**English** | [简体中文](./docs/README_CN.md) | [繁體中文](./docs/README_TW.md) | [العربية](./docs/README_AR.md) | [Deutsch](./docs/README_DE.md) | [Español](./docs/README_ES.md) | [Français](./docs/README_FR.md) | [日本語](./docs/README_JA.md) | [한국어](./docs/README_KO.md) | [Português](./docs/README_PT.md) | [Русский](./docs/README_RU.md) | [ไทย](./docs/README_TH.md) | [Tiếng Việt](./docs/README_VI.md)

![Platform](https://img.shields.io/badge/Platform-iOS%2014.0%2B-black)
![Build](https://img.shields.io/badge/Build-Theos-blue)
![Package](https://img.shields.io/badge/Package-dylib%20%2B%20deb-purple)
![License](https://img.shields.io/badge/License-MIT-green)

> [![Join Telegram](https://img.shields.io/badge/Join-Telegram%20Channel-blue?logo=telegram&logoWidth=20&labelColor=26A5E4&color=white)](https://t.me/VansonCLI)

---

## Introduction

**VansonCLI** turns an injected iOS process into a live runtime workspace that can be inspected, queried, edited, and operated from a floating panel. It combines AI chat, Objective-C runtime exploration, UIKit view picking, network capture, memory scanning, patch management, artifacts, and diagnostics in one compact interface.

The project is built as a Theos tweak for research, debugging, and technical exchange. Its core idea is to expose the target process as structured tools so a human operator and an AI assistant can work on the same runtime context: UI hierarchy, network traffic, runtime metadata, memory values, patch records, and generated artifacts.

## Compatibility Notes

- **Target platform**: iOS 14.0+, arm64, MobileSubstrate-compatible injection environment.
- **Build environment**: macOS with Theos and an iOS arm64 target toolchain.
- **Runtime scope**: behavior depends on the target app, injection method, sandbox state, system version, and available entitlements.
- **AI providers**: OpenAI-compatible Chat Completions and Responses endpoints, Anthropic, Gemini, and custom compatible providers.
- **Language support**: 简体中文, 繁體中文, English, العربية, Deutsch, Español, Français, 日本語, 한국어, Português, Русский, ไทย, Tiếng Việt.

## Navigation

- **AI Chat**: chat with the current app context, run tool calls, inspect verification results, attach references, and manage provider/model state.
- **Inspect**: browse Objective-C classes, methods, ivars, properties, protocols, strings, process metadata, loaded modules, and live instances.
- **Network**: capture HTTP/HTTPS/WebSocket traffic, inspect formatted headers/params/body, replay requests, manage favorites, rules, HAR export, and regex filters.
- **Artifacts**: review generated screenshots, logs, tool outputs, diagnostics, and saved runtime artifacts.
- **Patches**: manage method patches, hooks, value patches, network rules, retryable tool results, and patch notes.
- **Code and Memory**: inspect code-oriented outputs, scan values, refine memory candidates, preview values, and run controlled write workflows.
- **Settings**: manage AI providers, endpoint mode, API version, API key, role preset, model list, token limits, reasoning depth, language, build metadata, and about information.

## Highlights

- **AI-assisted runtime operations**: VansonCLI gives the assistant structured tool access to UIKit hierarchy, network flow, runtime objects, memory state, patches, traces, and artifacts.
- **Model provider editor**: configure base URL, API version, endpoint mode, API key, role preset, active model, token limit, GPT reasoning depth, model fetching, test calls, and call logs.
- **UIKit inspector**: pick views by touch, inspect hierarchy and constraints, edit common view properties, toggle pick highlight borders, and send selected UI context into chat.
- **Network workspace**: view request information in tabbed modals, edit replay headers/params/body inline, format params and payloads, favorite flows, export HAR, and test regex rules.
- **Chat ergonomics**: compact bubbles, reference cards, stop control, retryable tool blocks, verification detail, context usage tracking, and automatic reference clearing after send.
- **Memory and patch workflows**: scan values, refine candidates, browse memory, manage patch records, install hooks, and keep reversible notes around risky runtime changes.
- **Panel experience**: compact landscape shell, floating entry button, brand icon integration, localized UI, and high-density controls designed for phone-sized screens.

## Screenshots


### On-device vertical screenshots

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/IMG_0173.PNG" alt="VansonCLI live phone screenshot 1" width="180"></td>
    <td align="center"><img src="docs/screenshots/IMG_0174.PNG" alt="VansonCLI live phone screenshot 2" width="180"></td>
    <td align="center"><img src="docs/screenshots/IMG_0175.PNG" alt="VansonCLI live phone screenshot 3" width="180"></td>
    <td align="center"><img src="docs/screenshots/IMG_0176.PNG" alt="VansonCLI live phone screenshot 4" width="180"></td>
    <td align="center"><img src="docs/screenshots/IMG_0177.PNG" alt="VansonCLI live phone screenshot 5" width="180"></td>
  </tr>
</table>


## Installation

See [INSTALL.md](./INSTALL.md) for environment setup, packaging, installation flow, and common troubleshooting.

## Build

Requirements:

- macOS with Xcode Command Line Tools (`xcode-select --install`)
- Theos installed and available through the `THEOS` environment variable
- iOS SDK available to Theos
- arm64 iOS target toolchain
- `clang`, `make`, `ldid`, and `dpkg-deb`
- MobileSubstrate / Substitute / ElleKit compatible authorized test device

Current Makefile target:

- `TARGET := iphone:clang:latest:14.0`
- `ARCHS = arm64`

Build a release package:

```bash
./scripts/build_release.sh
```

Output artifacts:

- `release/VansonCLI_1.0.dylib`
- `packages/com.vanson.cli_1.0_iphoneos-arm.deb`

## Documentation

- [Installation](./INSTALL.md): build environment, package flow, install flow, and troubleshooting.
- [Architecture](./docs/ARCHITECTURE.md): module map, AI tool-call flow, network flow, UI inspector flow, and safety mode.
- [Safety](./docs/SAFETY.md): authorized-use boundary, sensitive data handling, AI provider key guidance, and patch risk controls.
- [Screenshots](./docs/SCREENSHOTS.md): mapping between public screenshots and current UI modules.
- [Changelog](./CHANGELOG.md): release notes and capability timeline.

## Project Layout

- `src/AI`: AI adapters, chat engine, model settings, prompt manager, token tracking, and tool execution.
- `src/UI`: UIKit panels, tabs, chat UI, network UI, inspect UI, settings, and about page.
- `src/Runtime`: runtime scanning and value reading.
- `src/Network`: request capture, URL protocol hooks, WebSocket hooks, and network records.
- `src/Patches`: patch, value, hook, and network rule models.
- `src/Memory`: memory scan, browse, and locate engines.
- `assets`: project logo and public visual assets.
- `UiOptimized`: public screenshots for README and release pages.
- `docs/screenshots`: live portrait screenshots captured from on-device runs.
- `scripts`: release build helper scripts.

## Changelog

See [Releases](https://github.com/vaenshine/VansonCLI/releases).

## Credits

- Developer: **Vaenshine**
- Project links: [GitHub](https://github.com/vaenshine/VansonCLI) / [Telegram](https://t.me/VansonCLI)
- License: **MIT License**

## Disclaimer

VansonCLI is provided for lawful testing, debugging, learning, and technical exchange. Use it only on apps, devices, accounts, and systems you own or are authorized to test.

Users are responsible for complying with local laws, platform rules, app terms, and third-party service terms. All operations performed with this tool are made independently by the user. Any risks including target app crashes, data loss or corruption, account restrictions, device instability, service violations, and all resulting direct or indirect losses are borne by the user.

VansonCLI is a general technical debugging workspace. It ships with no preset targets, custom operation schemes, or app-specific adaptations.

## Important Statement

This project is released under the **MIT License** for research, debugging, learning, and community exchange.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=vaenshine/VansonCLI&type=Date)](https://star-history.com/#vaenshine/VansonCLI&Date)
