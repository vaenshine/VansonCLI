# VansonCLI

![VansonCLI Logo](../assets/vansoncli-logo-512.png)

**Espace de travail iOS injecté pour le débogage assisté par IA, l'inspection UI, l'analyse réseau, les flux mémoire et les expérimentations de patch dans des environnements autorisés.**

[English](../README.md) | [简体中文](./README_CN.md) | [繁體中文](./README_TW.md) | [العربية](./README_AR.md) | [Deutsch](./README_DE.md) | [Español](./README_ES.md) | **Français** | [日本語](./README_JA.md) | [한국어](./README_KO.md) | [Português](./README_PT.md) | [Русский](./README_RU.md) | [ไทย](./README_TH.md) | [Tiếng Việt](./README_VI.md)

![Platform](https://img.shields.io/badge/Platform-iOS%2014.0%2B-black)
![Build](https://img.shields.io/badge/Build-Theos-blue)
![Package](https://img.shields.io/badge/Package-dylib%20%2B%20deb-purple)
![License](https://img.shields.io/badge/License-MIT-green)

> [![Join Telegram](https://img.shields.io/badge/Join-Telegram%20Channel-blue?logo=telegram&logoWidth=20&labelColor=26A5E4&color=white)](https://t.me/VansonCLI)

---

## Introduction

**VansonCLI** transforme un processus iOS injecté en espace de travail runtime en direct. Il combine chat IA, inspection Objective-C, sélection de vues UIKit, capture réseau, scan mémoire, gestion de patchs, artifacts et diagnostics dans un panneau flottant compact.

## Compatibilité

- **Plateforme cible** : iOS 14.0+, arm64, environnement d'injection compatible MobileSubstrate.
- **Environnement de build** : macOS, Theos et toolchain iOS arm64.
- **Fournisseurs IA** : OpenAI-compatible Chat Completions / Responses, Anthropic, Gemini et fournisseurs compatibles personnalisés.
- **Portée runtime** : dépend de l'app cible, de l'injection, du sandbox, de la version système et des entitlements.

## Navigation

- **AI Chat** : contexte applicatif, tool calls, détails de vérification, références et état provider/model.
- **Inspect** : classes, méthodes, ivars, propriétés, protocoles, chaînes, modules et instances vivantes.
- **Network** : trafic HTTP/HTTPS/WebSocket, paramètres et bodies formatés, replay et export HAR.
- **Artifacts** : captures, logs, diagnostics et sorties d'outils.
- **Patches et Memory** : hooks, patchs de valeurs, règles réseau, scan mémoire et écritures contrôlées.
- **Settings** : providers, mode endpoint, version API, clé API, modèles, tokens et profondeur de raisonnement.

## Captures


### Captures verticales sur appareil

<table>
  <tr>
    <td align="center"><img src="screenshots/IMG_0173.PNG" alt="VansonCLI live phone screenshot 1" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0174.PNG" alt="VansonCLI live phone screenshot 2" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0175.PNG" alt="VansonCLI live phone screenshot 3" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0176.PNG" alt="VansonCLI live phone screenshot 4" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0177.PNG" alt="VansonCLI live phone screenshot 5" width="180"></td>
  </tr>
</table>


## Build et documentation

```bash
./scripts/build_release.sh
```

- [Installation](../INSTALL.md)
- [Architecture](./ARCHITECTURE.md)
- [Safety](./SAFETY.md)
- [Screenshots](./SCREENSHOTS.md)
- [Changelog](../CHANGELOG.md)

## Avertissement

VansonCLI est fourni pour les tests légaux, le débogage, l'apprentissage et l'échange technique. Utilisez-le uniquement sur des apps, appareils, comptes et systèmes que vous possédez ou êtes autorisé à tester.
