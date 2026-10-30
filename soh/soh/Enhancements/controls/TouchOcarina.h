#pragma once
#include <cstdint>

namespace TouchHud {
// Translate only touch input; never reinterpret physical-controller bindings.
inline uint32_t OcarinaButtons(uint32_t buttons, bool playing, bool custom) {
    if (!playing || !custom) return buttons;
    constexpr uint32_t source[] = {0x8000, 4, 1, 2, 8, 0x20, 0x10, 0x2000};
    constexpr uint32_t target[] = {0x10000, 0x20000, 0x40000, 0x80000,
                                   0x100000, 0x200000, 0x400000, 0x800000};
    for (int i = 0; i < 8; ++i) if (buttons & source[i]) buttons |= target[i];
    return buttons;
}
}
