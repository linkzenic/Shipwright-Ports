#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#include "SOHiOSTouchControls.h"
#include "soh/Enhancements/controls/TouchHud.h"
#include "soh/Enhancements/controls/TouchHudLayout.h"
#include <atomic>

namespace {
std::atomic<int> requestedStyle{0};
struct Config { int style=0; float scale=1,opacity=.55f; bool left=true,right=true,transparent=false; };
Config current;
CGRect TouchRect(TouchHud::Bounds b) { return CGRectMake(b.x,b.y,b.w,b.h); }
UIColor* Color(uint32_t rgb,CGFloat alpha=1) {
    return [UIColor colorWithRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:alpha];
}
NSString* Text(const std::string& s) { return [NSString stringWithUTF8String:s.c_str()]; }
NSString* LayoutKey(int style) { return [NSString stringWithFormat:@"SOHIntegratedTouchLayout.%d",style]; }
TouchHud::Placement Load(int style) {
    TouchHud::Placement result;
    id data=[NSUserDefaults.standardUserDefaults objectForKey:LayoutKey(style)];
    if(![data isKindOfClass:NSDictionary.class] || [data count]>64) return result;
    for(id key in data) {
        if(![key isKindOfClass:NSString.class] || [key length]>16) continue;
        id value=data[key];
        if(![value isKindOfClass:NSArray.class] || [value count]!=4) continue;
        bool valid=true;for(id n in value) if(![n isKindOfClass:NSNumber.class]) valid=false;
        if(!valid) continue;
        std::string k=[key UTF8String];
        if([value[0] floatValue]>=0 && [value[1] floatValue]>=0)
            result.set(k,[value[0] floatValue],[value[1] floatValue],[value[2] floatValue]);
        result.show(k,[value[3] boolValue]);
    }
    return result;
}
void Save(int style,const TouchHud::Placement& p) {
    NSMutableDictionary* data=[NSMutableDictionary dictionary];
    for(auto& [key,pos]:p.positions) data[Text(key)]=@[@(pos[0]),@(pos[1]),@(pos[2]),@(p.visible(key))];
    for(auto& key:p.hidden) if(!data[Text(key)]) data[Text(key)]=@[@(-1),@(-1),@(1),@NO];
    [NSUserDefaults.standardUserDefaults setObject:data forKey:LayoutKey(style)];
}
UIFont* TouchFont(CGFloat size) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        NSURL* url=[NSBundle.mainBundle URLForResource:@"FiraSansCondensed-Bold" withExtension:@"ttf" subdirectory:@"fonts"];
        if(url) CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url,kCTFontManagerScopeProcess,nullptr);
        url=[NSBundle.mainBundle URLForResource:@"MaterialSymbolsRounded-Regular" withExtension:@"ttf" subdirectory:@"fonts"];
        if(url) CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url,kCTFontManagerScopeProcess,nullptr);
    });
    return [UIFont fontWithName:@"FiraSansCondensed-Bold" size:size] ?: [UIFont boldSystemFontOfSize:size];
}
}

@interface SOHIntegratedTouchOverlay : UIView {
    TouchHud::Layout _layout;
    TouchHud::Placement _placement,_saved,_gestureStart;
    std::array<int32_t,TouchHud::BindingCount> _bindings;
    std::map<uintptr_t,std::string> _fingers;
    std::string _selected,_dragKey;
    uintptr_t _editorFinger;
    int _state,_corner;
    float _dragX,_dragY,_resizeX,_resizeY,_resizeW,_resizeH,_resizeScale,_fixedX,_fixedY;
    CGRect _toolbar[4];
    BOOL _editing,_shown,_suspended,_menuVisible;
    Config _config;
    CADisplayLink* _displayLink;
}
- (void)configure:(Config)config;
- (void)setMenuVisible:(BOOL)visible;
- (void)startEditing;
- (void)cancelInputs;
- (void)shutdown;
@end

