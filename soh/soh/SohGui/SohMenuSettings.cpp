#include "SohMenu.h"
#include "soh/Notification/Notification.h"
#include "soh/Enhancements/enhancementTypes.h"
#include "SohModals.h"
#include "soh/OTRGlobals.h"
#include <soh/GameVersions.h>
#include "soh/ResourceManagerHelpers.h"
#include "UIWidgets.hpp"
#include "soh/Enhancements/controls/SohInputEditorWindow.h"
#include <ship/controller/controldeck/ControlDeck.h>
#include <ship/Context.h>
#include <algorithm>
#ifdef __ANDROID__
#include <jni.h>
#include <SDL2/SDL.h>
#include "soh/Enhancements/controls/TouchHudBindings.h"
#endif
#if defined(__IOS__)
#include "ios/SOHiCloudSync.h"
#endif
#if defined(__IOS__) && !defined(__TVOS__)
#include "ios/SOHiOSTouchControls.h"
#endif
#ifdef __TVOS__
#include "ios/SOHTVOSFileServer.h"
#endif

extern "C" {
#include "include/z64audio.h"
#include "variables.h"
}

namespace SohGui {

extern std::shared_ptr<SohMenu> mSohMenu;
extern std::shared_ptr<SohModalWindow> mModalWindow;
using namespace UIWidgets;

static std::map<int32_t, const char*> imguiScaleOptions = {
    { 0, "Small" },
    { 1, "Normal" },
    { 2, "Large" },
    { 3, "X-Large" },
};

static const std::map<int32_t, const char*> menuThemeOptions = {
    { UIWidgets::Colors::Red, "Red" },
    { UIWidgets::Colors::DarkRed, "Dark Red" },
    { UIWidgets::Colors::Orange, "Orange" },
    { UIWidgets::Colors::Green, "Green" },
    { UIWidgets::Colors::DarkGreen, "Dark Green" },
    { UIWidgets::Colors::LightBlue, "Light Blue" },
    { UIWidgets::Colors::Blue, "Blue" },
    { UIWidgets::Colors::DarkBlue, "Dark Blue" },
    { UIWidgets::Colors::Indigo, "Indigo" },
    { UIWidgets::Colors::Violet, "Violet" },
    { UIWidgets::Colors::Purple, "Purple" },
    { UIWidgets::Colors::Brown, "Brown" },
    { UIWidgets::Colors::Gray, "Gray" },
    { UIWidgets::Colors::DarkGray, "Dark Gray" },
};

static const std::map<int32_t, const char*> textureFilteringMap = {
    { Fast::FILTER_THREE_POINT, "Three-Point" },
    { Fast::FILTER_LINEAR, "Linear" },
    { Fast::FILTER_NONE, "None" },
};

static const std::map<int32_t, const char*> notificationPosition = {
    { 0, "Top Left" }, { 1, "Top Right" }, { 2, "Bottom Left" }, { 3, "Bottom Right" }, { 4, "Hidden" },
};

static const std::map<int32_t, const char*> bootSequenceLabels = {
    { BOOTSEQUENCE_DEFAULT, "Default" },        { BOOTSEQUENCE_AUTHENTIC, "Authentic" },
    { BOOTSEQUENCE_FILESELECT, "File Select" }, { BOOTSEQUENCE_DEBUGWARPSCREEN, "Debug Warp Screen" },
    { BOOTSEQUENCE_WARPPOINT, "Warp Point" },
};

#if defined(__ANDROID__) || (defined(__IOS__) && !defined(__TVOS__))
static const std::map<int32_t, const char*> touchFaceButtonLayoutMap = {
    { 0, "ABXY (Nintendo)" },
    { 1, "BAYX (Xbox)" },
    { 2, "GC Layout" },
};
#endif

#ifdef __ANDROID__
static const std::map<int32_t, const char*> touchStyleMap = {
    { 0, "Classic" }, { 1, "N64" }, { 2, "GameCube" }, { 3, "Modern" },
};

static const std::map<int32_t, const char*> touchActionMap = {
    {TouchHud::Disabled, "Disabled"}, {TouchHud::ActionA, "Action / A"},
    {TouchHud::SwordB, "Sword / B"}, {TouchHud::Target, "Target / N64 Z"},
    {TouchHud::Shield, "Shield / R"}, {TouchHud::Navi, "Navi"},
    {TouchHud::ItemLeft, "Left item / C-left"}, {TouchHud::ItemDown, "Down item / C-down"},
    {TouchHud::ItemRight, "Right item / C-right"}, {TouchHud::ExtraL, "Extra / N64 L"},
    {TouchHud::FirstPerson, "First-person / C-up"}, {TouchHud::Pause, "Pause / Start"},
    {TouchHud::DpadUp, "Extra Item 1 / D-pad Up"}, {TouchHud::DpadDown, "Extra Item 2 / D-pad Down"},
    {TouchHud::DpadLeft, "Extra Item 3 / D-pad Left"}, {TouchHud::DpadRight, "Extra Item 4 / D-pad Right"},
    {TouchHud::ToggleMap, "Toggle minimap"},
    {TouchHud::Modifier1, "Modifier 1 / M1"},
    {TouchHud::Modifier2, "Modifier 2 / M2 (reset by default)"},
};
static const std::map<int32_t, const char*> touchNaviLocationMap = {
    {0, "Fairy button (default)"}, {1, "D-pad Up"}, {2, "Z"}, {3, "Custom assignment"}
};
static std::array<std::array<int, TouchHud::BindingCount>, 4> touchBindingSnapshot;

static void SetAndroidIntegratedTouch() {
    if (CVarGetInteger(CVAR_ENHANCEMENT("ManualJump"), 0) && !CVarGetInteger(CVAR_SETTING("DisableChanges"), 0)) {
        for (int style=1; style<=3; ++style) {
            int jumpIndex = TouchHud::JumpIndex(style, CVarGetInteger(TouchHud::JumpCvar(style), 0));
            if (jumpIndex >= 0 && CVarGetInteger(TouchHud::BindingCvar(style, jumpIndex), TouchHud::DefaultAction(style,jumpIndex)) == TouchHud::Navi) {
                int fairyIndex = style == 2 ? 14 : 5;
                int displaced = CVarGetInteger(TouchHud::BindingCvar(style,fairyIndex), TouchHud::DefaultAction(style,fairyIndex));
                CVarSetInteger(TouchHud::BindingCvar(style,jumpIndex), displaced);
                CVarSetInteger(TouchHud::BindingCvar(style,fairyIndex), TouchHud::Navi);
            }
        }
    }
    for (int style=1; style<=3; ++style) for (int i=0; i<TouchHud::BindingCount; ++i)
        touchBindingSnapshot[style][i] = CVarGetInteger(TouchHud::BindingCvar(style, i), TouchHud::DefaultAction(style, i));
    int naviLocation = 3;
    if (touchBindingSnapshot[2][14] == TouchHud::Navi) naviLocation = 0;
    else if (touchBindingSnapshot[2][9] == TouchHud::Navi) naviLocation = 1;
    else if (touchBindingSnapshot[2][3] == TouchHud::Navi) naviLocation = 2;
    CVarSetInteger(CVAR_SETTING("TouchControls.GameCubeNaviLocation"), naviLocation);
    auto* env = static_cast<JNIEnv*>(SDL_AndroidGetJNIEnv());
    jobject activity = static_cast<jobject>(SDL_AndroidGetActivity());
    if (!env || !activity) return;
    jclass type = env->GetObjectClass(activity);
    jmethodID method = env->GetMethodID(type, "setIntegratedTouchFromNative", "(IFFZZ)V");
    if (method) env->CallVoidMethod(activity, method,
        std::clamp(CVarGetInteger(CVAR_SETTING("TouchControls.Style"), 0), 0, 3),
        CVarGetFloat(CVAR_SETTING("TouchControls.Scale"), 1),
        CVarGetFloat(CVAR_SETTING("TouchControls.Opacity"), .55f),
        static_cast<jboolean>(CVarGetInteger(CVAR_SETTING("TouchControls.TransparentSticks"), 0) != 0),
        static_cast<jboolean>(CVarGetInteger(CVAR_SETTING("TouchControls.FloatingRightStick"), 1) != 0));
    if (env->ExceptionCheck()) env->ExceptionClear();
    env->DeleteLocalRef(type); env->DeleteLocalRef(activity);
}

static void EditAndroidIntegratedTouch() {
    auto* env = static_cast<JNIEnv*>(SDL_AndroidGetJNIEnv());
    jobject activity = static_cast<jobject>(SDL_AndroidGetActivity());
    if (!env || !activity) return;
    jclass type = env->GetObjectClass(activity);
    jmethodID method = env->GetMethodID(type, "editIntegratedTouchFromNative", "()V");
    if (method) env->CallVoidMethod(activity, method);
    if (env->ExceptionCheck()) env->ExceptionClear();
    env->DeleteLocalRef(type); env->DeleteLocalRef(activity);
}
static void SetAndroidTouchControlsDisabled(bool disabled) {
    JNIEnv* env = (JNIEnv*)SDL_AndroidGetJNIEnv();
    jobject activity = (jobject)SDL_AndroidGetActivity();
    if (env == nullptr || activity == nullptr) {
        return;
    }

    jclass activityClass = env->GetObjectClass(activity);
    if (activityClass == nullptr) {
        env->DeleteLocalRef(activity);
        return;
    }

    jmethodID method = env->GetMethodID(activityClass, "setTouchControlsDisabledFromNative", "(Z)V");
    if (method != nullptr) {
        env->CallVoidMethod(activity, method, disabled ? JNI_TRUE : JNI_FALSE);
    }

    env->DeleteLocalRef(activityClass);
    env->DeleteLocalRef(activity);
}

static void SetAndroidTouchFaceButtonLayout(int32_t layout) {
    JNIEnv* env = (JNIEnv*)SDL_AndroidGetJNIEnv();
    jobject activity = (jobject)SDL_AndroidGetActivity();
    if (env == nullptr || activity == nullptr) {
        return;
    }

    jclass activityClass = env->GetObjectClass(activity);
    if (activityClass != nullptr) {
        jmethodID method =
            env->GetMethodID(activityClass, "setTouchFaceButtonLayoutFromNative", "(I)V");
        if (method != nullptr) {
            env->CallVoidMethod(activity, method, static_cast<jint>(layout));
        }
        env->DeleteLocalRef(activityClass);
    }
    env->DeleteLocalRef(activity);
}

static void SetAndroidTouchLeftStickFloating(bool floating) {
    JNIEnv* env = (JNIEnv*)SDL_AndroidGetJNIEnv();
    jobject activity = (jobject)SDL_AndroidGetActivity();
    if (env == nullptr || activity == nullptr) {
        return;
    }

    jclass activityClass = env->GetObjectClass(activity);
    if (activityClass != nullptr) {
        jmethodID method = env->GetMethodID(activityClass, "setTouchLeftStickFloatingFromNative", "(Z)V");
        if (method != nullptr) {
            env->CallVoidMethod(activity, method, floating ? JNI_TRUE : JNI_FALSE);
        }
        env->DeleteLocalRef(activityClass);
    }
    env->DeleteLocalRef(activity);
}

static void OpenAndroidDataFolderChooser() {
    JNIEnv* env = (JNIEnv*)SDL_AndroidGetJNIEnv();
    jobject activity = (jobject)SDL_AndroidGetActivity();
    if (env == nullptr || activity == nullptr) {
        return;
    }

    jclass activityClass = env->GetObjectClass(activity);
    if (activityClass == nullptr) {
        env->DeleteLocalRef(activity);
        return;
    }

    jmethodID method = env->GetMethodID(activityClass, "changeDataFolderFromNative", "()V");
    if (method != nullptr) {
        env->CallVoidMethod(activity, method);
    }

    env->DeleteLocalRef(activityClass);
    env->DeleteLocalRef(activity);
}
#endif

const char* GetGameVersionString(uint32_t index) {
    uint32_t gameVersion = ResourceMgr_GetGameVersion(index);
    switch (gameVersion) {
        case OOT_NTSC_US_10:
            return "NTSC 1.0";
        case OOT_NTSC_US_11:
            return "NTSC 1.1";
        case OOT_NTSC_US_12:
            return "NTSC 1.2";
        case OOT_NTSC_US_GC:
            return "NTSC-U GC";
        case OOT_NTSC_JP_GC:
            return "NTSC-J GC";
        case OOT_NTSC_JP_GC_CE:
            return "NTSC-J GC (Collector's Edition)";
        case OOT_NTSC_US_MQ:
            return "NTSC-U MQ";
        case OOT_NTSC_JP_MQ:
            return "NTSC-J MQ";
        case OOT_PAL_10:
            return "PAL 1.0";
        case OOT_PAL_11:
            return "PAL 1.1";
        case OOT_PAL_GC:
            return "PAL GC";
        case OOT_PAL_MQ:
            return "PAL MQ";
        case OOT_PAL_GC_DBG1:
        case OOT_PAL_GC_DBG2:
            return "PAL GC-D";
        case OOT_PAL_GC_MQ_DBG:
            return "PAL MQ-D";
        case OOT_IQUE_CN:
            return "IQUE CN";
        case OOT_IQUE_TW:
            return "IQUE TW";
        default:
            return "UNKNOWN";
    }
}

#include "message_data_static.h"
extern "C" MessageTableEntry* sNesMessageEntryTablePtr;
extern "C" MessageTableEntry* sGerMessageEntryTablePtr;
extern "C" MessageTableEntry* sFraMessageEntryTablePtr;
extern "C" MessageTableEntry* sJpnMessageEntryTablePtr;

static const std::array<MessageTableEntry**, LANGUAGE_MAX> messageTables = {
    &sNesMessageEntryTablePtr, &sGerMessageEntryTablePtr, &sFraMessageEntryTablePtr, &sJpnMessageEntryTablePtr
};

void SohMenu::UpdateLanguageMap(std::map<int32_t, const char*>& languageMap) {
    for (int32_t i = LANGUAGE_ENG; i < LANGUAGE_MAX; i++) {
        if (*messageTables.at(i) != NULL) {
            if (!languageMap.contains(i)) {
                languageMap.insert(std::make_pair(i, languages.at(i)));
            }
        } else {
            languageMap.erase(i);
        }
    }
}

void SohMenu::AddMenuSettings() {
    // Add Settings Menu
    AddMenuEntry("Settings", CVAR_SETTING("Menu.SettingsSidebarSection"));
    AddSidebarEntry("Settings", "General", 2);
    WidgetPath path = { "Settings", "General", SECTION_COLUMN_1 };

    // General - Settings
    AddWidget(path, "Menu Settings", WIDGET_SEPARATOR_TEXT);
    AddWidget(path, "Menu Theme", WIDGET_CVAR_COMBOBOX)
        .CVar(CVAR_SETTING("Menu.Theme"))
        .RaceDisable(false)
        .Options(ComboboxOptions()
                     .Tooltip("Changes the Theme of the Menu Widgets.")
                     .ComboMap(menuThemeOptions)
                     .DefaultIndex(Colors::LightBlue));
#if not defined(__SWITCH__) and not defined(__WIIU__)
    AddWidget(path, "Menu Controller Navigation", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_IMGUI_CONTROLLER_NAV)
        .RaceDisable(false)
        .Options(CheckboxOptions().Tooltip(
            "Allows controller navigation of the port menu (Settings, Enhancements,...)\nCAUTION: "
            "This will disable game inputs while the menu is visible.\n\nD-pad to move between "
            "items, A to select, B to move up in scope."));
    AddWidget(path, "Allow background inputs", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_ALLOW_BACKGROUND_INPUTS)
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) {
            SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS,
                        CVarGetInteger(CVAR_ALLOW_BACKGROUND_INPUTS, 1) ? "1" : "0");
        })
        .Options(CheckboxOptions()
                     .Tooltip("Allows controller inputs to be picked up by the game even when the game window isn't "
                              "the focused window.")
                     .DefaultValue(1));
    AddWidget(path, "Menu Background Opacity", WIDGET_CVAR_SLIDER_FLOAT)
        .CVar(CVAR_SETTING("Menu.BackgroundOpacity"))
        .RaceDisable(false)
        .Options(FloatSliderOptions().DefaultValue(0.85f).IsPercentage().Tooltip(
            "Sets the opacity of the background of the port menu."));

    AddWidget(path, "General Settings", WIDGET_SEPARATOR_TEXT);
    AddWidget(path, "Cursor Always Visible", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("CursorVisibility"))
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) {
            Ship::Context::GetRawInstance()->GetWindow()->SetForceCursorVisibility(
                CVarGetInteger(CVAR_SETTING("CursorVisibility"), 0));
        })
        .Options(CheckboxOptions().Tooltip("Makes the cursor always visible, even in full screen."));
