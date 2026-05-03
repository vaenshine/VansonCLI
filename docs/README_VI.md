# VansonCLI

![VansonCLI Logo](../assets/vansoncli-logo-512.png)

**Không gian runtime iOS dạng injected cho gỡ lỗi với AI, kiểm tra UI, phân tích mạng, workflow bộ nhớ và thử nghiệm patch trong môi trường kiểm thử được ủy quyền.**

[English](../README.md) | [简体中文](./README_CN.md) | [繁體中文](./README_TW.md) | [العربية](./README_AR.md) | [Deutsch](./README_DE.md) | [Español](./README_ES.md) | [Français](./README_FR.md) | [日本語](./README_JA.md) | [한국어](./README_KO.md) | [Português](./README_PT.md) | [Русский](./README_RU.md) | [ไทย](./README_TH.md) | **Tiếng Việt**

![Platform](https://img.shields.io/badge/Platform-iOS%2014.0%2B-black)
![Build](https://img.shields.io/badge/Build-Theos-blue)
![Package](https://img.shields.io/badge/Package-dylib%20%2B%20deb-purple)
![License](https://img.shields.io/badge/License-MIT-green)

> [![Join Telegram](https://img.shields.io/badge/Join-Telegram%20Channel-blue?logo=telegram&logoWidth=20&labelColor=26A5E4&color=white)](https://t.me/VansonCLI)

---

## Giới thiệu

**VansonCLI** biến một iOS process được inject thành runtime workspace trực tiếp. Nó kết hợp AI chat, Objective-C runtime inspection, UIKit view picking, network capture, memory scanning, patch management, artifacts và diagnostics trong một floating panel nhỏ gọn.

## Tương thích

- **Nền tảng mục tiêu**: iOS 14.0+, arm64, MobileSubstrate-compatible injection environment.
- **Môi trường build**: macOS, Theos và iOS arm64 toolchain.
- **AI providers**: OpenAI-compatible Chat Completions / Responses, Anthropic, Gemini và custom compatible providers.
- **Runtime scope**: phụ thuộc vào target app, injection method, sandbox state, system version và entitlements.

## Điều hướng

- **AI Chat**: app context, tool calls, verification details, references và provider/model state.
- **Inspect**: Objective-C classes, methods, ivars, properties, protocols, strings, modules và live instances.
- **Network**: HTTP/HTTPS/WebSocket traffic, formatted params/body, replay và HAR export.
- **Artifacts**: screenshots, logs, diagnostics và tool outputs.
- **Patches / Memory**: hooks, value patches, network rules, memory scan và controlled writes.
- **Settings**: providers, endpoint mode, API version, API key, models, token limits và reasoning depth.

## Ảnh chụp màn hình


### Ảnh chụp dọc trên thiết bị

<table>
  <tr>
    <td align="center"><img src="screenshots/IMG_0173.PNG" alt="VansonCLI live phone screenshot 1" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0174.PNG" alt="VansonCLI live phone screenshot 2" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0175.PNG" alt="VansonCLI live phone screenshot 3" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0176.PNG" alt="VansonCLI live phone screenshot 4" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0177.PNG" alt="VansonCLI live phone screenshot 5" width="180"></td>
  </tr>
</table>


## Build và tài liệu

```bash
./scripts/build_release.sh
```

- [Installation](../INSTALL.md)
- [Architecture](./ARCHITECTURE.md)
- [Safety](./SAFETY.md)
- [Screenshots](./SCREENSHOTS.md)
- [Changelog](../CHANGELOG.md)

## Tuyên bố miễn trừ

VansonCLI được cung cấp cho kiểm thử hợp pháp, gỡ lỗi, học tập và trao đổi kỹ thuật. Chỉ sử dụng với app, device, account và system mà bạn sở hữu hoặc được phép kiểm thử.