@implementation SOHIntegratedTouchOverlay
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor;self.multipleTouchEnabled=YES;self.opaque=NO;
        self.accessibilityLabel=@"Integrated touch controller";
        _shown=YES;_corner=-1;
        _displayLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(suspend:)
            name:UIApplicationWillResignActiveNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resume:)
            name:UIApplicationDidBecomeActiveNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(suspend:)
            name:UISceneWillDeactivateNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resume:)
            name:UISceneDidActivateNotification object:nil];
    }
    return self;
}
- (void)shutdown { [self cancelInputs];[_displayLink invalidate];_displayLink=nil;[NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)suspend:(NSNotification*)note { if(_editing)[self finishEditing:NO];_suspended=YES;[self cancelInputs]; }
- (void)resume:(NSNotification*)note { _suspended=NO;[self rebuild]; }
- (void)configure:(Config)config {
    [self cancelInputs];
    if(_editing)[self finishEditing:NO];
    if(_config.style!=config.style) { _placement=Load(config.style);_shown=YES; }
    _config=config;
    TouchHud_GetBindings(_config.style,_bindings.data(),_bindings.size());
    [self rebuild];
}
- (void)setMenuVisible:(BOOL)visible {
    if(_menuVisible!=visible) { _menuVisible=visible;[self cancelInputs];[self rebuild]; }
}
- (void)tick:(CADisplayLink*)link {
    if(_suspended||self.hidden||!self.window) return;
    int next=TouchHud_GetState();
    if(((next^_state)&127)!=0) {
        [self cancelInputs];
        _state=next;TouchHud_GetBindings(_config.style,_bindings.data(),_bindings.size());[self rebuild];
    } else _state=next;
    [self publish];[self setNeedsDisplay];
}
- (void)layoutSubviews { [super layoutSubviews];[self cancelInputs];[self rebuild]; }
- (void)safeAreaInsetsDidChange { [super safeAreaInsetsDidChange];[self setNeedsLayout]; }
- (void)rebuild {
    UIEdgeInsets s=self.safeAreaInsets;
    _layout.build(_config.style,self.bounds.size.width,self.bounds.size.height,
        {(float)s.left,(float)s.top,(float)s.right,(float)s.bottom},_config.scale,_state,_editing,_shown,_placement,_bindings);
    float u=std::min(_layout.unit,_layout.width/500.f),gap=8*u;
    float w=std::min(90*u,(_layout.width-_layout.left-_layout.right-3*gap)/4),x=(_layout.width-4*w-3*gap)/2;
    for(int i=0;i<4;i++) _toolbar[i]=CGRectMake(x+i*(w+gap),_layout.top+32*u,w,40*u);
    [self publish];[self setNeedsDisplay];
}
- (void)publish {
    std::array<float,30> anchors{};bool navi=false;
    if(_layout.width<=0||_layout.height<=0) return;
    for(auto& c:_layout.controls) if(c.slot>=0&&_placement.visible(c.key)) {
        anchors[c.slot*3]=c.bounds.cx()/_layout.width;anchors[c.slot*3+1]=c.bounds.cy()/_layout.height;
        anchors[c.slot*3+2]=std::min(c.bounds.w,c.bounds.h)*.76f/_layout.height;
        if(c.slot==8)navi=c.key=="fairy"||c.key=="map"||(_config.style==3&&c.key=="cu");
    }
    TouchHud_SetLayout(anchors.data(),anchors.size(),_shown&&!_editing&&!_suspended&&!_menuVisible&&!(_state&1),navi);
}
- (BOOL)floating:(const TouchHud::Control&)c { return c.stick==0?_config.left:c.stick==1&&_config.right; }
- (BOOL)pressed:(const std::string&)key { for(auto& [finger,k]:_fingers)if(k==key)return YES;return NO; }
- (void)releaseControl:(TouchHud::Control&)c {
    if(c.stick==0)TouchHud_SetStick(0,0);
    else if(c.stick==1)SOHiOS_SetCameraStick(0,0);
    else if(c.mask)TouchHud_SetButton(c.mask,NO);
    c.dx=c.dy=0;
}
- (void)cancelInputs {
    for(auto& c:_layout.controls)[self releaseControl:c];
    _fingers.clear();TouchHud_Reset();SOHiOS_SetCameraStick(0,0);
}
- (void)moveStick:(TouchHud::Control&)c point:(CGPoint)p {
    float r=std::min(c.bounds.w,c.bounds.h)*.34f;
    c.dx=(p.x-c.cx)/r;c.dy=(p.y-c.cy)/r;float length=hypot(c.dx,c.dy);
    if(length>1) { c.dx/=length;c.dy/=length; }
    if(c.stick==0)TouchHud_SetStick(lround(c.dx*85),lround(-c.dy*85));
    else SOHiOS_SetCameraStick(c.dx,c.dy);
}
- (void)startEditing {
    if(_editing||_config.style==0)return;
    [self cancelInputs];_saved=_placement;_editing=YES;_selected.clear();_dragKey.clear();
    if(_menuVisible)SOHiOS_RequestMenuToggle();
    [self rebuild];UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,
        @"Drag controls to move. Select a control and drag its corner handles to resize. Save, Reset, Cancel, and Hide or Show are at the top.");
}
- (void)finishEditing:(BOOL)save {
    if(save)Save(_config.style,_placement);else _placement=_saved;
    _editing=NO;_dragKey.clear();_editorFinger=0;_corner=-1;[self cancelInputs];[self rebuild];
}
- (void)toggleSelected {
    if(_selected.empty()||_selected=="settings"||_selected=="eye")return;
    _placement.show(_selected,!_placement.visible(_selected));[self rebuild];
}
- (void)drawLabel:(NSString*)label rect:(CGRect)rect size:(CGFloat)size color:(UIColor*)color align:(NSTextAlignment)align {
    NSMutableParagraphStyle* paragraph=[NSMutableParagraphStyle new];paragraph.alignment=align;
    UIFont* font=TouchFont(size);
    [label drawInRect:rect withAttributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:paragraph}];
}
- (void)drawRect:(CGRect)rect {
    if(_suspended)return;
    CGContextRef context=UIGraphicsGetCurrentContext();float u=_layout.unit;
    if(_editing) { [Color(0x080b12,.94) setFill];UIRectFill(self.bounds); }
    if(_config.style==3&&(_shown||_editing)&&(_editing||(!(_state&1)&&!_menuVisible))&&(_editing||_placement.visible("pad"))) {
        auto pad=_layout.find("pad");if(pad) {
            CGRect b=TouchRect(pad->bounds);float arm=b.size.width/3;
            UIBezierPath* cross=[UIBezierPath bezierPath];
            const CGPoint outline[]={{1,0},{2,0},{2,1},{3,1},{3,2},{2,2},{2,3},{1,3},{1,2},{0,2},{0,1},{1,1}};
            [cross moveToPoint:CGPointMake(b.origin.x+outline[0].x*arm,b.origin.y+outline[0].y*arm)];
            for(int i=1;i<12;i++)[cross addLineToPoint:CGPointMake(b.origin.x+outline[i].x*arm,b.origin.y+outline[i].y*arm)];
            [cross closePath];cross.lineJoinStyle=kCGLineJoinRound;
            [Color(0x626b78,_editing?(_placement.visible("pad")?.7:.2):_config.opacity*.7) setFill];[cross fill];
            [Color(0x626b78,_config.opacity) setStroke];cross.lineWidth=1.5*u;[cross stroke];
        }
    }
    for(auto& c:_layout.controls) {
        if(c.key=="pad")continue;
        bool visible=_placement.visible(c.key),down=[self pressed:c.key];
        if(!_editing&&(!visible||(((_state&1)||_menuVisible)&&c.key!="settings"&&c.key!="eye")))continue;
        if(!_editing&&_config.style==1&&c.stick==1)continue;
        if(!_editing&&c.stick>=0&&[self floating:c]&&!down)continue;
        bool content=!_editing&&c.slot>=0&&(_state&(1<<(8+c.slot)));
        bool transparent=!_editing&&c.stick>=0&&(_config.transparent||[self floating:c]);
        CGRect b=TouchRect(c.bounds);bool round=c.stick>=0||fabs(c.bounds.w-c.bounds.h)<.5f;
        UIBezierPath* path=round?[UIBezierPath bezierPathWithOvalInRect:b]:[UIBezierPath bezierPathWithRoundedRect:b cornerRadius:12*u];
        if(!(_config.style==3&&TouchHud::DpadDirection(c.key))) {
            [Color(c.color,transparent?0:_editing?(visible?.74:.18):_config.opacity*(content?.12:.70)) setFill];[path fill];
            [Color(_editing&&_selected==c.key?0xffcf64:c.color,transparent?0:_editing?1:_config.opacity) setStroke];
            path.lineWidth=(_selected==c.key?3:1.5)*u;[path stroke];
        }
        if(c.stick>=0&&!_editing) {
            [UIColor.whiteColor setFill];CGRect knob=CGRectMake(c.cx+c.dx*c.bounds.w*.34f-12*u,c.cy+c.dy*c.bounds.h*.34f-12*u,24*u,24*u);
            [[UIBezierPath bezierPathWithOvalInRect:knob] fill];continue;
        }
        bool utility=(c.key=="fairy"||c.key=="map"||(_config.style==3&&c.key=="cu"))&&(c.slot==8||c.mask==0x10000);
        if(utility) {
            UIFont* icons=[UIFont fontWithName:@"MaterialSymbolsRounded-Regular" size:std::min(c.bounds.w,c.bounds.h)*.72f];
            NSString* glyph=c.slot==8?@"\ue65f":@"\ue55b";
            if(!icons) { glyph=c.slot==8?@"✦":@"▧";icons=TouchFont(std::min(c.bounds.w,c.bounds.h)*.72f); }
            CGSize size=[glyph sizeWithAttributes:@{NSFontAttributeName:icons}];
            [glyph drawAtPoint:CGPointMake(CGRectGetMidX(b)-size.width/2,CGRectGetMidY(b)-size.height/2)
                withAttributes:@{NSFontAttributeName:icons,NSForegroundColorAttributeName:content?Color(0xffdf79):UIColor.whiteColor}];
            continue;
        }
        float bs=std::min(c.bounds.w,c.bounds.h)/((c.key=="a"&&_config.style==2?74:58)*u);
        bool letter=(c.slot>=0||c.mask==0x01000000)&&Text(c.label).length==1;
        float size=(letter?(content?13:c.key=="a"&&_config.style==2?31:24)*bs:13)*u;
        NSString* label=Text(c.label);
        if(c.label=="◀")label=@"◀\uFE0E";
        if(c.label=="▶")label=@"▶\uFE0E";
        if(_editing&&!visible)label=[label stringByAppendingString:@" (off)"];
        CGFloat line=TouchFont(size).lineHeight;
        CGRect text=content?CGRectMake(b.origin.x,b.origin.y+b.size.height-6*u*bs-line,b.size.width-6*u*bs,line+2):
            CGRectMake(b.origin.x,CGRectGetMidY(b)-line/2,b.size.width,line+2);
        [self drawLabel:label rect:text size:size color:UIColor.whiteColor align:content?NSTextAlignmentRight:NSTextAlignmentCenter];
    }
    if(_editing) {
        auto selected=_layout.find(_selected);
        if(selected) {
            CGRect b=CGRectInset(TouchRect(selected->bounds),-4*u,-4*u);[Color(0xffcf64) setStroke];
            CGContextSetLineWidth(context,1.5*u);CGContextStrokeRect(context,b);
            for(int i=0;i<4;i++) {
                CGPoint p=CGPointMake(i&1?CGRectGetMaxX(b):CGRectGetMinX(b),i&2?CGRectGetMaxY(b):CGRectGetMinY(b));
                UIBezierPath* h=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(p.x-8*u,p.y-8*u,16*u,16*u)];
                [Color(0x273340) setFill];[h fill];[h stroke];
            }
        }
        bool canHide=selected&&_selected!="settings"&&_selected!="eye";
        NSArray* names=@[@"Save",@"Reset",@"Cancel",canHide&&!_placement.visible(_selected)?@"Show":@"Hide"];
        for(int i=0;i<4;i++) {
            [Color(i==0?0x66572c:i==3&&!canHide?0x20252d:0x2b3a4b) setFill];
            [[UIBezierPath bezierPathWithRoundedRect:_toolbar[i] cornerRadius:5*u] fill];
            float size=std::min(14*u,(float)_toolbar[i].size.width/5);
            CGRect t=_toolbar[i];t.origin.y+=(t.size.height-TouchFont(size).lineHeight)/2;
            [self drawLabel:names[i] rect:t size:size color:i==3&&!canHide?UIColor.grayColor:UIColor.whiteColor align:NSTextAlignmentCenter];
        }
        NSString* title=selected?[NSString stringWithFormat:@"Selected: %@ · %@",Text(selected->label),_placement.visible(_selected)?@"On":@"Off"]:
            @"Select a control · Drag to move · Drag corners to resize";
        [self drawLabel:title rect:CGRectMake(0,_toolbar[0].origin.y-23*u,self.bounds.size.width,20*u) size:12*u color:UIColor.whiteColor align:NSTextAlignmentCenter];
    }
}
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    if(_editing)return self;
    if(_suspended||self.hidden)return nil;
    for(auto& c:_layout.controls) if(c.key!="pad"&&_placement.visible(c.key)&&c.stick<0&&c.bounds.contains(point.x,point.y)&&
        ((!(_state&1)&&!_menuVisible)||c.key=="settings"||c.key=="eye"))return self;
    if(!(_state&1)&&!_menuVisible)for(auto& c:_layout.controls)if(c.stick>=0&&_placement.visible(c.key)&&
        ([self floating:c]?(c.stick==0?point.x<self.bounds.size.width/2:point.x>=self.bounds.size.width/2):c.bounds.contains(point.x,point.y)))return self;
    return nil;
}
- (void)editorBegan:(UITouch*)touch {
    CGPoint p=[touch locationInView:self];if(_editorFinger)return;
    for(int i=0;i<4;i++)if(CGRectContainsPoint(_toolbar[i],p)) {
        if(i==0)[self finishEditing:YES];else if(i==1){_placement={};_selected.clear();[self rebuild];}
        else if(i==2)[self finishEditing:NO];else [self toggleSelected];return;
    }
    _gestureStart=_placement;_corner=-1;_dragKey.clear();
    auto selected=_layout.find(_selected);
    if(selected) {
        auto b=selected->bounds;
        for(int i=0;i<4;i++)if(hypot(p.x-(i&1?b.x+b.w+4*_layout.unit:b.x-4*_layout.unit),p.y-(i&2?b.y+b.h+4*_layout.unit:b.y-4*_layout.unit))<=16*_layout.unit) {
            _dragKey=_selected;_corner=i;_resizeX=p.x;_resizeY=p.y;_resizeW=b.w;_resizeH=b.h;
            auto old=_placement.positions.find(_selected);_resizeScale=old==_placement.positions.end()?1:old->second[2];
            _fixedX=i&1?b.x:b.x+b.w;_fixedY=i&2?b.y:b.y+b.h;break;
        }
    }
    if(_dragKey.empty()) {
        for(int pass=0;pass<2&&_dragKey.empty();pass++)for(auto& c:_layout.controls)
            if((pass||c.stick<0)&&c.bounds.contains(p.x,p.y)) { _dragKey=_selected=c.key;_dragX=p.x-c.bounds.cx();_dragY=p.y-c.bounds.cy();break; }
    }
    if(!_dragKey.empty())_editorFinger=(uintptr_t)(__bridge void*)touch;
    [self setNeedsDisplay];
}
- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if(_suspended)return;
    for(UITouch* touch in touches) {
        if(_editing){[self editorBegan:touch];continue;}
        CGPoint p=[touch locationInView:self];TouchHud::Control* chosen=nullptr;
        for(auto& c:_layout.controls)if(c.key!="pad"&&c.stick<0&&_placement.visible(c.key)&&![self pressed:c.key]&&c.bounds.contains(p.x,p.y)&&
            ((!(_state&1)&&!_menuVisible)||c.key=="settings"||c.key=="eye")){chosen=&c;break;}
        if(!chosen&&!(_state&1)&&!_menuVisible)for(int pass=0;pass<2&&!chosen;pass++)for(auto& c:_layout.controls)
            if(c.stick>=0&&_placement.visible(c.key)&&![self pressed:c.key]&&([self floating:c]==(pass==1))&&
                (pass?(c.stick==0?p.x<self.bounds.size.width/2:p.x>=self.bounds.size.width/2):c.bounds.contains(p.x,p.y))){chosen=&c;break;}
        if(!chosen)continue;
        if(chosen->key=="eye"){[self cancelInputs];_shown=!_shown;[self rebuild];continue;}
        if(chosen->key=="settings"){[self cancelInputs];SOHiOS_RequestMenuToggle();continue;}
        _fingers[(uintptr_t)(__bridge void*)touch]=chosen->key;
        if(chosen->stick>=0) {
            if([self floating:*chosen]){chosen->cx=p.x;chosen->cy=p.y;}
            [self moveStick:*chosen point:p];
        } else TouchHud_SetButton(chosen->mask,YES);
    }
    [self publish];[self setNeedsDisplay];
}
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    for(UITouch* touch in touches) {
        uintptr_t id=(uintptr_t)(__bridge void*)touch;CGPoint p=[touch locationInView:self];
        if(_editing) {
            if(id!=_editorFinger||_dragKey.empty())continue;
            float scale=1;auto old=_placement.positions.find(_dragKey);if(old!=_placement.positions.end())scale=old->second[2];
            if(_corner>=0) {
                float sx=_corner&1?1:-1,sy=_corner&2?1:-1;
                scale=TouchHud::ResizedScale(_resizeScale,_resizeW,_resizeH,_resizeW+sx*(p.x-_resizeX),_resizeH+sy*(p.y-_resizeY));
                _placement.set(_dragKey,(_fixedX+sx*_resizeW*scale/_resizeScale/2)/_layout.width,
                    (_fixedY+sy*_resizeH*scale/_resizeScale/2)/_layout.height,scale);
            } else _placement.set(_dragKey,(p.x-_dragX)/_layout.width,(p.y-_dragY)/_layout.height,scale);
            [self rebuild];
        } else {
            auto owner=_fingers.find(id);if(owner==_fingers.end())continue;
            auto c=_layout.find(owner->second);if(c&&c->stick>=0)[self moveStick:*c point:p];
        }
    }
    [self setNeedsDisplay];
}
- (void)endTouches:(NSSet<UITouch*>*)touches cancelled:(BOOL)cancelled {
    for(UITouch* touch in touches) {
        uintptr_t id=(uintptr_t)(__bridge void*)touch;
        if(_editing&&id==_editorFinger) {
            if(cancelled)_placement=_gestureStart;
            _editorFinger=0;_dragKey.clear();_corner=-1;[self rebuild];
        }
        auto owner=_fingers.find(id);if(owner==_fingers.end())continue;
        auto c=_layout.find(owner->second);if(c)[self releaseControl:*c];_fingers.erase(owner);
    }
    [self setNeedsDisplay];
}
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self endTouches:touches cancelled:NO]; }
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self endTouches:touches cancelled:YES]; }
@end