#endif
    AddWidget(path, "Search In Sidebar", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("Menu.SidebarSearch"))
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) {
            if (CVarGetInteger(CVAR_SETTING("Menu.SidebarSearch"), 0)) {
                mSohMenu->InsertSidebarSearch();
            } else {
                mSohMenu->RemoveSidebarSearch();
            }
        })
        .Options(CheckboxOptions().Tooltip(
            "Displays the Search menu as a sidebar entry in Settings instead of in the header."));
    AddWidget(path, "Search Input Autofocus", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("Menu.SearchAutofocus"))
        .RaceDisable(false)
        .Options(CheckboxOptions().Tooltip(
            "Search input box gets autofocus when visible. Does not affect using other widgets."));
    AddWidget(path, "Reset Button Combination:", WIDGET_CVAR_BTN_SELECTOR)
        .CVar("gSettings.ResetBtn")
        .Options(BtnSelectorOptions().DefaultValue(BTN_CUSTOM_MODIFIER2));
#if defined(__ANDROID__)
    AddWidget(path, "Current Data Folder", WIDGET_CUSTOM).CustomFunction([](WidgetInfo& info) {
        std::string dataFolderPath = Ship::Context::GetAppDirectoryPath();
        ImGui::TextColored(ImVec4(1.0f, 1.0f, 1.0f, 0.7f), "Current Data Folder");
        ImGui::PushTextWrapPos(ImGui::GetContentRegionAvail().x);
        ImGui::TextUnformatted(dataFolderPath.c_str());
        ImGui::PopTextWrapPos();
    });
    AddWidget(path, "Change Data Folder", WIDGET_BUTTON)
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) { OpenAndroidDataFolderChooser(); })
        .Options(ButtonOptions().Tooltip("Choose where Android stores saves, mods, settings, and support files."));
