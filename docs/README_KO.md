# VansonCLI

![VansonCLI Logo](../assets/vansoncli-logo-512.png)

**승인된 테스트 환경을 위한 주입형 iOS 런타임 워크스페이스. AI 지원 디버깅, UI 검사, 네트워크 분석, 메모리 워크플로, 패치 실험을 통합합니다.**

[English](../README.md) | [简体中文](./README_CN.md) | [繁體中文](./README_TW.md) | [العربية](./README_AR.md) | [Deutsch](./README_DE.md) | [Español](./README_ES.md) | [Français](./README_FR.md) | [日本語](./README_JA.md) | **한국어** | [Português](./README_PT.md) | [Русский](./README_RU.md) | [ไทย](./README_TH.md) | [Tiếng Việt](./README_VI.md)

![Platform](https://img.shields.io/badge/Platform-iOS%2014.0%2B-black)
![Build](https://img.shields.io/badge/Build-Theos-blue)
![Package](https://img.shields.io/badge/Package-dylib%20%2B%20deb-purple)
![License](https://img.shields.io/badge/License-MIT-green)

> [![Join Telegram](https://img.shields.io/badge/Join-Telegram%20Channel-blue?logo=telegram&logoWidth=20&labelColor=26A5E4&color=white)](https://t.me/VansonCLI)

---

## 소개

**VansonCLI**는 주입된 iOS 프로세스를 실시간 런타임 워크스페이스로 바꿉니다. AI 채팅, Objective-C 런타임 탐색, UIKit 뷰 선택, 네트워크 캡처, 메모리 스캔, 패치 관리, artifacts, 진단을 하나의 컴팩트한 플로팅 패널에 통합합니다.

## 호환성

- **대상 플랫폼**: iOS 14.0+, arm64, MobileSubstrate 호환 주입 환경.
- **빌드 환경**: macOS, Theos, iOS arm64 toolchain.
- **AI providers**: OpenAI-compatible Chat Completions / Responses, Anthropic, Gemini, custom compatible providers.
- **런타임 범위**: 대상 app, 주입 방식, sandbox, 시스템 버전, entitlements에 따라 달라집니다.

## 내비게이션

- **AI Chat**: 현재 app 컨텍스트, tool call, 검증 세부 정보, references, provider/model 상태.
- **Inspect**: Objective-C classes, methods, ivars, properties, protocols, strings, modules, live instances.
- **Network**: HTTP/HTTPS/WebSocket 트래픽, formatted params/body, replay, HAR export.
- **Artifacts**: screenshots, logs, diagnostics, tool outputs.
- **Patches / Memory**: hooks, value patches, network rules, memory scan, controlled writes.
- **Settings**: providers, endpoint mode, API version, API key, models, token limits, reasoning depth.

## 스크린샷


### 기기 세로 스크린샷

<table>
  <tr>
    <td align="center"><img src="screenshots/IMG_0173.PNG" alt="VansonCLI live phone screenshot 1" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0174.PNG" alt="VansonCLI live phone screenshot 2" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0175.PNG" alt="VansonCLI live phone screenshot 3" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0176.PNG" alt="VansonCLI live phone screenshot 4" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0177.PNG" alt="VansonCLI live phone screenshot 5" width="180"></td>
  </tr>
</table>


## 빌드와 문서

```bash
./scripts/build_release.sh
```

- [Installation](../INSTALL.md)
- [Architecture](./ARCHITECTURE.md)
- [Safety](./SAFETY.md)
- [Screenshots](./SCREENSHOTS.md)
- [Changelog](../CHANGELOG.md)

## 면책 조항

VansonCLI는 합법적인 테스트, 디버깅, 학습, 기술 교류를 위해 제공됩니다. 소유하거나 테스트 권한이 있는 app, device, account, system에서만 사용하세요.
