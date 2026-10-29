#define CVAR_PREFIX_SETTING "gSettings"
#include "../../soh/soh/Enhancements/controls/TouchHudLayout.h"
#include <cassert>
#include <limits>
int main() {
    using namespace TouchHud;
    assert(ActionMask(Navi)==0x20000 && ActionMask(Navi,true)==8);
    assert(ActionMask(Modifier1)==0x40 && ActionMask(Modifier2)==0x80);
    assert(ActionMask(ManualJump)==0x01000000 && ActionSlot(ManualJump)==-1);
    Placement p;Layout gc,modern,n64;std::array<int32_t,BindingCount> b;
    auto build=[&](Layout& l,int style,int state=0,bool edit=false) {
        for(int i=0;i<BindingCount;i++)b[i]=DefaultAction(style,i);
        l.build(style,844,390,{47,0,47,21},1,state,edit,true,p,b);
    };
    build(gc,2);build(modern,3);build(n64,1);
    for(auto key:{"settings","start","map"}) {
        assert(gc.find(key)&&modern.find(key));
        auto a=gc.find(key)->bounds,c=modern.find(key)->bounds;
        assert(a.x==c.x&&a.y==c.y&&a.w==c.w&&a.h==c.h);
    }
    assert(!n64.find("look")&&!n64.find("map"));
    build(n64,1,16|32);assert(n64.find("look")&&n64.find("map"));
    assert(gc.find("fairy")&&!gc.find("cu"));assert(modern.find("cu")&&!modern.find("fairy"));
    assert(std::abs(gc.find("cr")->bounds.cx()-gc.find("cl")->bounds.cx()-96)<.01f);
    p.show("pad",false);assert(!p.visible("pad"));p.show("du",true);assert(p.visible("pad"));
    p.show("settings",false);p.show("eye",false);assert(p.visible("settings")&&p.visible("eye"));
    p.set("a",.3,.4,1.2);auto saved=p;p.set("a",.8,.8,1);p=saved;
    assert(p.positions["a"][0]==.3f);p.set("a",std::numeric_limits<float>::quiet_NaN(),0,1);
    assert(p.positions["a"][0]==.3f);
    assert(ResizedScale(1,80,40,160,80)==2);assert(ResizedScale(1,80,40,10,5)==.5);
    for(int style=1;style<=3;style++)for(auto size:{std::array<float,2>{568,320},{844,390},{1024,768}}) {
        for(int i=0;i<BindingCount;i++)b[i]=DefaultAction(style,i);
        b[13]=Disabled;Layout l;l.build(style,size[0],size[1],{20,0,20,20},1.5,16|32,false,true,p,b);
        for(auto& c:l.controls)assert(c.bounds.w>0&&c.bounds.h>0&&c.bounds.x>=0&&c.bounds.y>=0&&
            c.bounds.x+c.bounds.w<=size[0]+.01&&c.bounds.y+c.bounds.h<=size[1]+.01);
    }
}