#elif !defined(__IOS__)
    AddWidget(path, "Open App Files Folder", WIDGET_BUTTON)
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) {
            std::string filesPath = Ship::Context::GetRawInstance()->GetAppDirectoryPath();
            SDL_OpenURL(std::string("file:///" + std::filesystem::absolute(filesPath).string()).c_str());
        })
        .Options(ButtonOptions().Tooltip("Opens the folder that contains the save and mods folders, etc."));
#endif
#if defined(__IOS__)
    AddWidget(path, "iCloud Save Sync", WIDGET_SEPARATOR_TEXT);
    AddWidget(path, "Sync Saves with iCloud", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("iCloudSync.Saves"))
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) {
            if (CVarGetInteger(CVAR_SETTING("iCloudSync.Saves"), 0)) {
                SOHiCloudSync_SyncNow();
            }
        })
        .Options(CheckboxOptions()
                     .DefaultValue(0)
                     .Tooltip("Synchronizes the three save slots and global save through the private iCloud account. "
                              "Game archives, mods, graphics settings, and touch controls remain local."));
    AddWidget(path, "Sync Saves Now", WIDGET_BUTTON)
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) {
            if (CVarGetInteger(CVAR_SETTING("iCloudSync.Saves"), 0)) {
                SOHiCloudSync_SyncNow();
            }
        })
        .Options(ButtonOptions().Tooltip(
            "Checks for cloud changes and uploads newer local saves. A newer cloud save is loaded safely on restart."));
    AddWidget(path, "iCloud Save Status", WIDGET_CUSTOM).CustomFunction([](WidgetInfo& info) {
        char status[384] = {};
        SOHiCloudSync_GetStatus(status, sizeof(status));
        ImGui::PushTextWrapPos(ImGui::GetContentRegionAvail().x);
        if (CVarGetInteger(CVAR_SETTING("iCloudSync.Saves"), 0)) {
            ImGui::TextUnformatted(status);
        } else {
            ImGui::TextUnformatted("iCloud save sync is off.");
        }
        ImGui::PopTextWrapPos();
    });
#endif
#if defined(__TVOS__)
    AddWidget(path, "Apple TV File Transfer", WIDGET_SEPARATOR_TEXT);
    AddWidget(path, "File Transfer Status", WIDGET_CUSTOM).CustomFunction([](WidgetInfo& info) {
        char status[512] = {};
        SOHTVOSFileServer_GetStatus(status, sizeof(status));
        ImGui::PushTextWrapPos(ImGui::GetContentRegionAvail().x);
        ImGui::TextUnformatted(status);
        ImGui::PopTextWrapPos();
    });
    AddWidget(path, "Start File Transfer", WIDGET_BUTTON)
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) { SOHTVOSFileServer_Start(); })
        .Options(ButtonOptions().Tooltip(
            "Starts a private web page for uploading game archives, legal ROMs, and mods from your home network."));
    AddWidget(path, "Stop File Transfer", WIDGET_BUTTON)
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) { SOHTVOSFileServer_Stop(); })
        .Options(ButtonOptions().Tooltip("Stops the local-network upload page."));
