# VansonCLI

![VansonCLI Logo](../assets/vansoncli-logo-512.png)

**Workspace iOS injetado para depuração assistida por IA, inspeção de UI, análise de rede, fluxos de memória e experimentos de patch em ambientes autorizados.**

[English](../README.md) | [简体中文](./README_CN.md) | [繁體中文](./README_TW.md) | [العربية](./README_AR.md) | [Deutsch](./README_DE.md) | [Español](./README_ES.md) | [Français](./README_FR.md) | [日本語](./README_JA.md) | [한국어](./README_KO.md) | **Português** | [Русский](./README_RU.md) | [ไทย](./README_TH.md) | [Tiếng Việt](./README_VI.md)

![Platform](https://img.shields.io/badge/Platform-iOS%2014.0%2B-black)
![Build](https://img.shields.io/badge/Build-Theos-blue)
![Package](https://img.shields.io/badge/Package-dylib%20%2B%20deb-purple)
![License](https://img.shields.io/badge/License-MIT-green)

> [![Join Telegram](https://img.shields.io/badge/Join-Telegram%20Channel-blue?logo=telegram&logoWidth=20&labelColor=26A5E4&color=white)](https://t.me/VansonCLI)

---

## Introdução

**VansonCLI** transforma um processo iOS injetado em um workspace runtime ao vivo. Ele combina chat com IA, inspeção do runtime Objective-C, seleção de views UIKit, captura de rede, varredura de memória, gerenciamento de patches, artifacts e diagnósticos em um painel flutuante compacto.

## Compatibilidade

- **Plataforma alvo**: iOS 14.0+, arm64, ambiente de injeção compatível com MobileSubstrate.
- **Ambiente de build**: macOS, Theos e toolchain iOS arm64.
- **Provedores de IA**: OpenAI-compatible Chat Completions / Responses, Anthropic, Gemini e provedores compatíveis personalizados.
- **Escopo runtime**: depende do app alvo, método de injeção, sandbox, versão do sistema e entitlements.

## Navegação

- **AI Chat**: contexto do app, tool calls, verificação, referências e estado provider/model.
- **Inspect**: classes, methods, ivars, properties, protocols, strings, modules e live instances.
- **Network**: tráfego HTTP/HTTPS/WebSocket, params/body formatados, replay e exportação HAR.
- **Artifacts**: screenshots, logs, diagnósticos e saídas de ferramentas.
- **Patches / Memory**: hooks, value patches, network rules, memory scan e controlled writes.
- **Settings**: providers, endpoint mode, API version, API key, models, token limits e reasoning depth.

## Capturas


### Capturas verticais no dispositivo

<table>
  <tr>
    <td align="center"><img src="screenshots/IMG_0173.PNG" alt="VansonCLI live phone screenshot 1" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0174.PNG" alt="VansonCLI live phone screenshot 2" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0175.PNG" alt="VansonCLI live phone screenshot 3" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0176.PNG" alt="VansonCLI live phone screenshot 4" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0177.PNG" alt="VansonCLI live phone screenshot 5" width="180"></td>
  </tr>
</table>


## Build e documentação

```bash
./scripts/build_release.sh
```

- [Installation](../INSTALL.md)
- [Architecture](./ARCHITECTURE.md)
- [Safety](./SAFETY.md)
- [Screenshots](./SCREENSHOTS.md)
- [Changelog](../CHANGELOG.md)

## Aviso

VansonCLI é fornecido para testes legais, depuração, aprendizado e troca técnica. Use apenas em apps, dispositivos, contas e sistemas que você possui ou está autorizado a testar.
