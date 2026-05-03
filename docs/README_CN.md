# VansonCLI

![VansonCLI Logo](../assets/vansoncli-logo-512.png)

**面向授权测试环境的 iOS 注入式运行时工作台，集成 AI 辅助调试、UI 检查、网络分析、内存工作流与补丁实验能力。**

[English](../README.md) | **简体中文** | [繁體中文](./README_TW.md) | [العربية](./README_AR.md) | [Deutsch](./README_DE.md) | [Español](./README_ES.md) | [Français](./README_FR.md) | [日本語](./README_JA.md) | [한국어](./README_KO.md) | [Português](./README_PT.md) | [Русский](./README_RU.md) | [ไทย](./README_TH.md) | [Tiếng Việt](./README_VI.md)

![Platform](https://img.shields.io/badge/Platform-iOS%2014.0%2B-black)
![Build](https://img.shields.io/badge/Build-Theos-blue)
![Package](https://img.shields.io/badge/Package-dylib%20%2B%20deb-purple)
![License](https://img.shields.io/badge/License-MIT-green)

> [![加入 Telegram 频道](https://img.shields.io/badge/加入-Telegram%20频道-blue?logo=telegram&logoWidth=20&labelColor=26A5E4&color=white)](https://t.me/VansonCLI)

---

## 简介

**VansonCLI** 会把被注入的 iOS 进程变成一个可实时检查、查询、编辑和操作的运行时工作台。它把 AI 对话、Objective-C 运行时探索、UIKit 控件选取、网络捕获、内存扫描、补丁管理、Artifacts 与诊断信息整合进一个紧凑悬浮面板。

项目以 Theos tweak 形式构建，面向研究、调试与技术交流。核心思路是把目标进程暴露成结构化工具，让操作者和 AI 助手共享同一份运行时上下文，包括 UI 层级、网络流量、运行时元数据、内存值、补丁记录和生成产物。

## 兼容性说明

- **目标平台**：iOS 14.0+，arm64，MobileSubstrate 兼容注入环境。
- **构建环境**：macOS、Theos、iOS arm64 目标工具链。
- **运行范围**：实际行为取决于目标 App、注入方式、沙盒状态、系统版本和可用 entitlement。
- **AI 提供商**：OpenAI-compatible Chat Completions 与 Responses 端点、Anthropic、Gemini、自定义兼容提供商。
- **多语言支持**：简体中文、繁體中文、English、العربية、Deutsch、Español、Français、日本語、한국어、Português、Русский、ไทย、Tiếng Việt。

## 页面结构

- **AI 对话**：携带当前 App 上下文对话，执行 tool call，查看验证结果，附加引用，并管理 provider/model 状态。
- **分析**：浏览 Objective-C 类、方法、成员变量、属性、协议、字符串、进程信息、加载模块和活跃实例。
- **网络**：捕获 HTTP/HTTPS/WebSocket 流量，查看格式化 headers/params/body，重放请求，管理收藏、规则、HAR 导出和正则筛选。
- **Artifacts**：查看生成截图、日志、工具输出、诊断结果和已保存的运行时产物。
- **补丁**：管理方法补丁、Hook、数值补丁、网络规则、可重试工具结果和补丁说明。
- **代码与内存**：查看代码相关输出，扫描数值，精炼内存候选，预览值，并执行受控写入流程。
- **设置**：管理 AI 提供商、端点模式、API 版本、API 密钥、角色预设、模型列表、Token 限制、推理深度、语言、构建信息与关于页面。

## 功能亮点

- **AI 辅助运行时操作**：VansonCLI 为助手提供 UIKit 层级、网络流、运行时对象、内存状态、补丁、追踪和 artifacts 的结构化工具访问。
- **模型提供商编辑器**：配置 Base URL、API 版本、端点模式、API Key、角色预设、当前模型、Token 限制、GPT 推理深度、模型获取、测试调用和调用日志。
- **UIKit 检查器**：通过触摸选取控件，查看层级与约束，编辑常见 view 属性，切换 pick 高亮边框，并把所选 UI 上下文发送到对话。
- **网络工作台**：在 tabbed modal 中查看请求信息，行内编辑重放 headers/params/body，格式化参数和载荷，收藏请求流，导出 HAR，并测试正则规则。
- **对话体验**：紧凑气泡、引用卡片、终止控制、可重试工具块、验证详情、上下文用量追踪，以及发送后自动清理引用。
- **内存与补丁工作流**：扫描数值，精炼候选，浏览内存，管理补丁记录，安装 Hook，并围绕高风险运行时变更保留可回滚说明。
- **面板体验**：紧凑横屏壳层、悬浮入口、品牌图标、多语言 UI，以及适配手机屏幕的高密度控件。

## 应用截图


### 真机竖屏截图

<table>
  <tr>
    <td align="center"><img src="screenshots/IMG_0173.PNG" alt="VansonCLI live phone screenshot 1" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0174.PNG" alt="VansonCLI live phone screenshot 2" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0175.PNG" alt="VansonCLI live phone screenshot 3" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0176.PNG" alt="VansonCLI live phone screenshot 4" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0177.PNG" alt="VansonCLI live phone screenshot 5" width="180"></td>
  </tr>
</table>


## 安装

请查看 [INSTALL.md](../INSTALL.md)，其中包含环境准备、打包、安装流程和常见问题。

## 构建

环境要求：

- macOS，并安装 Xcode Command Line Tools（`xcode-select --install`）
- Theos，并配置 `THEOS` 环境变量
- Theos 可用的 iOS SDK
- arm64 iOS 目标工具链
- `clang`、`make`、`ldid`、`dpkg-deb`
- MobileSubstrate / Substitute / ElleKit 兼容的授权测试设备

当前 Makefile 目标：

- `TARGET := iphone:clang:latest:14.0`
- `ARCHS = arm64`

构建 release 包：

```bash
./scripts/build_release.sh
```

输出产物：

- `release/VansonCLI_1.0.dylib`
- `packages/com.vanson.cli_1.0_iphoneos-arm.deb`

## 项目文档

- [安装说明](../INSTALL.md)：构建环境、打包流程、安装流程与常见问题。
- [架构说明](./ARCHITECTURE.md)：模块地图、AI tool-call 流程、网络流程、UI inspector 流程和安全模式。
- [安全说明](./SAFETY.md)：授权使用边界、敏感数据处理、AI provider key 建议和补丁风险控制。
- [截图说明](./SCREENSHOTS.md)：公开截图与当前 UI 模块的对应关系。
- [更新日志](../CHANGELOG.md)：版本记录和能力变更。

## 项目结构

- `src/AI`：AI adapter、对话引擎、模型设置、Prompt 管理、Token 追踪和工具执行。
- `src/UI`：UIKit 面板、Tab、对话 UI、网络 UI、分析 UI、设置和关于页面。
- `src/Runtime`：运行时扫描和值读取。
- `src/Network`：请求捕获、URLProtocol Hook、WebSocket Hook 和网络记录。
- `src/Patches`：补丁、数值、Hook 和网络规则模型。
- `src/Memory`：内存扫描、浏览和定位引擎。
- `assets`：项目 Logo 与公开视觉资源。
- `UiOptimized`：README 与 Release 页面使用的公开截图。
- `scripts`：release 构建辅助脚本。

## 更新日志

请前往 [Releases](https://github.com/vaenshine/VansonCLI/releases) 查看。

## 致谢

- 开发者：**Vaenshine**
- 项目链接：[GitHub](https://github.com/vaenshine/VansonCLI) / [Telegram](https://t.me/VansonCLI)
- 开源协议：**MIT License**

## 免责声明

VansonCLI 仅用于合法测试、调试、学习和技术交流。请仅在你拥有或已获授权测试的 App、设备、账号和系统上使用。

使用者需自行遵守当地法律、平台规则、App 条款和第三方服务条款。使用本工具执行的所有操作均由使用者独立作出。目标 App 崩溃、数据损坏或丢失、账号限制、设备异常、服务违规以及由此产生的直接或间接损失，均由使用者自行承担。

VansonCLI 是通用技术调试工作台，不包含预设目标、定制操作方案或针对特定 App 的专属适配。

## 重要声明

本项目基于 **MIT License** 开源，用于研究、调试、学习和社区交流。

## Star 趋势

[![Star History Chart](https://api.star-history.com/svg?repos=vaenshine/VansonCLI&type=Date)](https://star-history.com/#vaenshine/VansonCLI&Date)
