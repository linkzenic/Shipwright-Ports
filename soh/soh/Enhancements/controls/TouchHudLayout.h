#pragma once
#include "TouchHudBindings.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace TouchHud {
struct Bounds {
    float x, y, w, h;
    float cx() const { return x+w/2; }
    float cy() const { return y+h/2; }
    bool contains(float px, float py) const { return px>=x && py>=y && px<=x+w && py<=y+h; }
};
struct Placement {
    std::map<std::string,std::array<float,3>> positions;
    std::set<std::string> hidden;
    bool visible(const std::string& key) const {
        if(key=="pad") return visible("du") || visible("dd") || visible("dl") || visible("dr");
        return !hidden.contains(key);
    }
    void show(const std::string& key, bool value) {
        if(key=="settings" || key=="eye") return;
        if(key=="pad") { for(auto k:{"du","dd","dl","dr"}) show(k,value); return; }
        if(value) hidden.erase(key); else hidden.insert(key);
    }
    void set(const std::string& key,float x,float y,float scale) {
        if(!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(scale)) return;
        positions[key]={std::clamp(x,0.f,1.f),std::clamp(y,0.f,1.f),std::clamp(scale,.5f,2.f)};
    }
};
struct Control {
    std::string key,label;
    uint32_t mask,color;
    int slot,stick;
    Bounds bounds;
    float cx=0,cy=0,dx=0,dy=0;
};
inline bool DpadDirection(const std::string& key) { return key=="du"||key=="dd"||key=="dl"||key=="dr"; }
inline float ResizedScale(float original,float w,float h,float requestedW,float requestedH) {
    if(!std::isfinite(original)||!std::isfinite(requestedW)||!std::isfinite(requestedH)||w<=0||h<=0) return 1;
    return std::clamp(original*(requestedW*w+requestedH*h)/(w*w+h*h),.5f,2.f);
}
struct Layout {
    std::vector<Control> controls;
    float unit=1,left=0,right=0,top=0,bottom=0,width=0,height=0;
    Control* find(const std::string& key) { for(auto& c:controls) if(c.key==key) return &c; return nullptr; }
    void build(int style,float w,float h,std::array<float,4> safe,float scale,int state,bool editing,
               bool shown,const Placement& placement,const std::array<int32_t,BindingCount>& bindings) {
        controls.clear(); width=w; height=h;
        if(style<1||style>3||w<=0||h<=0) return;
        unit=std::clamp(scale,.75f,1.5f)*std::clamp(h/390.f,.82f,1.35f);
        left=safe[0]+(style==3?16:12)*unit; top=safe[1]+(style==3?16:12)*unit;
        right=safe[2]+(style==3?16:12)*unit; bottom=safe[3]+(style==3?16:12)*unit;
        constexpr uint32_t gray=0x626b78,yellow=0xdfb52b;
        auto add=[&](std::string key,std::string label,float x,float y,float bw,float bh,uint32_t color=0x626b78,int stick=-1) {
            uint32_t mask=0; int slot=-1;
            for(int i=0;i<BindingCount;i++) if(key==Keys[i]) {
                const int action=bindings[i]; if(action==Disabled&&!editing) return;
                mask=ActionMask(action,state&64); slot=ActionSlot(action);
                if(key=="fairy"&&action!=Navi) label="Item";
            }
            auto p=placement.positions.find(key);
            if(style==3&&DpadDirection(key)) p=placement.positions.end();
            float s=p==placement.positions.end()?1:p->second[2];
            float adjust=style==3&&(key=="settings"||key=="start"||key=="map"||key=="cu")?4*unit:0;
            float ww=std::min(bw*unit*s,w-left-right+2*adjust),hh=std::min(bh*unit*s,h-top-bottom+2*adjust);
            float cx=p==placement.positions.end()?x*w:p->second[0]*w,cy=p==placement.positions.end()?y*h:p->second[1]*h;
            cx=std::clamp(cx,left-adjust+ww/2,w-right+adjust-ww/2);
            cy=std::clamp(cy,top-adjust+hh/2,h-bottom+adjust-hh/2);
            controls.push_back({key,label,mask,color,slot,stick,{cx-ww/2,cy-hh/2,ww,hh},cx,cy});
        };
        auto face=[&](const char* key,const char* label,float x,float y,float size,uint32_t color){add(key,label,x,y,size,size,color);};
        if(shown||editing) {
            if(style==1) {
                face("a","A",.79,.80,52,0x346bcc);face("b","B",.70,.69,44,0x38a05f);
                // Keep the whole diamond inside the safe area. Independent
                // percentage offsets distort spacing on wide phone screens.
                float ccx=w-right-64*unit,ccy=.54f*h,step=46*unit;
                face("cl","◀",(ccx-step)/w,ccy/h,36,yellow);
                face("cd","▼",ccx/w,(ccy+step)/h,36,yellow);
                face("cr","▶",(ccx+step)/w,ccy/h,36,yellow);
                face("cu","▲",ccx/w,(ccy-step)/h,36,yellow);
                add("z","Z",.10,.13,64,32);add("l","L",.10,.25,64,30);add("r","R",.90,.13,64,32);
            } else if(style==2) {
                auto dock=[&](const char* k,const char* label,float ro,float bo,float size,uint32_t color){face(k,label,(w-safe[2]-(ro+size/2)*unit)/w,(h-(bo+size/2)*unit)/h,size,color);};
                dock("a","A",62,64,74,0x22707b);dock("b","B",158,48,58,0xa13d42);
                dock("cl","Y",124,138,58,0x715b96);dock("cr","X",28,144,58,0x537397);
                float rx=(w-safe[2]-63*unit)/w;
                add("cd","Z",rx,95*unit/h,78,46,0x764f9e);face("cu","C↑",.69,.47,28,yellow);
                add("z","L",(safe[0]+63*unit)/w,41*unit/h,78,46);add("r","R",rx,41*unit/h,78,46);
                add("l","Extra",.10,.25,52,27);
            } else {
                float fx=w-right-93*unit,fy=h-bottom-93*unit;
                face("a","A",(fx+44*unit)/w,fy/h,44,0x426e54);face("b","B",fx/w,(fy+44*unit)/h,44,0x85535b);
                face("cl","X",fx/w,(fy-44*unit)/h,44,0x4d6d91);face("cd","Y",(fx-44*unit)/w,fy/h,44,0x918157);
                float lx=(left+31.5f*unit)/w,rx=(w-right-31.5f*unit)/w;
                add("z","ZL",lx,(top+17.25f*unit)/h,63,34.5f);add("l","L",lx,(top+61.75f*unit)/h,63,34.5f);
                add("cr","ZR",rx,(top+17.25f*unit)/h,63,34.5f);add("r","R",rx,(top+61.75f*unit)/h,63,34.5f);
            }
            if(style==3) {
                float pt=std::max(top+114*unit,h-bottom-252*unit);
                add("pad","D-pad",(left+48*unit)/w,(pt+48*unit)/h,96,96);
                auto b=find("pad")->bounds;float arm=b.w/3;
                face("du","▲",b.cx()/w,(b.y+arm/2)/h,arm/unit,gray);face("dd","▼",b.cx()/w,(b.y+b.h-arm/2)/h,arm/unit,gray);
                face("dl","◀",(b.x+arm/2)/w,b.cy()/h,arm/unit,gray);face("dr","▶",(b.x+b.w-arm/2)/w,b.cy()/h,arm/unit,gray);
            } else {
                float dcx=left+46*unit,dcy=.51f*h,step=32*unit;
                face("du","▲",dcx/w,(dcy-step)/h,28,gray);
                face("dd","▼",dcx/w,(dcy+step)/h,28,gray);
                face("dl","◀",(dcx-step)/w,dcy/h,28,gray);
                face("dr","▶",(dcx+step)/w,dcy/h,28,gray);
            }
            add("start","Start",.54,.91,66,28);add("settings","Settings",.42,.91,72,28);
            if(style==2||style==3||(style==1&&(state&32))) {
                auto start=find("start"),settings=find("settings");
                float gap=start&&settings?std::max(8*unit,start->bounds.x-(settings->bounds.x+settings->bounds.w)):8*unit;
                float mapX=start?(start->bounds.x+start->bounds.w+gap+18*unit)/w:.63f,mapY=start?start->bounds.cy()/h:.91f;
                float fairyX=settings?(settings->bounds.x-gap-18*unit)/w:.28f,fairyY=settings?settings->bounds.cy()/h:.91f;
                add("map","Map",mapX,mapY,36,28);
                if(style==2||style==3) add(style==3?"cu":"fairy","Fairy",fairyX,fairyY,36,28);
            }
            add("move","Move",style==3?(left+75*unit)/w:.15f,style==3?(h-bottom-75*unit)/h:.80f,style==3?150:132,style==3?150:132,gray,0);
            if(style!=1||editing||(state&16)) add("look","Look",style==3?.62f:.59f,style==3?.62f:.69f,style==3?150:120,style==3?150:120,gray,1);
        }
        face("eye","◉",style==3?(w-right-15*unit)/w:.95f,style==3?(h-bottom-15*unit)/h:.92f,style==3?30:28,gray);
    }
};
}