#endif

    AddWidget(path, "Boot", WIDGET_SEPARATOR_TEXT);
    AddWidget(path, "Boot Sequence", WIDGET_CVAR_COMBOBOX)
        .CVar(CVAR_SETTING("BootSequence"))
        .RaceDisable(false)
        .Options(ComboboxOptions()
                     .DefaultIndex(BOOTSEQUENCE_DEFAULT)
                     .LabelPosition(LabelPositions::Far)
                     .ComponentAlignment(ComponentAlignments::Right)
                     .ComboMap(bootSequenceLabels)
                     .Tooltip("Configure what happens when starting or resetting the game.\n\n"
                              "Default: LUS logo -> N64 logo\n"
                              "Authentic: N64 logo only\n"
                              "File Select: Skip to file select menu\n"
                              "Debug Warp Screen: Skip to the debug warp screen\n"
                              "Warp Point: Skip to active warp point (if set), see Dev Tools -> General"));

    AddWidget(path, "Languages", WIDGET_SEPARATOR_TEXT);
    AddWidget(path, "Translate Title Screen", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("TitleScreenTranslation"))
        .RaceDisable(false);
    AddWidget(path, "Language", WIDGET_CVAR_COMBOBOX)
        .CVar(CVAR_SETTING("Languages"))
        .RaceDisable(false)
        .PreFunc([](WidgetInfo& info) {
            auto options = std::static_pointer_cast<UIWidgets::ComboboxOptions>(info.options);
            SohMenu::UpdateLanguageMap(options->comboMap);
        })
        .Options(ComboboxOptions()
                     .LabelPosition(LabelPositions::Far)
                     .ComponentAlignment(ComponentAlignments::Right)
                     .ComboMap(languages)
                     .DefaultIndex(LANGUAGE_ENG));
    AddWidget(path, "Accessibility", WIDGET_SEPARATOR_TEXT);
#if defined(_WIN32) || defined(__APPLE__) || defined(ESPEAK)
    AddWidget(path, "Text to Speech", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("A11yTTS"))
        .RaceDisable(false)
        .Options(CheckboxOptions().Tooltip("Enables text to speech for in-game dialogue"));
#endif
    AddWidget(path, "Disable Idle Camera Re-Centering", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("A11yDisableIdleCam"))
        .RaceDisable(false)
        .Options(CheckboxOptions().Tooltip("Disables the automatic re-centering of the camera when idle."));
    AddWidget(path, "Disable Screen Flash for Finishing Blow", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("A11yNoScreenFlashForFinishingBlow"))
        .RaceDisable(false)
        .Options(CheckboxOptions().Tooltip("Disables the white screen flash on enemy kill."));
    AddWidget(path, "Disable Jabu Wobble", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("A11yNoJabuWobble"))
        .RaceDisable(false)
        .Options(CheckboxOptions().Tooltip("Disable the geometry wobble and camera distortion inside Jabu."));
    AddWidget(path, "Disable Heat Haze", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("A11yNoHeatHaze"))
        .RaceDisable(false)
        .Options(CheckboxOptions().Tooltip("Disable the heat haze distortion effect in Death Mountain / Fire Temple."));
    AddWidget(path, "EXPERIMENTAL", WIDGET_SEPARATOR_TEXT).Options(TextOptions().Color(Colors::Orange));
    AddWidget(path, "Menu Scale", WIDGET_CUSTOM).CustomFunction([](WidgetInfo& info) {
        const auto theme = static_cast<Colors>(CVarGetInteger(CVAR_SETTING("Menu.Theme"), Colors::LightBlue));
        const float resetButtonWidth =
            ImGui::CalcTextSize(ICON_FA_UNDO).x + ImGui::GetStyle().FramePadding.x * 2.0f;
        const float sliderWidth =
            std::max(120.0f, ImGui::GetContentRegionAvail().x - resetButtonWidth - ImGui::GetStyle().ItemSpacing.x);

        CVarSliderFloat("Menu Scale: %.2fx", CVAR_SETTING("ImGuiScale.Value"),
                        FloatSliderOptions()
                            .Min(minImGuiScale)
                            .Max(maxImGuiScale)
                            .Step(0.05f)
                            .DefaultValue(1.0f)
                            .Format("%.2fx")
                            .Tooltip("Changes the scaling of the menu elements.")
                            .ShowButtons(true)
                            .Size(ImVec2(sliderWidth, 0.0f))
                            .ComponentAlignment(ComponentAlignments::Left)
                            .LabelPosition(LabelPositions::Above)
                            .Color(theme));

        ImGui::SameLine();
        if (Button(ICON_FA_UNDO "##ResetMenuScale",
                   ButtonOptions()
                       .Tooltip("Reset menu scale to 100%.")
                       .Size(Sizes::Inline)
                       .Color(theme))) {
            CVarSetFloat(CVAR_SETTING("ImGuiScale.Value"), 1.0f);
            Ship::Context::GetRawInstance()->GetWindow()->GetGui()->SaveConsoleVariablesNextFrame();
        }
        OTRGlobals::Instance->ScaleImGui();
    });

    // General - About
    path.column = SECTION_COLUMN_2;

    AddWidget(path, "About", WIDGET_SEPARATOR_TEXT);
    AddWidget(path, "Ship Of Harkinian", WIDGET_TEXT);
#if defined(__ANDROID__) && defined(ANDROID_APP_VERSION_NAME)
    AddWidget(path, "Android App Version", WIDGET_TEXT);
    AddWidget(path, ANDROID_APP_VERSION_NAME, WIDGET_TEXT);
