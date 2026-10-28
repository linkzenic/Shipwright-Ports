#define CVAR_PREFIX_SETTING "gSettings"
#include "../../soh/soh/Enhancements/controls/TouchHudBindings.h"
#include <cassert>
#include <set>
int main() {
    using namespace TouchHud;
    assert(BindingCount == 16 && Navi == 5 && ToggleMap == 16);
    assert(ManualJump == 17);
    assert(Modifier1 == 18 && Modifier2 == 19);
    assert(JumpIndex(2,1) == 4 && JumpIndex(2,2) == 2 && JumpIndex(2,3) == 3);
    assert(JumpIndex(1,1) == 2 && JumpIndex(3,3) == 4);
    assert(JumpIndex(2,0) == -1 && JumpIndex(0,1) == -1 && JumpIndex(2,99) == -1);
    assert(std::string(JumpCvar(1)) != JumpCvar(2));
    assert(DefaultAction(2,5) == Disabled && DefaultAction(2,7) == Disabled);
    assert(DefaultAction(2,14) == Navi && DefaultAction(2,15) == ToggleMap);
    assert(DefaultAction(1,15) == ToggleMap && DefaultAction(1,14) == Disabled);
    assert(DefaultAction(3,15) == ToggleMap);
    assert(DefaultAction(2,2) == ItemLeft && DefaultAction(2,3) == ItemDown && DefaultAction(2,4) == ItemRight);
    for (int style=1; style<=3; ++style) {
        std::set<int> actions;
        for (int i=0; i<BindingCount; ++i) {
            int action = DefaultAction(style,i);
            assert(action >= Disabled && action < ActionCount);
            if (action != Disabled) assert(actions.insert(action).second);
        }
    }
    assert(std::string(BindingCvar(2,14)) == "gSettings.TouchControls.Bindings.2.fairy");
    assert(std::string(BindingCvar(1,0)) != BindingCvar(2,0));
}
