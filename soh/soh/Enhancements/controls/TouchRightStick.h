#pragma once
#include <cstdint>

namespace TouchHud {
struct RightStickResult {
    uint32_t buttons = 0;
    int8_t x = 0, y = 0;
};
inline RightStickResult RouteRightStick(int style, bool playing, bool ocarinaStick,
                                       bool freeCamera, bool gameCubeCamera, int8_t x, int8_t y) {
    if (style != 1 && style != 2) return {};
    if (playing) return style == 2 && ocarinaStick ? RightStickResult{0, x, y} : RightStickResult{};
    if (style == 1 || gameCubeCamera) return freeCamera ? RightStickResult{0, x, y} : RightStickResult{};
    return {(x > 42 ? 1u : x < -42 ? 2u : 0u) | (y > 42 ? 8u : y < -42 ? 4u : 0u), 0, 0};
}
}
