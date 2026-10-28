#pragma once
#include <array>
#include <string>
#include "soh/cvar_prefixes.h"

namespace TouchHud {
// Kept in sync with Android's TouchBindings. These are game actions, not SDL
// controller bindings; changing them must never edit ControlDeck mappings.
enum Action { Disabled, ActionA, SwordB, Target, Shield, Navi, ItemLeft, ItemDown,
              ItemRight, ExtraL, FirstPerson, Pause, DpadUp, DpadDown, DpadLeft, DpadRight, ToggleMap, ManualJump,
              Modifier1, Modifier2, ActionCount };
constexpr int BindingCount = 16;
inline constexpr std::array<const char*, BindingCount> Keys = {
    "a", "b", "cl", "cd", "cr", "cu", "z", "l", "r", "du", "dd", "dl", "dr", "start", "fairy", "map"
};
inline constexpr std::array<int, BindingCount> DefaultActions = {
    ActionA, SwordB, ItemLeft, ItemDown, ItemRight, Navi, Target, ExtraL, Shield,
    DpadUp, DpadDown, DpadLeft, DpadRight, Pause, Disabled, Disabled
};
inline int DefaultAction(int style, int index) {
    if ((style == 1 || style == 3) && index == 15) return ToggleMap;
    if (style == 2) {
        if (index == 5 || index == 7) return Disabled;
        if (index == 14) return Navi;
        if (index == 15) return ToggleMap;
    }
    return DefaultActions.at(index);
}
inline const char* BindingCvar(int style, int index) {
    static const auto paths = [] {
        std::array<std::array<std::string, BindingCount>, 4> result;
        for (int s = 0; s < 4; ++s) for (int i = 0; i < BindingCount; ++i)
            result[s][i] = std::string(CVAR_SETTING("TouchControls.Bindings.")) + std::to_string(s) + "." + Keys[i];
        return result;
    }();
    return paths.at(style).at(index).c_str();
}
inline int JumpIndex(int style, int choice) {
    if (style < 1 || style > 3 || choice < 1 || choice > 3) return -1;
    constexpr int indices[3][3] = {{2,3,4}, {4,2,3}, {2,3,4}};
    return indices[style-1][choice-1];
}
inline const char* JumpCvar(int style) {
    static const std::array<std::string,4> paths = {
        CVAR_SETTING("TouchControls.JumpButton.0"), CVAR_SETTING("TouchControls.JumpButton.1"),
        CVAR_SETTING("TouchControls.JumpButton.2"), CVAR_SETTING("TouchControls.JumpButton.3")
    };
    return paths.at(style).c_str();
}
}
