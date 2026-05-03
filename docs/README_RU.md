# VansonCLI

![VansonCLI Logo](../assets/vansoncli-logo-512.png)

**Инъекционная iOS runtime-среда для AI-assisted debugging, UI inspection, network analysis, memory workflows и patch experiments в авторизованных тестовых окружениях.**

[English](../README.md) | [简体中文](./README_CN.md) | [繁體中文](./README_TW.md) | [العربية](./README_AR.md) | [Deutsch](./README_DE.md) | [Español](./README_ES.md) | [Français](./README_FR.md) | [日本語](./README_JA.md) | [한국어](./README_KO.md) | [Português](./README_PT.md) | **Русский** | [ไทย](./README_TH.md) | [Tiếng Việt](./README_VI.md)

![Platform](https://img.shields.io/badge/Platform-iOS%2014.0%2B-black)
![Build](https://img.shields.io/badge/Build-Theos-blue)
![Package](https://img.shields.io/badge/Package-dylib%20%2B%20deb-purple)
![License](https://img.shields.io/badge/License-MIT-green)

> [![Join Telegram](https://img.shields.io/badge/Join-Telegram%20Channel-blue?logo=telegram&logoWidth=20&labelColor=26A5E4&color=white)](https://t.me/VansonCLI)

---

## Введение

**VansonCLI** превращает инъецированный iOS process в живую runtime-среду. Он объединяет AI chat, Objective-C runtime inspection, UIKit view picking, network capture, memory scanning, patch management, artifacts и diagnostics в компактной floating panel.

## Совместимость

- **Целевая платформа**: iOS 14.0+, arm64, MobileSubstrate-compatible injection environment.
- **Build environment**: macOS, Theos и iOS arm64 toolchain.
- **AI providers**: OpenAI-compatible Chat Completions / Responses, Anthropic, Gemini и custom compatible providers.
- **Runtime scope**: зависит от target app, injection method, sandbox state, system version и entitlements.

## Навигация

- **AI Chat**: app context, tool calls, verification details, references, provider/model state.
- **Inspect**: Objective-C classes, methods, ivars, properties, protocols, strings, modules, live instances.
- **Network**: HTTP/HTTPS/WebSocket traffic, formatted params/body, replay, HAR export.
- **Artifacts**: screenshots, logs, diagnostics, tool outputs.
- **Patches / Memory**: hooks, value patches, network rules, memory scan, controlled writes.
- **Settings**: providers, endpoint mode, API version, API key, models, token limits, reasoning depth.

## Скриншоты


### Вертикальные скриншоты с устройства

<table>
  <tr>
    <td align="center"><img src="screenshots/IMG_0173.PNG" alt="VansonCLI live phone screenshot 1" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0174.PNG" alt="VansonCLI live phone screenshot 2" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0175.PNG" alt="VansonCLI live phone screenshot 3" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0176.PNG" alt="VansonCLI live phone screenshot 4" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0177.PNG" alt="VansonCLI live phone screenshot 5" width="180"></td>
  </tr>
</table>


## Build и документация

```bash
./scripts/build_release.sh
```

- [Installation](../INSTALL.md)
- [Architecture](./ARCHITECTURE.md)
- [Safety](./SAFETY.md)
- [Screenshots](./SCREENSHOTS.md)
- [Changelog](../CHANGELOG.md)

## Disclaimer

VansonCLI предоставляется для законного тестирования, отладки, обучения и технического обмена. Используйте его только с apps, devices, accounts и systems, которыми вы владеете или которые вам разрешено тестировать.
