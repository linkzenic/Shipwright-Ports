#pragma once
#include <cstdint>
#include <algorithm>
#include <cmath>

namespace TouchHud {
struct Anchor { float x = 0, y = 0, size = 0; };
struct Rect { int16_t x, y, size; };
inline bool Valid(const Anchor& a) {
    return std::isfinite(a.x) && std::isfinite(a.y) && std::isfinite(a.size) &&
           a.x >= 0 && a.x <= 1 && a.y >= 0 && a.y <= 1 && a.size > 0 && a.size <= .5f;
}
inline Rect Project(const Anchor& a, float aspect) {
    // Same 320x240-centered widescreen coordinates as SOH's native HUD.
    const float width = 240.f * aspect;
    const int16_t size = std::clamp<int>(std::lround(a.size * 240.f), 8, 120);
    return {static_cast<int16_t>(std::lround(160.f + (a.x - .5f) * width - size * .5f)),
            static_cast<int16_t>(std::lround(a.y * 240.f - size * .5f)), size};
}
}
