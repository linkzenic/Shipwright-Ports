// UIKit test host: uses the production overlay with a small, deterministic input backend.
#define CVAR_PREFIX_SETTING "gSettings"
#include "../../soh/ios/SOHIntegratedTouchControls.mm"
#include <cassert>

static int testState=2|16;
static uint32_t testHeld=0;
static float cameraX=0,cameraY=0;
static bool nativeActive=false;
static std::array<float,30> published;
int TouchHud_GetState(void){return testState;}
int TouchHud_GetBindings(int style,int32_t* b,int count){
    if(count!=TouchHud::BindingCount)return 0;
    for(int i=0;i<count;i++)b[i]=TouchHud::DefaultAction(style,i);
    return count;
}
void TouchHud_SetButton(uint32_t mask,int down){if(down)testHeld|=mask;else testHeld&=~mask;}
void TouchHud_SetStick(int,int){}
void TouchHud_Reset(void){testHeld=0;nativeActive=false;}
void TouchHud_SetLayout(const float* values,int count,int visible,int){nativeActive=visible;if(values&&count==30)std::copy(values,values+30,published.begin());}
void SOHiOS_SetCameraStick(float x,float y){cameraX=x;cameraY=y;}
void SOHiOS_RequestMenuToggle(void){}
void SOHiOS_RefreshOverlay(void){}

@interface SOHTestTouch : UITouch
@property(nonatomic) CGPoint location;
@end
@implementation SOHTestTouch
- (CGPoint)locationInView:(UIView*)view{return self.location;}
@end

@interface SOHTestOverlay : SOHIntegratedTouchOverlay
- (void)runChecks;
- (void)presentStyle:(int)style editor:(BOOL)editor;
@end
@implementation SOHTestOverlay
- (void)tap:(CGPoint)p {
    SOHTestTouch* t=[SOHTestTouch new];t.location=p;
    [self touchesBegan:[NSSet setWithObject:t] withEvent:nil];
    [self touchesEnded:[NSSet setWithObject:t] withEvent:nil];
}
- (void)runChecks {
    [self layoutIfNeeded];
    for(int style=1;style<=3;style++) {
        [self configure:Config{style,1,.55f,true,true,false}];_state=testState;[self rebuild];
        assert(_layout.find("a")&&_layout.find("start"));[self publish];assert(nativeActive);
        auto a=_layout.find("a")->bounds;
        SOHTestTouch* t=[SOHTestTouch new];t.location=CGPointMake(a.cx(),a.cy());
        [self touchesBegan:[NSSet setWithObject:t] withEvent:nil];assert(testHeld&0x8000);
        [self touchesCancelled:[NSSet setWithObject:t] withEvent:nil];assert(!testHeld);
        SOHTestTouch* second=[SOHTestTouch new];auto b=_layout.find("b")->bounds;
        second.location=CGPointMake(b.cx(),b.cy());t.location=CGPointMake(a.cx(),a.cy());
        [self touchesBegan:[NSSet setWithObjects:t,second,nil] withEvent:nil];assert((testHeld&0xc000)==0xc000);
        [self touchesEnded:[NSSet setWithObject:t] withEvent:nil];assert((testHeld&0xc000)==0x4000);
        [self touchesEnded:[NSSet setWithObject:second] withEvent:nil];assert(!testHeld);
        t.location=CGPointMake(self.bounds.size.width*.60,self.bounds.size.height*.30);
        [self touchesBegan:[NSSet setWithObject:t] withEvent:nil];
        t.location=CGPointMake(t.location.x+30,t.location.y-20);[self touchesMoved:[NSSet setWithObject:t] withEvent:nil];
        assert(cameraX>0&&cameraY<0);[self touchesCancelled:[NSSet setWithObject:t] withEvent:nil];assert(cameraX==0&&cameraY==0);
        [self setMenuVisible:YES];
        assert([self hitTest:CGPointMake(self.bounds.size.width*.60,self.bounds.size.height*.30) withEvent:nil]==nil);
        [self touchesBegan:[NSSet setWithObject:second] withEvent:nil];assert(!testHeld);
        [self setMenuVisible:NO];
        [self startEditing];assert(!nativeActive);
        auto before=_layout.find("a")->bounds;t.location=CGPointMake(before.cx(),before.cy());
        [self touchesBegan:[NSSet setWithObject:t] withEvent:nil];
        t.location=CGPointMake(before.cx()-50,before.cy()-30);[self touchesMoved:[NSSet setWithObject:t] withEvent:nil];
        [self touchesEnded:[NSSet setWithObject:t] withEvent:nil];
        assert(_placement.positions.contains("a"));
        auto moved=_layout.find("a")->bounds;assert(moved.cx()<before.cx()-10);
        auto hide=_toolbar[3];[self tap:CGPointMake(CGRectGetMidX(hide),CGRectGetMidY(hide))];assert(!_placement.visible("a"));
        [self tap:CGPointMake(CGRectGetMidX(hide),CGRectGetMidY(hide))];assert(_placement.visible("a"));
        auto bounds=_layout.find("a")->bounds;
        t.location=CGPointMake(bounds.x+bounds.w+4*_layout.unit,bounds.y+bounds.h+4*_layout.unit);
        [self touchesBegan:[NSSet setWithObject:t] withEvent:nil];assert(_corner==3);
        t.location=CGPointMake(t.location.x+30,t.location.y+30);[self touchesMoved:[NSSet setWithObject:t] withEvent:nil];
        [self touchesEnded:[NSSet setWithObject:t] withEvent:nil];assert(_placement.positions["a"][2]>1);
        [self finishEditing:NO];assert(!_placement.positions.contains("a"));
        if(style==3) {
            [self startEditing];_selected="pad";[self toggleSelected];
            for(auto key:{"du","dd","dl","dr"})assert(!_placement.visible(key));
            [self toggleSelected];assert(_placement.visible("pad"));[self finishEditing:NO];
        }
        [self startEditing];_placement.set("a",.55,.65,1.2);_placement.show("b",false);[self finishEditing:YES];
        auto persisted=Load(style);assert(persisted.positions.contains("a")&&!persisted.visible("b"));
        assert(!persisted.positions.contains("b"));
        [NSUserDefaults.standardUserDefaults removeObjectForKey:LayoutKey(style)];
        _placement={};[self rebuild];[self startEditing];_selected="settings";[self toggleSelected];assert(_placement.visible("settings"));
        _placement.set("a",.4,.4,1);[self suspend:nil];assert(!_editing&&!_placement.positions.contains("a")&&!testHeld);
        [self resume:nil];
        if(style==1) {
            testState=2;_state=testState;[self rebuild];assert(!_layout.find("look")&&!_layout.find("map"));
            testState=2|16|32;_state=testState;[self rebuild];assert(_layout.find("look")&&_layout.find("map"));
        }
    }
    testState=2|16;[self cancelInputs];
    [@"UIKit interaction checks passed\n" writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/results.txt"]
        atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"UIKit interaction checks passed");
}
- (void)presentStyle:(int)style editor:(BOOL)editor {
    [self configure:Config{style,1,.55f,true,true,false}];_placement={};_state=testState;[self rebuild];
    if(editor)[self startEditing];
}
@end

