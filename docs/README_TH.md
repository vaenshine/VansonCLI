# VansonCLI

![VansonCLI Logo](../assets/vansoncli-logo-512.png)

**พื้นที่ทำงาน iOS runtime แบบ injected สำหรับการดีบักด้วย AI, ตรวจ UI, วิเคราะห์เครือข่าย, memory workflows และการทดลอง patch ในสภาพแวดล้อมทดสอบที่ได้รับอนุญาต**

[English](../README.md) | [简体中文](./README_CN.md) | [繁體中文](./README_TW.md) | [العربية](./README_AR.md) | [Deutsch](./README_DE.md) | [Español](./README_ES.md) | [Français](./README_FR.md) | [日本語](./README_JA.md) | [한국어](./README_KO.md) | [Português](./README_PT.md) | [Русский](./README_RU.md) | **ไทย** | [Tiếng Việt](./README_VI.md)

![Platform](https://img.shields.io/badge/Platform-iOS%2014.0%2B-black)
![Build](https://img.shields.io/badge/Build-Theos-blue)
![Package](https://img.shields.io/badge/Package-dylib%20%2B%20deb-purple)
![License](https://img.shields.io/badge/License-MIT-green)

> [![Join Telegram](https://img.shields.io/badge/Join-Telegram%20Channel-blue?logo=telegram&logoWidth=20&labelColor=26A5E4&color=white)](https://t.me/VansonCLI)

---

## บทนำ

**VansonCLI** เปลี่ยน process ของ iOS ที่ถูก inject ให้เป็น runtime workspace แบบสด รวม AI chat, Objective-C runtime inspection, UIKit view picking, network capture, memory scanning, patch management, artifacts และ diagnostics ไว้ใน floating panel ขนาดกะทัดรัด

## ความเข้ากันได้

- **แพลตฟอร์มเป้าหมาย**: iOS 14.0+, arm64, MobileSubstrate-compatible injection environment.
- **สภาพแวดล้อม build**: macOS, Theos และ iOS arm64 toolchain.
- **AI providers**: OpenAI-compatible Chat Completions / Responses, Anthropic, Gemini และ custom compatible providers.
- **Runtime scope**: ขึ้นกับ target app, injection method, sandbox state, system version และ entitlements.

## การนำทาง

- **AI Chat**: app context, tool calls, verification details, references และ provider/model state.
- **Inspect**: Objective-C classes, methods, ivars, properties, protocols, strings, modules และ live instances.
- **Network**: HTTP/HTTPS/WebSocket traffic, formatted params/body, replay และ HAR export.
- **Artifacts**: screenshots, logs, diagnostics และ tool outputs.
- **Patches / Memory**: hooks, value patches, network rules, memory scan และ controlled writes.
- **Settings**: providers, endpoint mode, API version, API key, models, token limits และ reasoning depth.

## ภาพหน้าจอ


### ภาพหน้าจอแนวตั้งจากอุปกรณ์

<table>
  <tr>
    <td align="center"><img src="screenshots/IMG_0173.PNG" alt="VansonCLI live phone screenshot 1" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0174.PNG" alt="VansonCLI live phone screenshot 2" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0175.PNG" alt="VansonCLI live phone screenshot 3" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0176.PNG" alt="VansonCLI live phone screenshot 4" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0177.PNG" alt="VansonCLI live phone screenshot 5" width="180"></td>
  </tr>
</table>


## Build และเอกสาร

```bash
./scripts/build_release.sh
```

- [Installation](../INSTALL.md)
- [Architecture](./ARCHITECTURE.md)
- [Safety](./SAFETY.md)
- [Screenshots](./SCREENSHOTS.md)
- [Changelog](../CHANGELOG.md)

## Disclaimer

VansonCLI จัดทำขึ้นสำหรับการทดสอบที่ถูกกฎหมาย การดีบัก การเรียนรู้ และการแลกเปลี่ยนทางเทคนิค ใช้กับ app, device, account และ system ที่คุณเป็นเจ้าของหรือได้รับอนุญาตให้ทดสอบเท่านั้น
