# VansonCLI

![VansonCLI Logo](../assets/vansoncli-logo-512.png)

**Entorno de trabajo iOS inyectado para depuración asistida por IA, inspección de UI, análisis de red, flujos de memoria y experimentos de parches en entornos autorizados.**

[English](../README.md) | [简体中文](./README_CN.md) | [繁體中文](./README_TW.md) | [العربية](./README_AR.md) | [Deutsch](./README_DE.md) | **Español** | [Français](./README_FR.md) | [日本語](./README_JA.md) | [한국어](./README_KO.md) | [Português](./README_PT.md) | [Русский](./README_RU.md) | [ไทย](./README_TH.md) | [Tiếng Việt](./README_VI.md)

![Platform](https://img.shields.io/badge/Platform-iOS%2014.0%2B-black)
![Build](https://img.shields.io/badge/Build-Theos-blue)
![Package](https://img.shields.io/badge/Package-dylib%20%2B%20deb-purple)
![License](https://img.shields.io/badge/License-MIT-green)

> [![Join Telegram](https://img.shields.io/badge/Join-Telegram%20Channel-blue?logo=telegram&logoWidth=20&labelColor=26A5E4&color=white)](https://t.me/VansonCLI)

---

## Introducción

**VansonCLI** convierte un proceso iOS inyectado en un espacio de trabajo de ejecución en vivo. Combina chat con IA, inspección del runtime Objective-C, selección de vistas UIKit, captura de red, escaneo de memoria, gestión de parches, artifacts y diagnósticos en un panel flotante compacto.

## Compatibilidad

- **Plataforma objetivo**: iOS 14.0+, arm64, entorno de inyección compatible con MobileSubstrate.
- **Entorno de compilación**: macOS, Theos y toolchain iOS arm64.
- **Proveedores de IA**: OpenAI-compatible Chat Completions / Responses, Anthropic, Gemini y proveedores compatibles personalizados.
- **Alcance de ejecución**: depende de la app objetivo, método de inyección, sandbox, versión del sistema y entitlements.

## Navegación

- **AI Chat**: conversación con contexto de la app, tool calls, verificación, referencias y estado provider/model.
- **Inspect**: clases, métodos, ivars, propiedades, protocolos, cadenas, módulos e instancias vivas.
- **Network**: tráfico HTTP/HTTPS/WebSocket, parámetros y cuerpos formateados, replay y exportación HAR.
- **Artifacts**: capturas, logs, diagnósticos y salidas de herramientas.
- **Patches y Memory**: hooks, parches de valores, reglas de red, escaneo de memoria y escrituras controladas.
- **Settings**: providers, modo de endpoint, API version, API key, modelos, tokens y razonamiento.

## Capturas


### Capturas verticales en dispositivo

<table>
  <tr>
    <td align="center"><img src="screenshots/IMG_0173.PNG" alt="VansonCLI live phone screenshot 1" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0174.PNG" alt="VansonCLI live phone screenshot 2" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0175.PNG" alt="VansonCLI live phone screenshot 3" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0176.PNG" alt="VansonCLI live phone screenshot 4" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0177.PNG" alt="VansonCLI live phone screenshot 5" width="180"></td>
  </tr>
</table>


## Compilación y documentación

```bash
./scripts/build_release.sh
```

- [Instalación](../INSTALL.md)
- [Arquitectura](./ARCHITECTURE.md)
- [Seguridad](./SAFETY.md)
- [Capturas](./SCREENSHOTS.md)
- [Cambios](../CHANGELOG.md)

## Aviso legal

VansonCLI se proporciona para pruebas legales, depuración, aprendizaje e intercambio técnico. Úsalo únicamente en apps, dispositivos, cuentas y sistemas propios o autorizados.
