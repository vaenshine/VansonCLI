# Screenshots

The public screenshot set lives in `UiOptimized/` and `docs/screenshots/`. These images are used by the README files and release pages.

They are aligned with current UI modules:

| File | UI area | Main source modules |
| --- | --- | --- |
| `UiOptimized/AIChat.png` | AI Chat workspace | `src/UI/Chat`, `src/AI/Chat`, `src/AI/ToolCall` |
| `UiOptimized/Network.png` | Network workspace | `src/UI/Network`, `src/Network` |
| `UiOptimized/Inspect.png` | Runtime and UI inspection | `src/UI/Inspect`, `src/UI/UIInspector`, `src/UIInspector`, `src/Runtime` |
| `UiOptimized/Memory.png` | Memory workspace | `src/UI/Memory`, `src/Memory` |
| `UiOptimized/Workspace.png` | Workspace hub | `src/UI/Panel/VCWorkspaceHubTab.mm` |
| `UiOptimized/Code.png` | Code workspace | `src/UI/Code` |
| `UiOptimized/Settings.png` | Provider and settings editor | `src/UI/Settings`, `src/AI/Models` |

## On-device Vertical Screenshots

These phone screenshots show VansonCLI running on a real portrait device viewport:

<table>
  <tr>
    <td align="center"><img src="screenshots/IMG_0173.PNG" alt="VansonCLI live phone screenshot 1" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0174.PNG" alt="VansonCLI live phone screenshot 2" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0175.PNG" alt="VansonCLI live phone screenshot 3" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0176.PNG" alt="VansonCLI live phone screenshot 4" width="180"></td>
    <td align="center"><img src="screenshots/IMG_0177.PNG" alt="VansonCLI live phone screenshot 5" width="180"></td>
  </tr>
</table>

## Screenshot Rules

- Screenshots should reflect implemented UI controls and current workflows.
- Screenshots should avoid real API keys, private hosts, account identifiers, and personal data.
- Screenshots should use authorized test apps and test traffic.
- Generated marketing images can be used for social previews, while README workflow screenshots should remain close to the implemented UI.