#endif
    if (gGitCommitTag[0] != 0) {
        AddWidget(path, gBuildVersion, WIDGET_TEXT);
    } else {
        AddWidget(path, ("Branch: " + std::string(gGitBranch)), WIDGET_TEXT);
        AddWidget(path, ("Commit: " + std::string(gGitCommitHash)), WIDGET_TEXT);
    }
    for (uint32_t i = 0; i < ResourceMgr_GetNumGameVersions(); i++) {
        AddWidget(path, GetGameVersionString(i), WIDGET_TEXT);
    }

    // Audio Settings
    path.sidebarName = "Audio";
    path.column = SECTION_COLUMN_1;
    AddSidebarEntry("Settings", "Audio", 3);

    AddWidget(path, "Master Volume: %d %%", WIDGET_CVAR_SLIDER_INT)
        .CVar(CVAR_SETTING("Volume.Master"))
        .RaceDisable(false)
        .Options(IntSliderOptions().Min(0).Max(100).DefaultValue(40).ShowButtons(true).Format(""));
    AddWidget(path, "Main Music Volume: %d %%", WIDGET_CVAR_SLIDER_INT)
        .CVar(CVAR_SETTING("Volume.MainMusic"))
        .RaceDisable(false)
        .Options(IntSliderOptions().Min(0).Max(100).DefaultValue(100).ShowButtons(true).Format(""))
        .Callback([](WidgetInfo& info) {
            Audio_SetGameVolume(SEQ_PLAYER_BGM_MAIN,
                                ((float)CVarGetInteger(CVAR_SETTING("Volume.MainMusic"), 100) / 100.0f));
        });
    AddWidget(path, "Sub Music Volume: %d %%", WIDGET_CVAR_SLIDER_INT)
        .CVar(CVAR_SETTING("Volume.SubMusic"))
        .RaceDisable(false)
        .Options(IntSliderOptions().Min(0).Max(100).DefaultValue(100).ShowButtons(true).Format(""))
        .Callback([](WidgetInfo& info) {
            Audio_SetGameVolume(SEQ_PLAYER_BGM_SUB,
                                ((float)CVarGetInteger(CVAR_SETTING("Volume.SubMusic"), 100) / 100.0f));
        });
    AddWidget(path, "Fanfare Volume: %d %%", WIDGET_CVAR_SLIDER_INT)
        .CVar(CVAR_SETTING("Volume.Fanfare"))
        .RaceDisable(false)
        .Options(IntSliderOptions().Min(0).Max(100).DefaultValue(100).ShowButtons(true).Format(""))
        .Callback([](WidgetInfo& info) {
            Audio_SetGameVolume(SEQ_PLAYER_FANFARE,
                                ((float)CVarGetInteger(CVAR_SETTING("Volume.Fanfare"), 100) / 100.0f));
        });
    AddWidget(path, "Sound Effects Volume: %d %%", WIDGET_CVAR_SLIDER_INT)
        .CVar(CVAR_SETTING("Volume.SFX"))
        .RaceDisable(false)
        .Options(IntSliderOptions().Min(0).Max(100).DefaultValue(100).ShowButtons(true).Format(""))
        .Callback([](WidgetInfo& info) {
            Audio_SetGameVolume(SEQ_PLAYER_SFX, ((float)CVarGetInteger(CVAR_SETTING("Volume.SFX"), 100) / 100.0f));
        });
    AddWidget(path, "Audio API (Needs reload)", WIDGET_AUDIO_BACKEND).RaceDisable(false);

    // Graphics Settings
    static int32_t maxFps = 360;
    const char* tooltip =
        "Uses Matrix Interpolation to create extra frames, resulting in smoother graphics. This is "
        "purely visual and does not impact game logic, execution of glitches, etc.\n\nA higher target "
        "FPS than your monitor's refresh rate will waste resources, and might give a worse result.";
    path.sidebarName = "Graphics";
    AddSidebarEntry("Settings", "Graphics", 3);
    AddWidget(path, "Graphics Options", WIDGET_SEPARATOR_TEXT);
    AddWidget(path, "Toggle Fullscreen", WIDGET_BUTTON)
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) { Ship::Context::GetRawInstance()->GetWindow()->ToggleFullscreen(); })
        .Options(ButtonOptions().Tooltip("Toggles Fullscreen On/Off."));
    AddWidget(path, "Internal Resolution", WIDGET_CVAR_SLIDER_FLOAT)
        .CVar(CVAR_INTERNAL_RESOLUTION)
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) {
            Ship::Context::GetRawInstance()->GetWindow()->SetResolutionMultiplier(
                CVarGetFloat(CVAR_INTERNAL_RESOLUTION, 1));
        })
        .PreFunc([](WidgetInfo& info) {
            if (mSohMenu->disabledMap.at(DISABLE_FOR_ADVANCED_RESOLUTION_ON).active &&
                mSohMenu->disabledMap.at(DISABLE_FOR_VERTICAL_RES_TOGGLE_ON).active) {
                info.activeDisables.push_back(DISABLE_FOR_ADVANCED_RESOLUTION_ON);
                info.activeDisables.push_back(DISABLE_FOR_VERTICAL_RES_TOGGLE_ON);
            } else if (mSohMenu->disabledMap.at(DISABLE_FOR_LOW_RES_MODE_ON).active) {
                info.activeDisables.push_back(DISABLE_FOR_LOW_RES_MODE_ON);
            }
        })
        .Options(
            FloatSliderOptions()
                .Tooltip("Multiplies your output resolution by the value inputted, as a more intensive but effective "
                         "form of anti-aliasing.")
                .ShowButtons(false)
                .IsPercentage()
                .Min(0.5f)
                .Max(2.0f));
#ifndef __WIIU__
    AddWidget(path, "Anti-aliasing (MSAA)", WIDGET_CVAR_SLIDER_INT)
        .CVar(CVAR_MSAA_VALUE)
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) {
            Ship::Context::GetRawInstance()->GetWindow()->SetMsaaLevel(CVarGetInteger(CVAR_MSAA_VALUE, 1));
        })
        .Options(
            IntSliderOptions()
                .Tooltip("Activates MSAA (multi-sample anti-aliasing) from 2x up to 8x, to smooth the edges of "
                         "rendered geometry.\n"
                         "Higher sample count will result in smoother edges on models, but may reduce performance.")
                .Min(1)
                .Max(8)
                .DefaultValue(1));
