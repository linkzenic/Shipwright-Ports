#include "../../soh/soh/Enhancements/controls/TouchHudGeometry.h"
#include <cassert>
#include <limits>
int main() {
    using namespace TouchHud;
    assert(Valid({.5f,.5f,.1f}));
    assert(!Valid({.5f,.5f,0}));
    assert(!Valid({-1,.5f,.1f}));
    assert(!Valid({.5f,2,.1f}));
    assert(!Valid({std::numeric_limits<float>::quiet_NaN(),.5f,.1f}));
    auto center = Project({.5f,.5f,.1f},16.f/9);
    assert(center.x == 148 && center.y == 108 && center.size == 24);
    auto wide = Project({.9f,.8f,.1f},16.f/9);
    auto standard = Project({.9f,.8f,.1f},4.f/3);
    assert(wide.x == 319 && standard.x == 276 && wide.y == standard.y);
    assert(Project({.5f,.5f,.001f},16.f/9).size == 8);
}