static SOHIntegratedTouchOverlay* integrated;
int SOHiOS_IntegratedTouchStyle() { return requestedStyle.load(); }
void SOHiOS_ConfigureIntegratedTouch(int style,float scale,float opacity,int left,int right,int transparent) {
    requestedStyle=std::clamp(style,0,3);
    Config config{std::clamp(style,0,3),std::clamp(scale,.75f,1.5f),std::clamp(opacity,.15f,1.f),left!=0,right!=0,transparent!=0};
    dispatch_async(dispatch_get_main_queue(),^{current=config;[integrated configure:config];SOHiOS_RefreshOverlay();});
}
void SOHiOS_ApplyIntegratedTouch(void* target,int enabled,int menuVisible) {
    UIWindow* window=(__bridge UIWindow*)target;
    if(!enabled||current.style==0) {
        [integrated shutdown];[integrated removeFromSuperview];integrated=nil;TouchHud_Reset();return;
    }
    if(!integrated) {
        integrated=[[SOHIntegratedTouchOverlay alloc] initWithFrame:window.bounds];
        integrated.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [integrated configure:current];
    }
    if(integrated.superview!=window){[integrated removeFromSuperview];integrated.frame=window.bounds;[window addSubview:integrated];}
    [integrated setMenuVisible:menuVisible!=0];[window bringSubviewToFront:integrated];
}
void SOHiOS_EditIntegratedTouch() { dispatch_async(dispatch_get_main_queue(),^{[integrated startEditing];}); }