#endif
    auto fps = CVarGetInteger(CVAR_SETTING("InterpolationFPS"), 20);
    const char* fpsFormat = fps == 20 ? "Original (%d)" : "%d";
    AddWidget(path, "Current FPS", WIDGET_CVAR_SLIDER_INT)
        .CVar(CVAR_SETTING("InterpolationFPS"))
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) {
            auto options = std::static_pointer_cast<IntSliderOptions>(info.options);
            int32_t defaultValue = options->defaultValue;
            if (CVarGetInteger(info.cVar, defaultValue) == defaultValue) {
                options->format = "Original (%d)";
            } else {
                options->format = "%d";
            }
        })
        .PreFunc([](WidgetInfo& info) {
            if (mSohMenu->disabledMap.at(DISABLE_FOR_MATCH_REFRESH_RATE_ON).active)
                info.activeDisables.push_back(DISABLE_FOR_MATCH_REFRESH_RATE_ON);
        })
        .Options(IntSliderOptions().Tooltip(tooltip).Min(20).Max(maxFps).DefaultValue(20).Format(fpsFormat));
    AddWidget(path, "Match Refresh Rate", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("MatchRefreshRate"))
        .RaceDisable(false)
        .Options(CheckboxOptions().Tooltip("Matches interpolation value to the refresh rate of your display."));
    AddWidget(path, "Renderer API (Needs reload)", WIDGET_VIDEO_BACKEND).RaceDisable(false);
    AddWidget(path, "Enable Vsync", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_VSYNC_ENABLED)
        .RaceDisable(false)
        .PreFunc([](WidgetInfo& info) { info.isHidden = mSohMenu->disabledMap.at(DISABLE_FOR_NO_VSYNC).active; })
        .Options(CheckboxOptions()
                     .Tooltip("Removes tearing, but clamps your max FPS to your display's refresh rate.")
                     .DefaultValue(true));
    AddWidget(path, "Windowed Fullscreen", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SDL_WINDOWED_FULLSCREEN)
        .RaceDisable(false)
        .PreFunc([](WidgetInfo& info) {
            info.isHidden = mSohMenu->disabledMap.at(DISABLE_FOR_NO_WINDOWED_FULLSCREEN).active;
        })
        .Options(CheckboxOptions().Tooltip("Enables Windowed Fullscreen Mode."));
    AddWidget(path, "Allow multi-windows", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_ENABLE_MULTI_VIEWPORTS)
        .RaceDisable(false)
        .PreFunc(
            [](WidgetInfo& info) { info.isHidden = mSohMenu->disabledMap.at(DISABLE_FOR_NO_MULTI_VIEWPORT).active; })
        .Options(CheckboxOptions()
                     .Tooltip("Allows multiple windows to be opened at once. Requires a reload to take effect.")
                     .DefaultValue(true));
    AddWidget(path, "Texture Filter (Needs reload)", WIDGET_CVAR_COMBOBOX)
        .CVar(CVAR_TEXTURE_FILTER)
        .RaceDisable(false)
        .Options(ComboboxOptions().Tooltip("Sets the applied Texture Filtering.").ComboMap(textureFilteringMap));

    path.column = SECTION_COLUMN_2;
    AddWidget(path, "Advanced Graphics Options", WIDGET_SEPARATOR_TEXT);

    // Controls
    path.sidebarName = "Controls";
    path.column = SECTION_COLUMN_1;
    AddSidebarEntry("Settings", "Controls", 2);
    AddWidget(path, "Manual Jump (Experimental)", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_ENHANCEMENT("ManualJump"))
        .Options(CheckboxOptions().Tooltip("Experimental: enable grounded jumps with your Jump binding. Disabled by "
                                          "default and during race lockout. Configure the button in Manual Jump Bindings."));
    AddWidget(path, "Manual Jump Bindings", WIDGET_BUTTON)
        .Callback([](WidgetInfo& info) {
            auto window = std::dynamic_pointer_cast<SohInputEditorWindow>(
                Ship::Context::GetRawInstance()->GetWindow()->GetGui()->GetGuiWindow("Configure Controller"));
            if (window != nullptr) {
                window->OpenManualJumpMenu();
            }
        })
        .Options(ButtonOptions().Size(Sizes::Inline));
    AddWidget(path, "Clear Devices", WIDGET_BUTTON)
        .Callback([](WidgetInfo& info) {
            SohGui::mModalWindow->RegisterPopup(
                "Clear Config",
                "This will completely erase the controls config, including registered devices.\nContinue?", "Clear",
                "Cancel",
                []() {
                    Ship::Context::GetRawInstance()->GetConsoleVariables()->ClearBlock(CVAR_PREFIX_SETTING
                                                                                       ".Controllers");
                    uint8_t bits = 0;
                    Ship::Context::GetRawInstance()->GetControlDeck()->Init(&bits);
                },
                nullptr);
        })
        .Options(ButtonOptions().Size(Sizes::Inline));
    AddWidget(path, "Controller Bindings", WIDGET_SEPARATOR_TEXT);
    AddWidget(path, "Popout Bindings Window", WIDGET_WINDOW_BUTTON)
        .CVar(CVAR_WINDOW("ControllerConfiguration"))
        .RaceDisable(false)
        .WindowName("Configure Controller")
        .HideInSearch(true)
        .Options(WindowButtonOptions().Tooltip("Enables the separate Bindings Window."));

