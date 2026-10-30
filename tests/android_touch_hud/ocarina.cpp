#include "soh/soh/Enhancements/controls/TouchOcarina.h"
#include <cassert>
int main() {
    constexpr uint32_t notes[] = {0x8000, 4, 1, 2, 8};
    for (int i = 0; i < 5; ++i) {
        assert(TouchHud::OcarinaButtons(notes[i], true, true) == (notes[i] | (0x10000u << i)));
        assert(TouchHud::OcarinaButtons(notes[i], true, false) == notes[i]);
        assert(TouchHud::OcarinaButtons(notes[i], false, true) == notes[i]);
    }
    assert(TouchHud::OcarinaButtons(0, true, true) == 0);
    assert(TouchHud::OcarinaButtons(0x4000, true, true) == 0x4000); // Cancel remains B.
    assert(TouchHud::OcarinaButtons(0x8005, true, true) == 0x78005);
}
