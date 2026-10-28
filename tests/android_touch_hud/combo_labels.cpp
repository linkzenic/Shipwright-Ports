#include "../../soh/soh/SohGui/UIComboLabel.h"
#include <cassert>
int main() {
    using UIWidgets::ComboLabelVisible;
    assert(ComboLabelVisible("X"));
    assert(ComboLabelVisible("Y"));
    assert(ComboLabelVisible("Z"));
    assert(ComboLabelVisible("Off"));
    assert(ComboLabelVisible("C-left"));
    assert(!ComboLabelVisible(nullptr));
    assert(!ComboLabelVisible(""));
    assert(!ComboLabelVisible(" "));
    assert(!ComboLabelVisible(" \t\r\n"));
}