#if defined(__ANDROID__)
    // Touch Controls
    path.sidebarName = "Touch Controls";
    path.column = SECTION_COLUMN_1;
    AddSidebarEntry("Settings", path.sidebarName, 2);
    AddWidget(path, "Touch Controller Style", WIDGET_CVAR_COMBOBOX)
        .CVar(CVAR_SETTING("TouchControls.Style"))
        .RaceDisable(false)
        .Callback([](WidgetInfo&) { SetAndroidIntegratedTouch(); })
        .Options(ComboboxOptions().DefaultIndex(0).ComboMap(touchStyleMap).Tooltip(
            "Classic preserves the existing controls and HUD. Integrated presets place live item icons on the touch buttons."));
    AddWidget(path, "Edit Integrated Touch Layout", WIDGET_BUTTON)
        .PreFunc([](WidgetInfo& info) { info.isHidden = CVarGetInteger(CVAR_SETTING("TouchControls.Style"), 0) == 0; })
        .RaceDisable(false).Callback([](WidgetInfo&) { EditAndroidIntegratedTouch(); });
    AddWidget(path, "Size", WIDGET_CVAR_SLIDER_FLOAT)
        .CVar(CVAR_SETTING("TouchControls.Scale"))
        .PreFunc([](WidgetInfo& info) { info.isHidden = CVarGetInteger(CVAR_SETTING("TouchControls.Style"), 0) == 0; })
        .RaceDisable(false).Callback([](WidgetInfo&) { SetAndroidIntegratedTouch(); })
        .Options(FloatSliderOptions().Min(.75f).Max(1.5f).DefaultValue(1).IsPercentage());
    AddWidget(path, "Opacity", WIDGET_CVAR_SLIDER_FLOAT)
        .CVar(CVAR_SETTING("TouchControls.Opacity"))
        .PreFunc([](WidgetInfo& info) { info.isHidden = CVarGetInteger(CVAR_SETTING("TouchControls.Style"), 0) == 0; })
        .RaceDisable(false).Callback([](WidgetInfo&) { SetAndroidIntegratedTouch(); })
        .Options(FloatSliderOptions().Min(.15f).Max(1).DefaultValue(.55f).IsPercentage());
    AddWidget(path, "Touch Face Buttons", WIDGET_CVAR_COMBOBOX)
        .CVar(CVAR_SETTING("TouchControls.FaceButtonLayout"))
        .PreFunc([](WidgetInfo& info) { info.isHidden = CVarGetInteger(CVAR_SETTING("TouchControls.Style"), 0) != 0; })
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) {
            SetAndroidTouchFaceButtonLayout(
                CVarGetInteger(CVAR_SETTING("TouchControls.FaceButtonLayout"), 0));
        })
        .Options(ComboboxOptions()
                     .ComboMap(touchFaceButtonLayoutMap)
                     .DefaultIndex(0)
                     .Tooltip("Choose ABXY (Nintendo), BAYX (Xbox), or GC Layout touch-button placement."));
    AddWidget(path, "Floating Left Stick", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("TouchControls.FloatingLeftStick"))
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) {
            SetAndroidTouchLeftStickFloating(
                CVarGetInteger(CVAR_SETTING("TouchControls.FloatingLeftStick"), 1) != 0);
        })
        .Options(CheckboxOptions().DefaultValue(true).Tooltip(
            "When disabled, the left touch stick stays fixed in the lower-left corner."));
    AddWidget(path, "Transparent Sticks", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("TouchControls.TransparentSticks"))
        .RaceDisable(false)
        .Callback([](WidgetInfo&) { SetAndroidIntegratedTouch(); })
        .Options(CheckboxOptions().Tooltip(
            "Hides fixed stick backgrounds and outlines while keeping the small position indicators visible. "
            "Floating sticks are always transparent. The layout editor still shows their bounds."));
    AddWidget(path, "Floating Right Stick", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("TouchControls.FloatingRightStick"))
        .RaceDisable(false)
        .Callback([](WidgetInfo&) { SetAndroidIntegratedTouch(); })
        .Options(CheckboxOptions().DefaultValue(true).Tooltip(
            "Sets the right camera stick's origin where you touch inside its area. "
            "When disabled, its origin is fixed. Independent of Floating Left Stick."));
    AddWidget(path, "Disable Touch Controls", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("TouchControls.Disabled"))
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) {
            SetAndroidTouchControlsDisabled(CVarGetInteger(CVAR_SETTING("TouchControls.Disabled"), 0) != 0);
        })
        .Options(CheckboxOptions().Tooltip("Hides the Android touch controls and eye button."));
    AddWidget(path, "Extra Item Slots", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_ENHANCEMENT("DpadEquips"))
        .Options(CheckboxOptions().Tooltip(
            "Enables up to four extra items on the D-pad, for every layout and physical controllers. "
            "In the pause inventory, highlight an item and press a D-pad direction to equip it. "
            "If D-pad pause navigation is enabled, hold C-up (the touch Fairy control) while pressing the direction. "
            "Integrated layouts can assign Extra Item 1-4 to other touch buttons in the right column. Unused slots may remain empty."));
    AddWidget(path, "Allow Unequipping Items", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_ENHANCEMENT("ItemUnequip"))
        .PreFunc([](WidgetInfo& info) { info.isHidden = !CVarGetInteger(CVAR_ENHANCEMENT("DpadEquips"),0); })
        .Options(CheckboxOptions().Tooltip(
            "Highlight an equipped item and press its assigned C-button or D-pad direction again to clear that slot. "
            "This is the existing shared item-unequip enhancement."));

    path.column = SECTION_COLUMN_2;
    AddWidget(path, "Touch Button Assignments", WIDGET_SEPARATOR_TEXT)
        .PreFunc([](WidgetInfo& info) { info.isHidden = CVarGetInteger(CVAR_SETTING("TouchControls.Style"), 0) == 0; });
    AddWidget(path, "Enable Manual Jump (Experimental)", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_ENHANCEMENT("ManualJump"))
        .PreFunc([](WidgetInfo& info) { info.isHidden = CVarGetInteger(CVAR_SETTING("TouchControls.Style"), 0) == 0; })
        .Callback([](WidgetInfo&) { SetAndroidIntegratedTouch(); })
        .Options(CheckboxOptions().Tooltip(
            "The existing Manual Jump enhancement. Enables grounded jumps and disables automatic ledge jumps. "
            "Touch button choices below are separate from physical controller bindings."));
    static const std::map<int32_t,const char*> touchJumpButtons[3] = {
        {{0,"Off"},{1,"C-left"},{2,"C-down"},{3,"C-right"}},
        {{0,"Off"},{1,"X"},{2,"Y"},{3,"Z"}},
        {{0,"Off"},{1,"X"},{2,"Y"},{3,"ZR"}}
    };
    for (int style=1; style<=3; ++style) {
        AddWidget(path,"Jump Button##TouchJump"+std::to_string(style),WIDGET_CVAR_COMBOBOX)
            .CVar(TouchHud::JumpCvar(style))
            .PreFunc([style](WidgetInfo& info) { info.isHidden = CVarGetInteger(CVAR_SETTING("TouchControls.Style"),0) != style; })
            .RaceDisable(false)
            .Callback([](WidgetInfo&) {
                SetAndroidIntegratedTouch();
                Ship::Context::GetRawInstance()->GetWindow()->GetGui()->SaveConsoleVariablesNextFrame();
            })
            .Options(ComboboxOptions().DefaultIndex(0).ComboMap(touchJumpButtons[style-1]).Tooltip(
                "Manual Jump takes priority over this touch button's item assignment while enabled. "
                "Off restores its saved assignment. If this button was Navi, Navi returns to the Fairy/C-up control. "
                "Physical controller bindings are unchanged."));
    }
    static const std::map<int32_t,const char*> touchVaultModes = {{0,"Automatic"},{1,"Manual"}};
    AddWidget(path,"Vaulting Mode",WIDGET_CVAR_COMBOBOX)
        .CVar(CVAR_ENHANCEMENT("ManualJumpVaultMode"))
        .PreFunc([](WidgetInfo& info) { info.isHidden = CVarGetInteger(CVAR_SETTING("TouchControls.Style"),0) == 0; })
        .Options(ComboboxOptions().DefaultIndex(1).ComboMap(touchVaultModes).Tooltip(
            "The shared Manual Jump gameplay option: Automatic keeps native vaults and short step-ups. "
            "Manual requires Jump while moving into these obstacles, with a 180 ms buffer. "
            "Tall climbs and A-button climbing remain unchanged. Manual Jump must be enabled."));
    AddWidget(path, "Navi Button", WIDGET_CVAR_COMBOBOX)
        .CVar(CVAR_SETTING("TouchControls.GameCubeNaviLocation"))
        .PreFunc([](WidgetInfo& info) { info.isHidden = CVarGetInteger(CVAR_SETTING("TouchControls.Style"), 0) != 2; })
        .RaceDisable(false)
        .Callback([](WidgetInfo&) {
            int location = CVarGetInteger(CVAR_SETTING("TouchControls.GameCubeNaviLocation"), 0);
            if (location >= 0 && location <= 2) {
                const int destinations[] = {14, 9, 3};
                int destination = destinations[location];
                int displaced = touchBindingSnapshot[2][destination];
                bool moved = displaced == TouchHud::Navi;
                for (int i=0; i<TouchHud::BindingCount; ++i) if (i != destination && touchBindingSnapshot[2][i] == TouchHud::Navi) {
                    CVarSetInteger(TouchHud::BindingCvar(2, i), moved ? TouchHud::Disabled : displaced);
                    moved = true;
                }
                CVarSetInteger(TouchHud::BindingCvar(2, destination), TouchHud::Navi);
            }
            SetAndroidIntegratedTouch();
            Ship::Context::GetRawInstance()->GetWindow()->GetGui()->SaveConsoleVariablesNextFrame();
        })
        .Options(ComboboxOptions().DefaultIndex(0).ComboMap(touchNaviLocationMap).Tooltip(
            "Defaults to the small Fairy button. D-pad Up and Z swap their current function with Navi, "
            "so no item input is lost. Physical controllers are unchanged."));
    static const char* labels[3][TouchHud::BindingCount] = {
        {"A", "B", "C-left", "C-down", "C-right", "C-up", "Z", "L", "R", "D-pad up", "D-pad down", "D-pad left", "D-pad right", "Start", "Fairy / utility", "Map"},
        {"A", "B", "Y", "Z", "X", "C-up", "L", "Extra", "R", "D-pad up", "D-pad down", "D-pad left", "D-pad right", "Start", "Fairy / utility", "Map"},
        {"A", "B", "X", "Y", "ZR", "Fairy", "ZL", "L", "R", "D-pad up", "D-pad down", "D-pad left", "D-pad right", "Start", "Fairy / utility", "Map"}
    };
    for (int style=1; style<=3; ++style) for (int i=0; i<TouchHud::BindingCount; ++i) {
        AddWidget(path, std::string(labels[style-1][i]) + "##TouchBinding" + std::to_string(style) + "_" + TouchHud::Keys[i], WIDGET_CVAR_COMBOBOX)
            .CVar(TouchHud::BindingCvar(style, i))
            .PreFunc([style, i](WidgetInfo& info) {
                info.isHidden = CVarGetInteger(CVAR_SETTING("TouchControls.Style"), 0) != style ||
                    (i == 14 && style != 2) ||
                    (i == 15 && style == 1 && !CVarGetInteger(CVAR_CHEAT("MoonJumpOnL"),0));
                bool jumpOverride = CVarGetInteger(CVAR_ENHANCEMENT("ManualJump"),0) &&
                    !CVarGetInteger(CVAR_SETTING("DisableChanges"),0) &&
                    TouchHud::JumpIndex(style,CVarGetInteger(TouchHud::JumpCvar(style),0)) == i;
                info.options->disabled = jumpOverride;
                if (jumpOverride) info.options->disabledTooltip = "Manual Jump currently overrides this touch button. Choose Off in Jump Button to restore this assignment.";
            })
            .RaceDisable(false)
            .Callback([style, i](WidgetInfo&) {
                int chosen = CVarGetInteger(TouchHud::BindingCvar(style, i), TouchHud::DefaultAction(style, i));
                // Swap functions instead of silently duplicating an item/prompt anchor.
                if (chosen != TouchHud::Disabled) for (int j=0; j<TouchHud::BindingCount; ++j) {
                    if (j != i && touchBindingSnapshot[style][j] == chosen)
                        CVarSetInteger(TouchHud::BindingCvar(style, j), touchBindingSnapshot[style][i]);
                }
                SetAndroidIntegratedTouch();
                Ship::Context::GetRawInstance()->GetWindow()->GetGui()->SaveConsoleVariablesNextFrame();
            })
            .Options(ComboboxOptions().DefaultIndex(TouchHud::DefaultAction(style, i)).ComboMap(touchActionMap).Tooltip(
                "Touch-only assignment for this preset. Selecting an assigned action swaps the two touch buttons. "
                "Item icons and prompts follow these assignments. Physical controller bindings are unchanged. "
                "M1/M2 use the existing shared modifier effects. Warning: M2 resets the game by default; "
                "check Settings > General > Reset Button Combination before assigning it."));
    }
    AddWidget(path, "Restore Default Assignments", WIDGET_BUTTON)
        .PreFunc([](WidgetInfo& info) { info.isHidden = CVarGetInteger(CVAR_SETTING("TouchControls.Style"), 0) == 0; })
        .RaceDisable(false)
        .Callback([](WidgetInfo&) {
            int style = std::clamp(CVarGetInteger(CVAR_SETTING("TouchControls.Style"), 0), 1, 3);
            for (int i=0; i<TouchHud::BindingCount; ++i)
                CVarSetInteger(TouchHud::BindingCvar(style, i), TouchHud::DefaultAction(style, i));
            CVarSetInteger(TouchHud::JumpCvar(style), 0);
            SetAndroidIntegratedTouch();
            Ship::Context::GetRawInstance()->GetWindow()->GetGui()->SaveConsoleVariablesNextFrame();
        }).Options(ButtonOptions().Tooltip("Restores only this preset's touch assignments. Positions, sizes and physical controllers are unchanged."));

    // Keep Android's persisted overlay state aligned with the native CVars after relaunches.
    SetAndroidTouchFaceButtonLayout(CVarGetInteger(CVAR_SETTING("TouchControls.FaceButtonLayout"), 0));
    SetAndroidIntegratedTouch();
    SetAndroidTouchLeftStickFloating(
        CVarGetInteger(CVAR_SETTING("TouchControls.FloatingLeftStick"), 1) != 0);
    SetAndroidTouchControlsDisabled(CVarGetInteger(CVAR_SETTING("TouchControls.Disabled"), 0) != 0);
