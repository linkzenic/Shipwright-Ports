#include "TouchHud.h"
#ifdef __ANDROID__
#include "TouchHudGeometry.h"
#include "TouchHudBindings.h"
#include "soh/ShipInit.hpp"
#include "soh/OTRGlobals.h"
#include "soh/Enhancements/game-interactor/GameInteractor.h"
#include <ship/Context.h>
#include <libultraship/bridge/consolevariablebridge.h>
#include <ship/window/Window.h>
#include <ship/window/gui/Gui.h>
#include <jni.h>
#include <atomic>
#include <array>
#include <mutex>
extern "C" {
#include "functions.h"
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
std::mutex layoutMutex;
std::array<TouchHud::Anchor, 10> anchors;
void Reset() { held = pending = 0; pendingMap = mapPressed = pendingNavi = naviPressed = false; stickX = stickY = 0; }
bool ManualJumpActive() {
    return CVarGetInteger(CVAR_ENHANCEMENT("ManualJump"), 0) &&
           !CVarGetInteger(CVAR_SETTING("DisableChanges"), 0);
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
                   (gPlayState && gPlayState->pauseCtx.state != 0 ? 64 : 0);
        const auto content = drawnContent.exchange(0);
        if (!menu && active && gPlayState != nullptr) next |= content << 8;
        state = next;
        if (menu) Reset();
    });
}
RegisterShipInitFunc init(Init);
}
extern "C" JNIEXPORT jint JNICALL Java_com_dishii_soh_MainActivity_integratedTouchState(JNIEnv*, jobject) { return state; }
extern "C" JNIEXPORT jintArray JNICALL Java_com_dishii_soh_MainActivity_integratedTouchBindings(JNIEnv* env, jobject, jint style) {
    style = std::clamp<int>(style, 0, 3);
    const auto context = Ship::Context::GetRawInstance();
    const bool settingsReady = context && context->GetConsoleVariables();
    std::array<jint, TouchHud::BindingCount> bindings;
    for (int i=0; i<TouchHud::BindingCount; ++i) {
        int action = settingsReady ? CVarGetInteger(TouchHud::BindingCvar(style, i), TouchHud::DefaultAction(style, i))
                                   : TouchHud::DefaultAction(style, i);
        bindings[i] = action >= 0 && action < TouchHud::ActionCount ? action : TouchHud::DefaultAction(style, i);
    }
    if (settingsReady && ManualJumpActive() && !(gPlayState && gPlayState->pauseCtx.state != 0)) {
        int index = TouchHud::JumpIndex(style, CVarGetInteger(TouchHud::JumpCvar(style), 0));
        if (index >= 0) bindings[index] = TouchHud::ManualJump;
    }
    auto result = env->NewIntArray(bindings.size());
    if (result) env->SetIntArrayRegion(result, 0, bindings.size(), bindings.data());
    return result;
}
extern "C" JNIEXPORT void JNICALL Java_com_dishii_soh_MainActivity_integratedTouchButton(JNIEnv*, jobject, jint mask, jboolean down) {
    // A semantic map action must not send N64 L: that may also answer Navi.
    if (mask == 0x10000) { if (down) pendingMap = true; return; }
    if (mask == 0x20000) { if (down) pendingNavi = true; return; }
    if (down) { held.fetch_or(mask); pending.fetch_or(mask); }
    else held.fetch_and(~static_cast<uint32_t>(mask));
}
extern "C" JNIEXPORT void JNICALL Java_com_dishii_soh_MainActivity_integratedTouchStick(JNIEnv*, jobject, jint x, jint y) {
    stickX = std::clamp(x, -85, 85); stickY = std::clamp(y, -85, 85);
}
extern "C" JNIEXPORT void JNICALL Java_com_dishii_soh_MainActivity_integratedTouchReset(JNIEnv*, jobject) { Reset(); active = false; }
extern "C" JNIEXPORT void JNICALL Java_com_dishii_soh_MainActivity_integratedTouchLayout(JNIEnv* env, jobject, jfloatArray values, jboolean visible, jboolean useNaviIcon) {
    if (!visible) { active = false; return; }
    if (values == nullptr || env->GetArrayLength(values) != 30) { active = false; return; }
    std::array<float, 30> data;
    env->GetFloatArrayRegion(values, 0, data.size(), data.data());
    if (env->ExceptionCheck()) { active = false; return; }
    std::lock_guard lock(layoutMutex);
    for (int i = 0; i < 10; ++i) anchors[i] = {data[i*3], data[i*3+1], data[i*3+2]};
    naviUtilityIcon = useNaviIcon;
    active = true;
}
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
    return held.load() | pending.exchange(0);
}
extern "C" int TouchHud_MapPressed() { return TouchHud_IsActive() && mapPressed.exchange(false); }
extern "C" int TouchHud_NaviPressed() { return TouchHud_IsActive() && naviPressed.exchange(false); }
extern "C" void TouchHud_Stick(int8_t* x, int8_t* y) {
    if (!active || (state.load() & 1)) return;
    if (stickX != 0 || stickY != 0) { *x = stickX; *y = stickY; }
}
#else
extern "C" int TouchHud_IsActive() { return 0; }
extern "C" void TouchHud_MarkContent(int) { }
extern "C" int TouchHud_MapPressed() { return 0; }
extern "C" int TouchHud_NaviUtilityIcon() { return 0; }
extern "C" int TouchHud_NaviPressed() { return 0; }
extern "C" int TouchHud_ItemHidden(int) { return 0; }
extern "C" int TouchHud_ItemRect(int, int16_t*, int16_t*, int16_t*) { return 0; }
extern "C" uint32_t TouchHud_Buttons() { return 0; }
extern "C" void TouchHud_Stick(int8_t*, int8_t*) { }
#endif
