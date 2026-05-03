# VansonCLI

![VansonCLI Logo](../assets/vansoncli-logo-512.png)

**許可されたテスト環境向けの注入型 iOS ランタイムワークスペース。AI 支援デバッグ、UI 検査、ネットワーク解析、メモリ操作、パッチ実験を統合します。**

[English](../README.md) | [简体中文](./README_CN.md) | [繁體中文](./README_TW.md) | [العربية](./README_AR.md) | [Deutsch](./README_DE.md) | [Español](./README_ES.md) | [Français](./README_FR.md) | **日本語** | [한국어](./README_KO.md) | [Português](./README_PT.md) | [Русский](./README_RU.md) | [ไทย](./README_TH.md) | [Tiếng Việt](./README_VI.md)

![Platform](https://img.shields.io/badge/Platform-iOS%2014.0%2B-black)
![Build](https://img.shields.io/badge/Build-Theos-blue)
![Package](https://img.shields.io/badge/Package-dylib%20%2B%20deb-purple)
![License](https://img.shields.io/badge/License-MIT-green)

> [![Join Telegram](https://img.shields.io/badge/Join-Telegram%20Channel-blue?logo=telegram&logoWidth=20&labelColor=26A5E4&color=white)](https://t.me/VansonCLI)

---

## 概要

**VansonCLI** は、注入された iOS プロセスをリアルタイムのランタイムワークスペースに変えます。AI チャット、Objective-C ランタイム探索、UIKit ビュー選択、ネットワークキャプチャ、メモリスキャン、パッチ管理、artifacts、診断をコンパクトなフローティングパネルに統合します。

## 互換性

- **対象プラットフォーム**: iOS 14.0+、arm64、MobileSubstrate 互換の注入環境。
- **ビルド環境**: macOS、Theos、iOS arm64 toolchain。
- **AI providers**: OpenAI-compatible Chat Completions / Responses、Anthropic、Gemini、カスタム互換 provider。
- **実行範囲**: 対象 app、注入方式、sandbox、OS バージョン、entitlements に依存します。

## ナビゲーション

- **AI Chat**: app コンテキスト、tool call、検証詳細、参照、provider/model 状態。
- **Inspect**: Objective-C クラス、メソッド、ivar、プロパティ、プロトコル、文字列、モジュール、生存インスタンス。
- **Network**: HTTP/HTTPS/WebSocket、整形済み params/body、replay、HAR export。
- **Artifacts**: スクリーンショット、ログ、診断、ツール出力。
- **Patches / Memory**: hooks、値パッチ、ネットワークルール、メモリスキャン、制御された書き込み。
- **Settings**: provider、endpoint mode、API version、API key、models、token limit、reasoning depth。

## スクリーンショット


### 実機の縦長スクリーンショット

<table>
  <tr>
    <td align="center"><img src="screenshots/IMG_0173.PNG" alt="VansonCLI live phone screenshot 1" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0174.PNG" alt="VansonCLI live phone screenshot 2" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0175.PNG" alt="VansonCLI live phone screenshot 3" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0176.PNG" alt="VansonCLI live phone screenshot 4" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0177.PNG" alt="VansonCLI live phone screenshot 5" width="180"></td>
  </tr>
</table>


## ビルドとドキュメント

```bash
./scripts/build_release.sh
```

- [Installation](../INSTALL.md)
- [Architecture](./ARCHITECTURE.md)
- [Safety](./SAFETY.md)
- [Screenshots](./SCREENSHOTS.md)
- [Changelog](../CHANGELOG.md)

## 免責事項

VansonCLI は合法的なテスト、デバッグ、学習、技術交流のために提供されています。所有またはテスト許可を得た app、device、account、system でのみ使用してください。
