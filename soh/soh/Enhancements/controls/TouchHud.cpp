#include "TouchHud.h"
#if defined(__ANDROID__) || (defined(__IOS__) && !defined(__TVOS__))
#include "TouchHudGeometry.h"
#include "TouchHudBindings.h"
#include "TouchOcarina.h"
#include "TouchRightStick.h"
#include "soh/ShipInit.hpp"
#include "soh/OTRGlobals.h"
#include "soh/Enhancements/game-interactor/GameInteractor.h"
#include <ship/Context.h>
#include <libultraship/bridge/consolevariablebridge.h>
#include <ship/window/Window.h>
#include <ship/window/gui/Gui.h>
#ifdef __ANDROID__
#include <jni.h>
#endif
#include <atomic>
#include <array>
#include <mutex>
extern "C" {
#include "functions.h"
#include "macros.h"
#include "variables.h"
extern PlayState* gPlayState;
}
namespace {
std::atomic<bool> active{false};
std::atomic<bool> naviUtilityIcon{false};
std::atomic<int> state{0}; // low bits: menu/play/Navi-on-L/jump/free-look; bits 8..17: drawn content
std::atomic<uint32_t> drawnContent{0};
std::atomic<uint32_t> held{0}, pending{0};
std::atomic<bool> pendingMap{false}, mapPressed{false};
std::atomic<bool> pendingNavi{false}, naviPressed{false};
std::atomic<int> stickX{0}, stickY{0};
std::atomic<int> rightX{0}, rightY{0};
std::mutex layoutMutex;
std::array<TouchHud::Anchor, 10> anchors;
void Reset() { held = pending = 0; pendingMap = mapPressed = pendingNavi = naviPressed = false; stickX = stickY = rightX = rightY = 0; }
bool ManualJumpActive() {
    return CVarGetInteger(CVAR_ENHANCEMENT("ManualJump"), 0) &&
           !CVarGetInteger(CVAR_SETTING("DisableChanges"), 0);
}
bool OcarinaPlaying() {
    return gPlayState && GET_PLAYER(gPlayState) &&
           (GET_PLAYER(gPlayState)->stateFlags2 & PLAYER_STATE2_OCARINA_PLAYING);
}
void Init() {
    GameInteractor::Instance->RegisterGameHook<GameInteractor::OnGameFrameUpdate>([] {
        const auto context = Ship::Context::GetRawInstance();
        const bool menu = context && context->GetWindow() && context->GetWindow()->GetGui() &&
                          context->GetWindow()->GetGui()->GetMenuOrMenubarVisible();
        // Publish the completed frame's actual draws, not save-file assignments.
        // Hidden HUDs and title screens must retain full-sized button letters.
        int next = (menu ? 1 : 0) | (gPlayState != nullptr ? 2 : 0) |
                   (CVarGetInteger(CVAR_ENHANCEMENT("NaviOnL"), 0) ? 4 : 0) |
                   (ManualJumpActive() ? 8 : 0) |
                   (CVarGetInteger(CVAR_SETTING("FreeLook.Enabled"), 0) ? 16 : 0) |
                   (CVarGetInteger(CVAR_CHEAT("MoonJumpOnL"), 0) ? 32 : 0) |
                   (gPlayState && gPlayState->pauseCtx.state != 0 ? 64 : 0) |
                   (OcarinaPlaying() ? 128 : 0);
        const auto content = drawnContent.exchange(0);
        if (!menu && active && gPlayState != nullptr) next |= content << 8;
        state = next;
        if (menu) Reset();
    });
}
RegisterShipInitFunc init(Init);
}
extern "C" int TouchHud_GetState() { return state; }
extern "C" int TouchHud_GetBindings(int style, int32_t* bindings, int count) {
    if (!bindings || count != TouchHud::BindingCount) return 0;
    style = std::clamp<int>(style, 0, 3);
    const auto context = Ship::Context::GetRawInstance();
    const bool settingsReady = context && context->GetConsoleVariables();
    for (int i=0; i<TouchHud::BindingCount; ++i) {
        int action = settingsReady ? CVarGetInteger(TouchHud::BindingCvar(style, i), TouchHud::DefaultAction(style, i))
                                   : TouchHud::DefaultAction(style, i);
        bindings[i] = action >= 0 && action < TouchHud::ActionCount ? action : TouchHud::DefaultAction(style, i);
    }
    if (settingsReady && ManualJumpActive() && !OcarinaPlaying() && !(gPlayState && gPlayState->pauseCtx.state != 0)) {
        int index = TouchHud::JumpIndex(style, CVarGetInteger(TouchHud::JumpCvar(style), 0));
        if (index >= 0) bindings[index] = TouchHud::ManualJump;
    }
    return TouchHud::BindingCount;
}
extern "C" void TouchHud_SetButton(uint32_t mask, int down) {
    // A semantic map action must not send N64 L: that may also answer Navi.
    if (mask == 0x10000) { if (down) pendingMap = true; return; }
    if (mask == 0x20000) {
        if (down && !(state.load() & 128)) pendingNavi = true;
        mask = 8; // Preserve the Fairy icon, but retain normal C-up look/note behavior.
    }
    if (down) { held.fetch_or(mask); pending.fetch_or(mask); }
    else held.fetch_and(~static_cast<uint32_t>(mask));
}
extern "C" void TouchHud_SetStick(int x, int y) {
    stickX = std::clamp(x, -85, 85); stickY = std::clamp(y, -85, 85);
}
extern "C" int TouchHud_SetRightStick(int x, int y) {
    int style = CVarGetInteger(CVAR_SETTING("TouchControls.Style"), 0);
    if (style != 1 && style != 2) { rightX = rightY = 0; return 0; }
    rightX = std::clamp(x, -85, 85); rightY = std::clamp(y, -85, 85);
    return 1;
}
extern "C" uint32_t TouchHud_RightStick(int8_t* x, int8_t* y) {
    if (!active || (state.load() & 1)) return 0;
    int style = CVarGetInteger(CVAR_SETTING("TouchControls.Style"), 0);
    if (style != 1 && style != 2) return 0;
    const auto result = TouchHud::RouteRightStick(style, (state.load() & 128) != 0,
        CVarGetInteger(CVAR_SETTING("CustomOcarina.RightStick"), 0),
        CVarGetInteger(CVAR_SETTING("FreeLook.Enabled"), 0),
        CVarGetInteger(CVAR_SETTING("TouchControls.GameCubeStickCamera"), 0), rightX.load(), rightY.load());
    // An idle touch stick must not erase a connected controller's input.
    if (result.x != 0 || result.y != 0) { *x = result.x; *y = result.y; }
    return result.buttons;
}
extern "C" void TouchHud_Reset() { Reset(); active = false; }
extern "C" void TouchHud_SetLayout(const float* values, int count, int visible, int useNaviIcon) {
    if (!visible) { active = false; return; }
    if (values == nullptr || count != 30) { active = false; return; }
    std::lock_guard lock(layoutMutex);
    for (int i = 0; i < 10; ++i) anchors[i] = {values[i*3], values[i*3+1], values[i*3+2]};
    naviUtilityIcon = useNaviIcon;
    active = true;
}
#ifdef __ANDROID__
extern "C" JNIEXPORT jboolean JNICALL Java_com_dishii_soh_MainActivity_integratedRightStick(JNIEnv*, jobject, jint x, jint y) {
    return TouchHud_SetRightStick(x, y);
}
extern "C" JNIEXPORT jint JNICALL Java_com_dishii_soh_MainActivity_integratedTouchState(JNIEnv*, jobject) {
    return TouchHud_GetState();
}
extern "C" JNIEXPORT jintArray JNICALL Java_com_dishii_soh_MainActivity_integratedTouchBindings(JNIEnv* env, jobject, jint style) {
    std::array<int32_t, TouchHud::BindingCount> bindings;
    TouchHud_GetBindings(style, bindings.data(), bindings.size());
    const auto result = env->NewIntArray(bindings.size());
    if (result) env->SetIntArrayRegion(result, 0, bindings.size(), bindings.data());
    return result;
}
extern "C" JNIEXPORT void JNICALL Java_com_dishii_soh_MainActivity_integratedTouchButton(JNIEnv*, jobject, jint mask, jboolean down) {
    TouchHud_SetButton(static_cast<uint32_t>(mask), down);
}
extern "C" JNIEXPORT void JNICALL Java_com_dishii_soh_MainActivity_integratedTouchStick(JNIEnv*, jobject, jint x, jint y) {
    TouchHud_SetStick(x, y);
}
extern "C" JNIEXPORT void JNICALL Java_com_dishii_soh_MainActivity_integratedTouchReset(JNIEnv*, jobject) { TouchHud_Reset(); }
extern "C" JNIEXPORT void JNICALL Java_com_dishii_soh_MainActivity_integratedTouchLayout(JNIEnv* env, jobject, jfloatArray values, jboolean visible, jboolean useNaviIcon) {
    if (!visible || !values || env->GetArrayLength(values) != 30) {
        TouchHud_SetLayout(nullptr, 0, false, false);
        return;
    }
    std::array<float, 30> data;
    env->GetFloatArrayRegion(values, 0, data.size(), data.data());
    if (env->ExceptionCheck()) { TouchHud_SetLayout(nullptr, 0, false, false); return; }
    TouchHud_SetLayout(data.data(), data.size(), visible, useNaviIcon);
}
#endif
extern "C" int TouchHud_NaviUtilityIcon() { return TouchHud_IsActive() && naviUtilityIcon; }
extern "C" int TouchHud_IsActive() { return active && !(state.load() & 1); }
extern "C" void TouchHud_MarkContent(int slot) {
    if (TouchHud_IsActive() && slot >= 0 && slot < 10) drawnContent.fetch_or(1u << slot);
}
extern "C" int TouchHud_ItemHidden(int slot) {
    if (!TouchHud_IsActive() || slot < 0 || slot >= 10) return false;
    std::lock_guard lock(layoutMutex);
    return anchors[slot].size == 0;
}
extern "C" int TouchHud_ItemRect(int slot, int16_t* x, int16_t* y, int16_t* size) {
    if (!TouchHud_IsActive() || slot < 0 || slot >= 10) return false;
    std::lock_guard lock(layoutMutex);
    if (!TouchHud::Valid(anchors[slot])) return false;
    const auto rect = TouchHud::Project(anchors[slot], Ship::Context::GetRawInstance()->GetWindow()->GetAspectRatio());
    *x = rect.x; *y = rect.y; *size = rect.size;
    return true;
}
extern "C" uint32_t TouchHud_Buttons() {
    if (!active || (state.load() & 1)) { Reset(); return 0; }
    mapPressed = pendingMap.exchange(false);
    naviPressed = pendingNavi.exchange(false);
    return TouchHud::OcarinaButtons(held.load() | pending.exchange(0), (state.load() & 128) != 0,
                                   CVarGetInteger(CVAR_SETTING("CustomOcarina.Enabled"), 0) != 0);
}
extern "C" int TouchHud_MapPressed() { return TouchHud_IsActive() && mapPressed.exchange(false); }
extern "C" int TouchHud_NaviPressed() { return TouchHud_IsActive() && naviPressed.exchange(false); }
extern "C" void TouchHud_Stick(int8_t* x, int8_t* y) {
    if (!active || (state.load() & 1)) return;
    if (stickX != 0 || stickY != 0) { *x = stickX; *y = stickY; }
}
#else
extern "C" int TouchHud_GetState() { return 0; }
extern "C" int TouchHud_GetBindings(int, int32_t*, int) { return 0; }
extern "C" void TouchHud_SetButton(uint32_t, int) { }
extern "C" void TouchHud_SetStick(int, int) { }
extern "C" void TouchHud_Reset() { }
extern "C" void TouchHud_SetLayout(const float*, int, int, int) { }
extern "C" int TouchHud_IsActive() { return 0; }
extern "C" void TouchHud_MarkContent(int) { }
extern "C" int TouchHud_MapPressed() { return 0; }
extern "C" int TouchHud_NaviUtilityIcon() { return 0; }
extern "C" int TouchHud_NaviPressed() { return 0; }
extern "C" int TouchHud_ItemHidden(int) { return 0; }
extern "C" int TouchHud_ItemRect(int, int16_t*, int16_t*, int16_t*) { return 0; }
extern "C" uint32_t TouchHud_Buttons() { return 0; }
extern "C" int TouchHud_SetRightStick(int, int) { return 0; }
extern "C" uint32_t TouchHud_RightStick(int8_t*, int8_t*) { return 0; }
extern "C" void TouchHud_Stick(int8_t*, int8_t*) { }
#endif