#endif

    // Input Viewer
    path.sidebarName = "Input Viewer";
    path.column = SECTION_COLUMN_1;
    AddSidebarEntry("Settings", path.sidebarName, 3);
    AddWidget(path, "Input Viewer", WIDGET_SEPARATOR_TEXT);
    AddWidget(path, "Toggle Input Viewer", WIDGET_WINDOW_BUTTON)
        .CVar(CVAR_WINDOW("InputViewer"))
        .RaceDisable(false)
        .WindowName("Input Viewer")
        .HideInSearch(true)
        .Options(WindowButtonOptions().Tooltip("Toggles the Input Viewer.").EmbedWindow(false));

    AddWidget(path, "Input Viewer Settings", WIDGET_SEPARATOR_TEXT);
    AddWidget(path, "Popout Input Viewer Settings", WIDGET_WINDOW_BUTTON)
        .CVar(CVAR_WINDOW("InputViewerSettings"))
        .RaceDisable(false)
        .WindowName("Input Viewer Settings")
        .HideInSearch(true)
        .Options(WindowButtonOptions().Tooltip("Enables the separate Input Viewer Settings Window."));

    // Notifications
    path.sidebarName = "Notifications";
    path.column = SECTION_COLUMN_1;
    AddSidebarEntry("Settings", path.sidebarName, 3);
    AddWidget(path, "Position", WIDGET_CVAR_COMBOBOX)
        .CVar(CVAR_SETTING("Notifications.Position"))
        .RaceDisable(false)
        .Options(ComboboxOptions()
                     .Tooltip("Which corner of the screen notifications appear in.")
                     .ComboMap(notificationPosition)
                     .DefaultIndex(3));
    AddWidget(path, "Duration (seconds):", WIDGET_CVAR_SLIDER_FLOAT)
        .CVar(CVAR_SETTING("Notifications.Duration"))
        .RaceDisable(false)
        .Options(FloatSliderOptions()
                     .Tooltip("How long notifications are displayed for.")
                     .Format("%.1f")
                     .Step(0.1f)
                     .Min(3.0f)
                     .Max(30.0f)
                     .DefaultValue(10.0f));
    AddWidget(path, "Background Opacity", WIDGET_CVAR_SLIDER_FLOAT)
        .CVar(CVAR_SETTING("Notifications.BgOpacity"))
        .RaceDisable(false)
        .Options(FloatSliderOptions()
                     .Tooltip("How opaque the background of notifications is.")
                     .DefaultValue(0.5f)
                     .IsPercentage());
    AddWidget(path, "Size:", WIDGET_CVAR_SLIDER_FLOAT)
        .CVar(CVAR_SETTING("Notifications.Size"))
        .RaceDisable(false)
        .Options(FloatSliderOptions()
                     .Tooltip("How large notifications are.")
                     .Format("%.1f")
                     .Step(0.1f)
                     .Min(1.0f)
                     .Max(5.0f)
                     .DefaultValue(1.8f));
    AddWidget(path, "Test Notification", WIDGET_BUTTON)
        .RaceDisable(false)
        .Callback([](WidgetInfo& info) {
            Notification::Emit({
                .itemIcon = "__OTR__textures/icon_item_24_static/gQuestIconGoldSkulltulaTex",
                .prefix = "This",
                .message = "is a",
                .suffix = "test.",
            });
        })
        .Options(ButtonOptions().Tooltip("Displays a test notification."));
    AddWidget(path, "Mute Notification Sound", WIDGET_CVAR_CHECKBOX)
        .CVar(CVAR_SETTING("Notifications.Mute"))
        .RaceDisable(false)
        .Options(CheckboxOptions().Tooltip("Prevent notifications from playing a sound."));

    // Mod Menu
    path.sidebarName = "Mod Menu";
    AddSidebarEntry("Settings", path.sidebarName, 1);
    AddWidget(path, "Popout Mod Menu Window", WIDGET_WINDOW_BUTTON)
        .CVar(CVAR_WINDOW("ModMenu"))
        .WindowName("Mod Menu")
        .HideInSearch(true)
        .Options(WindowButtonOptions().Tooltip("Enables the separate Mod Menu Window."));
}

} // namespace SohGui
