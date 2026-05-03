# VansonCLI

![VansonCLI Logo](../assets/vansoncli-logo-512.png)

**مساحة عمل iOS محقونة لتصحيح الأخطاء بمساعدة الذكاء الاصطناعي، وفحص الواجهة، وتحليل الشبكة، وتدفقات الذاكرة، وتجارب التصحيح في بيئات اختبار مصرح بها.**

[English](../README.md) | [简体中文](./README_CN.md) | [繁體中文](./README_TW.md) | **العربية** | [Deutsch](./README_DE.md) | [Español](./README_ES.md) | [Français](./README_FR.md) | [日本語](./README_JA.md) | [한국어](./README_KO.md) | [Português](./README_PT.md) | [Русский](./README_RU.md) | [ไทย](./README_TH.md) | [Tiếng Việt](./README_VI.md)

![Platform](https://img.shields.io/badge/Platform-iOS%2014.0%2B-black)
![Build](https://img.shields.io/badge/Build-Theos-blue)
![Package](https://img.shields.io/badge/Package-dylib%20%2B%20deb-purple)
![License](https://img.shields.io/badge/License-MIT-green)

> [![Join Telegram](https://img.shields.io/badge/Join-Telegram%20Channel-blue?logo=telegram&logoWidth=20&labelColor=26A5E4&color=white)](https://t.me/VansonCLI)

---

## المقدمة

**VansonCLI** يحول عملية iOS محقونة إلى مساحة عمل runtime مباشرة. يجمع بين محادثة الذكاء الاصطناعي، وفحص Objective-C runtime، واختيار عناصر UIKit، والتقاط الشبكة، ومسح الذاكرة، وإدارة التصحيحات، وartifacts، والتشخيصات في لوحة عائمة مدمجة.

## التوافق

- **النظام المستهدف**: iOS 14.0+، arm64، وبيئة حقن متوافقة مع MobileSubstrate.
- **بيئة البناء**: macOS، Theos، وسلسلة أدوات iOS arm64.
- **مزودو الذكاء الاصطناعي**: OpenAI-compatible Chat Completions / Responses، Anthropic، Gemini، ومزودون متوافقون مخصصون.
- **نطاق التشغيل**: يعتمد على التطبيق المستهدف، وطريقة الحقن، وحالة sandbox، وإصدار النظام، وentitlements.

## التنقل

- **AI Chat**: محادثة مع سياق التطبيق، tool calls، تفاصيل التحقق، المراجع، وحالة provider/model.
- **Inspect**: classes، methods، ivars، properties، protocols، strings، modules، وlive instances.
- **Network**: حركة HTTP/HTTPS/WebSocket، params/body منسقة، replay، وتصدير HAR.
- **Artifacts**: screenshots، logs، diagnostics، ومخرجات الأدوات.
- **Patches / Memory**: hooks، value patches، network rules، memory scan، وcontrolled writes.
- **Settings**: providers، endpoint mode، API version، API key، models، token limits، وreasoning depth.

## لقطات الشاشة


### لقطات شاشة عمودية من الجهاز

<table>
  <tr>
    <td align="center"><img src="screenshots/IMG_0173.PNG" alt="VansonCLI live phone screenshot 1" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0174.PNG" alt="VansonCLI live phone screenshot 2" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0175.PNG" alt="VansonCLI live phone screenshot 3" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0176.PNG" alt="VansonCLI live phone screenshot 4" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0177.PNG" alt="VansonCLI live phone screenshot 5" width="180"></td>
  </tr>
</table>


## البناء والوثائق

```bash
./scripts/build_release.sh
```

- [Installation](../INSTALL.md)
- [Architecture](./ARCHITECTURE.md)
- [Safety](./SAFETY.md)
- [Screenshots](./SCREENSHOTS.md)
- [Changelog](../CHANGELOG.md)

## إخلاء المسؤولية

VansonCLI مخصص للاختبار القانوني، وتصحيح الأخطاء، والتعلم، والتبادل التقني. استخدمه فقط على التطبيقات والأجهزة والحسابات والأنظمة التي تملكها أو لديك إذن باختبارها.
