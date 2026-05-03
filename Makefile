TARGET := iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VansonCLI

VC_VERSION = $(shell grep -i "Version:" control | awk '{print $$2}')

VansonCLI_FILES = \
	Tweak.xm \
	src/Core/VCConfig.mm \
	src/Core/VCCapabilityManager.mm \
	src/Core/VCLanguage.mm \
	src/Core/Lang/VCLang_EN.mm \
	src/Core/Lang/VCLang_ZH.mm \
	src/Core/Lang/VCLang_ZH_HANT.mm \
	src/Core/Lang/VCLang_JA.mm \
	src/Core/Lang/VCLang_KO.mm \
	src/Core/Lang/VCLang_RU.mm \
	src/Core/Lang/VCLang_ES.mm \
	src/Core/Lang/VCLang_VI.mm \
	src/Core/Lang/VCLang_TH.mm \
	src/Core/Lang/VCLang_PT.mm \
	src/Core/Lang/VCLang_FR.mm \
	src/Core/Lang/VCLang_DE.mm \
	src/Core/Lang/VCLang_AR.mm \
	src/Core/VCSafeMode.mm \
	src/Core/VCCrypto.mm \
	src/Vendor/MemoryBackend/Core/VCMemoryCore.cpp \
	src/Vendor/MemoryBackend/Core/VCMemCore.cpp \
	src/Vendor/MemoryBackend/Engine/VCMemEngine.mm \
	src/Runtime/VCRuntimeModels.mm \
	src/Runtime/VCRuntimeEngine.mm \
	src/Runtime/VCStringScanner.mm \
	src/Runtime/VCInstanceScanner.mm \
	src/Runtime/VCValueReader.mm \
	src/Memory/VCMemoryBrowserEngine.mm \
	src/Memory/VCMemoryScanEngine.mm \
	src/Memory/VCMemoryLocatorEngine.mm \
	src/Process/VCProcessInfo.mm \
	src/Unity/VCUnityRuntimeEngine.mm \
	src/Trace/VCTraceManager.mm \
	src/UIInspector/VCUIInspector.mm \
	src/UIInspector/VCTouchOverlay.mm \
	src/Network/VCNetRecord.mm \
	src/Network/VCWebSocketMonitor.mm \
	src/Network/VCURLProtocol.mm \
	src/Network/VCNetMonitor.mm \
	src/AI/Models/VCProviderConfig.mm \
	src/AI/Models/VCProviderManager.mm \
	src/AI/Memory/VCMemoryManager.mm \
	src/AI/Security/VCPromptLeakGuard.mm \
	src/AI/Adapters/VCOpenAIAdapter.mm \
	src/AI/Adapters/VCAnthropicAdapter.mm \
		src/AI/Adapters/VCGeminiAdapter.mm \
		src/AI/Chat/VCMessage.mm \
		src/AI/Chat/VCChatDiagnostics.mm \
		src/AI/Chat/VCChatSession.mm \
		src/AI/Chat/VCAIEngine.mm \
		src/AI/Chat/VCAutoSave.mm \
	src/AI/TokenManager/VCTokenTracker.mm \
	src/AI/TokenManager/VCContextCompactor.mm \
	src/AI/ToolCall/VCToolCallParser.mm \
	src/AI/ToolCall/VCToolSchemaRegistry.mm \
	src/AI/ToolCall/VCAIReadOnlyToolExecutor.mm \
	src/AI/Verification/VCVerificationGate.mm \
	src/AI/Context/VCContextCollector.mm \
	src/AI/Prompts/VCPromptManager.mm \
	src/Console/VCConsole.mm \
	src/Console/VCAliasManager.mm \
	src/Console/VCCommandRouter.mm \
	src/Patches/VCPatchItem.mm \
	src/Patches/VCValueItem.mm \
	src/Patches/VCHookItem.mm \
	src/Patches/VCNetRule.mm \
	src/Patches/VCPatchManager.mm \
	src/Hook/VCHookManager.mm \
	src/UI/Patches/VCPatchCell.mm \
	src/UI/Patches/VCPatchesTab.mm \
	src/UI/Base/VCOverlayRootViewController.mm \
	src/UI/Base/VCOverlayWindow.mm \
	src/UI/Base/VCOverlayCanvasManager.mm \
	src/UI/Base/VCOverlayTrackingManager.mm \
	src/UI/Base/VCBrandIcon.mm \
	src/UI/Base/VCFloatingButton.mm \
	src/UI/Panel/VCTabBar.mm \
	src/UI/Panel/VCPanel.mm \
	src/UI/Panel/VCWorkspaceHubTab.mm \
	src/UI/Inspect/VCInspectTab.mm \
	src/UI/Network/VCNetworkTab.mm \
	src/UI/UIInspector/VCUIInspectorTab.mm \
	src/UI/Console/VCConsoleTab.mm \
	src/UI/Chat/VCChatTab.mm \
	src/UI/Chat/VCChatBubble.mm \
	src/UI/Chat/VCChatMessageBlockView.mm \
	src/UI/Chat/VCChatMarkdownView.mm \
	src/UI/Chat/VCChatReferenceCardView.mm \
	src/UI/Chat/VCChatStatusBannerView.mm \
	src/UI/Chat/VCMermaidPreviewView.mm \
	src/UI/Chat/VCToolCallBlock.mm \
	src/UI/Chat/VCModelSelector.mm \
	src/UI/Code/VCCodeTab.mm \
	src/UI/Memory/VCMemoryBrowserTab.mm \
	src/UI/Artifacts/VCArtifactsTab.mm \
	src/UI/Settings/VCSettingsTab.mm \
	src/UI/About/VCAboutTab.mm

VansonCLI_FRAMEWORKS = UIKit Foundation Security QuartzCore
VansonCLI_CFLAGS = -fobjc-arc -I. -DVC_VERSION_STR=\"$(VC_VERSION)\"
VansonCLI_CCFLAGS = -fvisibility=hidden -fvisibility-inlines-hidden -std=c++17 -fblocks -I.

include $(THEOS_MAKE_PATH)/tweak.mk

after-all::
	@mkdir -p release
	@cp $(THEOS_OBJ_DIR)/VansonCLI.dylib release/VansonCLI_$(VC_VERSION).dylib
	@echo "==> Release: release/VansonCLI_$(VC_VERSION).dylib"