@interface SOHTouchTestController : UIViewController
@end
@implementation SOHTouchTestController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations{return UIInterfaceOrientationMaskLandscape;}
- (BOOL)prefersStatusBarHidden{return YES;}
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation{return UIInterfaceOrientationLandscapeRight;}
@end
@interface SOHTouchTestScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow* window;
@end
@implementation SOHTouchTestScene
- (void)scene:(UIScene*)scene willConnectToSession:(UISceneSession*)session options:(UISceneConnectionOptions*)options {
    self.window=[[UIWindow alloc]initWithWindowScene:(UIWindowScene*)scene];
    SOHTouchTestController* vc=[SOHTouchTestController new];vc.view.backgroundColor=Color(0x172a28);
    self.window.rootViewController=vc;[self.window makeKeyAndVisible];
    SOHTestOverlay* view=[[SOHTestOverlay alloc]initWithFrame:vc.view.bounds];
    view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[vc.view addSubview:view];
    NSArray* args=NSProcessInfo.processInfo.arguments;int style=2;BOOL editor=YES;
    NSUInteger index=[args indexOfObject:@"--preset"];if(index!=NSNotFound&&index+1<args.count)style=[args[index+1] intValue];
    if([args containsObject:@"--play"])editor=NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [view runChecks];[view presentStyle:style editor:editor];
    });
}
@end
@interface SOHTouchTestApp : UIResponder <UIApplicationDelegate>
@end
@implementation SOHTouchTestApp
- (UISceneConfiguration*)application:(UIApplication*)application configurationForConnectingSceneSession:(UISceneSession*)session options:(UISceneConnectionOptions*)options {
    UISceneConfiguration* config=[[UISceneConfiguration alloc]initWithName:@"Touch Checks" sessionRole:session.role];
    config.delegateClass=SOHTouchTestScene.class;return config;
}
@end
int main(int argc,char**argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(SOHTouchTestApp.class));}}
