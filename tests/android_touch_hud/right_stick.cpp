#include "soh/soh/Enhancements/controls/TouchRightStick.h"
#include <cassert>
#include <initializer_list>
int main() {
    for (int style = 0; style <= 3; ++style)
    for (bool playing : {false, true})
    for (bool notes : {false, true})
    for (bool camera : {false, true})
    for (bool gcCamera : {false, true}) {
        const auto r = TouchHud::RouteRightStick(style, playing, notes, camera, gcCamera, 85, -85);
        const bool owned = style == 1 || style == 2;
        const bool axes = owned && (playing ? style == 2 && notes : camera && (style == 1 || gcCamera));
        const bool buttons = style == 2 && !playing && !gcCamera;
        assert(r.x == (axes ? 85 : 0));
        assert(r.y == (axes ? -85 : 0));
        assert(r.buttons == (buttons ? 5u : 0u));
        assert(!(r.buttons && (r.x || r.y)));
    }
    assert(TouchHud::RouteRightStick(2, false, false, false, false, 42, -42).buttons == 0);
    assert(TouchHud::RouteRightStick(2, false, false, false, false, -85, 85).buttons == 10);
}
