#import <UIKit/UIKit.h>

#include <SDL.h>
#include <algorithm>
#include <atomic>
#include <cmath>

#include "SOHiOSTouchControls.h"

namespace {

constexpr int kButtonA = 0;
constexpr int kButtonB = 1;
constexpr int kButtonX = 2;
constexpr int kButtonY = 3;
constexpr int kButtonBack = 4;
constexpr int kButtonStart = 6;
constexpr int kButtonLeftShoulder = 9;
constexpr int kButtonRightShoulder = 10;
constexpr int kButtonDpadUp = 11;
constexpr int kButtonDpadDown = 12;
constexpr int kButtonDpadLeft = 13;
constexpr int kButtonDpadRight = 14;

constexpr int kAxisLeftX = 0;
constexpr int kAxisLeftY = 1;
constexpr int kAxisRightX = 2;
constexpr int kAxisRightY = 3;
constexpr int kAxisLeftTrigger = 4;
constexpr int kAxisRightTrigger = 5;

int sVirtualJoystickDeviceIndex = -1;
SDL_Joystick* sVirtualJoystick = nullptr;
std::atomic_bool sTouchControlsMenuToggleRequested(false);

bool EnsureVirtualController() {
    if (sVirtualJoystick != nullptr) {
        return true;
    }

    sVirtualJoystickDeviceIndex =
        SDL_JoystickAttachVirtual(SDL_JOYSTICK_TYPE_GAMECONTROLLER, 6, 18, 0);
    if (sVirtualJoystickDeviceIndex < 0) {
        SDL_Log("Could not attach the SOH mobile touch controller: %s", SDL_GetError());
        return false;
    }

    // Match the Linkzenic Android virtual controller exactly. SDL does not
    // reliably promote a virtual joystick to a game controller on iOS unless
    // its GUID has an explicit mapping, which leaves right-stick and trigger
    // axes invisible to the control deck.
    SDL_JoystickGUID guid = SDL_JoystickGetDeviceGUID(sVirtualJoystickDeviceIndex);
    char guidString[33];
    SDL_JoystickGetGUIDString(guid, guidString, sizeof(guidString));
    char mappingString[512];
    int mappingLength = SDL_snprintf(
        mappingString, sizeof(mappingString),
        "%s,SOH iOS Touch Overlay,"
        "a:b0,b:b1,x:b2,y:b3,back:b4,guide:b5,start:b6,"
        "leftstick:b7,rightstick:b8,leftshoulder:b9,rightshoulder:b10,"
        "dpup:b11,dpdown:b12,dpleft:b13,dpright:b14,"
        "leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:a4,righttrigger:a5,"
        "platform:iOS,",
        guidString);
    if (mappingLength < 0 || mappingLength >= static_cast<int>(sizeof(mappingString)) ||
        SDL_GameControllerAddMapping(mappingString) < 0) {
        SDL_Log("Could not map the SOH mobile touch controller: %s", SDL_GetError());
        SDL_JoystickDetachVirtual(sVirtualJoystickDeviceIndex);
        sVirtualJoystickDeviceIndex = -1;
        return false;
    }

    sVirtualJoystick = SDL_JoystickOpen(sVirtualJoystickDeviceIndex);
    if (sVirtualJoystick == nullptr) {
        SDL_Log("Could not open the SOH mobile touch controller: %s", SDL_GetError());
        SDL_JoystickDetachVirtual(sVirtualJoystickDeviceIndex);
        sVirtualJoystickDeviceIndex = -1;
        return false;
    }
    return true;
}

void SetVirtualButton(int button, bool pressed) {
    if (EnsureVirtualController()) {
        SDL_JoystickSetVirtualButton(sVirtualJoystick, button,
                                     pressed ? SDL_PRESSED : SDL_RELEASED);
    }
}

void SetVirtualAxis(int axis, Sint16 value) {
    if (EnsureVirtualController()) {
        SDL_JoystickSetVirtualAxis(sVirtualJoystick, axis, value);
    }
}

Sint16 ClampAxis(CGFloat value) {
    return static_cast<Sint16>(
        std::clamp(value, static_cast<CGFloat>(SDL_MIN_SINT16),
                   static_cast<CGFloat>(SDL_MAX_SINT16)));
}

UIColor* AndroidControlFill() {
    return [UIColor colorWithWhite:1.0 alpha:0.125];
}

UIColor* AndroidControlPressedFill() {
    return [UIColor colorWithWhite:1.0 alpha:0.063];
}

UIColor* AndroidControlStroke() {
    return [UIColor colorWithWhite:1.0 alpha:0.145];
}

} // namespace

typedef NS_ENUM(NSInteger, SOHAndroidButtonShape) {
    SOHAndroidButtonShapeCircle,
    SOHAndroidButtonShapeRectangle,
    SOHAndroidButtonShapeLeftShoulder,
    SOHAndroidButtonShapeRightShoulder,
};

@interface SOHAndroidTouchButton : UIButton

@property(nonatomic) int controllerButton;
@property(nonatomic) int controllerAxis;
@property(nonatomic) Sint16 pressedAxisValue;
@property(nonatomic) Sint16 releasedAxisValue;
@property(nonatomic) BOOL inputPressed;
@property(nonatomic) SOHAndroidButtonShape controlShape;

- (instancetype)initWithLabel:(NSString*)label
                       button:(int)button
                        shape:(SOHAndroidButtonShape)shape;
- (instancetype)initWithLabel:(NSString*)label
                         axis:(int)axis
                        value:(Sint16)value
                 releaseValue:(Sint16)releaseValue
                        shape:(SOHAndroidButtonShape)shape;
- (void)cancelInput;

@end

@implementation SOHAndroidTouchButton

- (instancetype)initBaseWithLabel:(NSString*)label shape:(SOHAndroidButtonShape)shape {
    self = [super initWithFrame:CGRectZero];
    if (self != nil) {
        self.controllerButton = -1;
        self.controllerAxis = -1;
        self.controlShape = shape;
        self.multipleTouchEnabled = YES;
        self.backgroundColor = AndroidControlFill();
        self.layer.borderColor = AndroidControlStroke().CGColor;
        self.layer.borderWidth = 2.5;
        [self setTitle:label forState:UIControlStateNormal];
        [self setTitleColor:AndroidControlStroke() forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
        self.accessibilityLabel = label;

        [self addTarget:self
                      action:@selector(inputDown)
            forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [self addTarget:self
                      action:@selector(inputUp)
            forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                             UIControlEventTouchCancel | UIControlEventTouchDragExit];
    }
    return self;
}

- (instancetype)initWithLabel:(NSString*)label
                       button:(int)button
                        shape:(SOHAndroidButtonShape)shape {
    self = [self initBaseWithLabel:label shape:shape];
    if (self != nil) {
        self.controllerButton = button;
    }
    return self;
}

- (instancetype)initWithLabel:(NSString*)label
                         axis:(int)axis
                        value:(Sint16)value
                 releaseValue:(Sint16)releaseValue
                        shape:(SOHAndroidButtonShape)shape {
    self = [self initBaseWithLabel:label shape:shape];
    if (self != nil) {
        self.controllerAxis = axis;
        self.pressedAxisValue = value;
        self.releasedAxisValue = releaseValue;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    switch (self.controlShape) {
        case SOHAndroidButtonShapeCircle:
            self.layer.cornerRadius = MIN(width, height) * 0.5;
            self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
                                       kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            break;
        case SOHAndroidButtonShapeRectangle:
            self.layer.cornerRadius = 10.0;
            self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
                                       kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            break;
        case SOHAndroidButtonShapeLeftShoulder:
            self.layer.cornerRadius = 10.0;
            self.layer.maskedCorners =
                kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            break;
        case SOHAndroidButtonShapeRightShoulder:
            self.layer.cornerRadius = 10.0;
            self.layer.maskedCorners =
                kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            break;
    }
}

- (void)inputDown {
    if (self.inputPressed) {
        return;
    }
    self.inputPressed = YES;
    self.backgroundColor = AndroidControlPressedFill();
    if (self.controllerButton >= 0) {
        SetVirtualButton(self.controllerButton, true);
    } else if (self.controllerAxis >= 0) {
        SetVirtualAxis(self.controllerAxis, self.pressedAxisValue);
    }
}

- (void)inputUp {
    if (!self.inputPressed) {
        return;
    }
    self.inputPressed = NO;
    self.backgroundColor = AndroidControlFill();
    if (self.controllerButton >= 0) {
        SetVirtualButton(self.controllerButton, false);
    } else if (self.controllerAxis >= 0) {
        SetVirtualAxis(self.controllerAxis, self.releasedAxisValue);
    }
}

- (void)cancelInput {
    [self inputUp];
}

@end

@interface SOHAndroidTouchStick : UIView

@property(nonatomic, strong) UIView* base;
@property(nonatomic, strong) UIView* knob;
@property(nonatomic) CGPoint stickCenter;
@property(nonatomic) CGFloat stickDiameter;
@property(nonatomic) int controllerAxisX;
@property(nonatomic) int controllerAxisY;
- (void)cancelInput;

@end

@implementation SOHAndroidTouchStick

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        self.multipleTouchEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.accessibilityLabel = @"Floating left joystick";
        self.controllerAxisX = kAxisLeftX;
        self.controllerAxisY = kAxisLeftY;

        self.base = [[UIView alloc] initWithFrame:CGRectZero];
        self.base.userInteractionEnabled = NO;
        self.base.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.188];
        self.base.layer.borderColor = AndroidControlStroke().CGColor;
        self.base.layer.borderWidth = 2.0;
        self.base.hidden = YES;
        [self addSubview:self.base];

        self.knob = [[UIView alloc] initWithFrame:CGRectZero];
        self.knob.userInteractionEnabled = NO;
        self.knob.backgroundColor = AndroidControlFill();
        self.knob.layer.borderColor = AndroidControlStroke().CGColor;
        self.knob.layer.borderWidth = 2.5;
        [self.base addSubview:self.knob];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat diameter = self.stickDiameter > 0.0 ? self.stickDiameter : 150.0;
    self.base.bounds = CGRectMake(0.0, 0.0, diameter, diameter);
    self.base.layer.cornerRadius = diameter * 0.5;
    CGFloat knobSize = diameter * 0.32;
    self.knob.bounds = CGRectMake(0.0, 0.0, knobSize, knobSize);
    self.knob.layer.cornerRadius = knobSize * 0.5;
    self.knob.center = CGPointMake(diameter * 0.5, diameter * 0.5);
}

- (void)updateForPoint:(CGPoint)point {
    CGPoint center = self.stickCenter;
    CGFloat knobRadius = CGRectGetWidth(self.knob.bounds) * 0.5;
    CGFloat radius = self.stickDiameter * 0.5 - knobRadius;
    CGFloat dx = point.x - center.x;
    CGFloat dy = point.y - center.y;
    CGFloat distance = hypot(dx, dy);
    if (distance > radius && distance > 0.0) {
        dx = dx / distance * radius;
        dy = dy / distance * radius;
    }

    self.knob.center =
        CGPointMake(self.stickDiameter * 0.5 + dx, self.stickDiameter * 0.5 + dy);
    SetVirtualAxis(self.controllerAxisX, ClampAxis((dx / radius) * SDL_MAX_SINT16));
    SetVirtualAxis(self.controllerAxisY, ClampAxis((dy / radius) * SDL_MAX_SINT16));
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    UITouch* touch = touches.anyObject;
    if (touch != nil) {
        CGPoint point = [touch locationInView:self];
        self.stickCenter = point;
        self.base.center = self.stickCenter;
        self.base.hidden = NO;
        [self updateForPoint:point];
    }
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    UITouch* touch = touches.anyObject;
    if (touch != nil) {
        [self updateForPoint:[touch locationInView:self]];
    }
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self cancelInput];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self cancelInput];
}

- (void)cancelInput {
    SetVirtualAxis(self.controllerAxisX, 0);
    SetVirtualAxis(self.controllerAxisY, 0);
    self.knob.center =
        CGPointMake(self.stickDiameter * 0.5, self.stickDiameter * 0.5);
    self.base.hidden = YES;
}

@end

@interface SOHAndroidCrossView : UIView
@end

@implementation SOHAndroidCrossView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat width = CGRectGetWidth(rect);
    CGFloat height = CGRectGetHeight(rect);
    CGFloat arm = MIN(width, height) / 3.0;
    CGFloat x = (width - arm) * 0.5;
    CGFloat y = (height - arm) * 0.5;

    UIBezierPath* cross = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, 0, arm, height)
                                                     cornerRadius:5.0];
    [cross appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, y, width, arm)
                                                  cornerRadius:5.0]];
    CGContextSetFillColorWithColor(context, AndroidControlFill().CGColor);
    CGContextSetStrokeColorWithColor(context, AndroidControlStroke().CGColor);
    CGContextSetLineWidth(context, 2.5);
    CGContextAddPath(context, cross.CGPath);
    CGContextDrawPath(context, kCGPathFillStroke);

    NSDictionary* attributes = @{
        NSFontAttributeName : [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold],
        NSForegroundColorAttributeName : AndroidControlStroke(),
    };
    [@"▲" drawAtPoint:CGPointMake(width * 0.5 - 6.0, 4.0) withAttributes:attributes];
    [@"▼" drawAtPoint:CGPointMake(width * 0.5 - 6.0, height - 18.0) withAttributes:attributes];
    [@"◀" drawAtPoint:CGPointMake(4.0, height * 0.5 - 8.0) withAttributes:attributes];
    [@"▶" drawAtPoint:CGPointMake(width - 17.0, height * 0.5 - 8.0) withAttributes:attributes];
}

@end

@interface SOHAndroidLookArea : UIView

@property(nonatomic) CGPoint lastPoint;
@property(nonatomic) BOOL trackingTouch;
- (void)cancelInput;

@end

@implementation SOHAndroidLookArea

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        self.backgroundColor = UIColor.clearColor;
        self.multipleTouchEnabled = NO;
        self.accessibilityLabel = @"Camera look area";
    }
    return self;
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    UITouch* touch = touches.anyObject;
    if (touch != nil) {
        self.lastPoint = [touch locationInView:self];
        self.trackingTouch = YES;
    }
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    UITouch* touch = touches.anyObject;
    if (touch == nil || !self.trackingTouch) {
        return;
    }
    CGPoint point = [touch locationInView:self];
    CGFloat dx = (point.x - self.lastPoint.x) * 15.0;
    CGFloat dy = (point.y - self.lastPoint.y) * 15.0;
    self.lastPoint = point;
    SetVirtualAxis(kAxisRightX, ClampAxis(dx));
    SetVirtualAxis(kAxisRightY, ClampAxis(dy));
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self cancelInput];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self cancelInput];
}

- (void)cancelInput {
    self.trackingTouch = NO;
    SetVirtualAxis(kAxisRightX, 0);
    SetVirtualAxis(kAxisRightY, 0);
}

@end

@interface SOHAndroidTouchOverlay : UIView

@property(nonatomic, strong) UIView* controlGroup;
@property(nonatomic, strong) SOHAndroidTouchStick* leftStick;
@property(nonatomic, strong) SOHAndroidTouchStick* rightStick;
@property(nonatomic, strong) SOHAndroidCrossView* cCross;
@property(nonatomic, strong) SOHAndroidTouchButton* buttonA;
@property(nonatomic, strong) SOHAndroidTouchButton* buttonB;
@property(nonatomic, strong) SOHAndroidTouchButton* buttonX;
@property(nonatomic, strong) SOHAndroidTouchButton* buttonY;
@property(nonatomic, strong) SOHAndroidTouchButton* buttonL;
@property(nonatomic, strong) SOHAndroidTouchButton* buttonZL;
@property(nonatomic, strong) SOHAndroidTouchButton* buttonZR;
@property(nonatomic, strong) SOHAndroidTouchButton* buttonR;
@property(nonatomic, strong) SOHAndroidTouchButton* buttonBack;
@property(nonatomic, strong) SOHAndroidTouchButton* buttonStart;
@property(nonatomic, strong) NSArray<SOHAndroidTouchButton*>* cButtons;
@property(nonatomic, strong) NSArray<SOHAndroidTouchButton*>* allInputButtons;
@property(nonatomic, strong) UIButton* visibilityButton;
@property(nonatomic) BOOL controlsHiddenByUser;
@property(nonatomic) BOOL menuVisible;
@property(nonatomic) NSInteger faceButtonLayout;

- (void)cancelAllInputs;
- (void)setSOHFaceButtonLayout:(NSInteger)layout;
- (void)setSOHMenuVisible:(BOOL)visible;

@end

@implementation SOHAndroidTouchOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        self.backgroundColor = UIColor.clearColor;
        self.multipleTouchEnabled = YES;
        self.faceButtonLayout = 0;

        self.controlGroup = [[UIView alloc] initWithFrame:self.bounds];
        self.controlGroup.backgroundColor = UIColor.clearColor;
        self.controlGroup.multipleTouchEnabled = YES;
        self.controlGroup.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:self.controlGroup];

        self.leftStick = [[SOHAndroidTouchStick alloc] initWithFrame:CGRectZero];
        self.rightStick = [[SOHAndroidTouchStick alloc] initWithFrame:CGRectZero];
        self.rightStick.controllerAxisX = kAxisRightX;
        self.rightStick.controllerAxisY = kAxisRightY;
        self.rightStick.accessibilityLabel = @"Floating right joystick";
        self.cCross = [[SOHAndroidCrossView alloc] initWithFrame:CGRectZero];

        self.buttonA = [[SOHAndroidTouchButton alloc] initWithLabel:@"A"
                                                            button:kButtonA
                                                             shape:SOHAndroidButtonShapeCircle];
        self.buttonB = [[SOHAndroidTouchButton alloc] initWithLabel:@"B"
                                                            button:kButtonB
                                                             shape:SOHAndroidButtonShapeCircle];
        self.buttonX = [[SOHAndroidTouchButton alloc] initWithLabel:@"X"
                                                            button:kButtonX
                                                             shape:SOHAndroidButtonShapeCircle];
        self.buttonY = [[SOHAndroidTouchButton alloc] initWithLabel:@"Y"
                                                            button:kButtonY
                                                             shape:SOHAndroidButtonShapeCircle];
        self.buttonL =
            [[SOHAndroidTouchButton alloc] initWithLabel:@"L"
                                                 button:kButtonLeftShoulder
                                                  shape:SOHAndroidButtonShapeLeftShoulder];
        self.buttonZL =
            [[SOHAndroidTouchButton alloc] initWithLabel:@"ZL"
                                                   axis:kAxisLeftTrigger
                                                  value:SDL_MAX_SINT16
                                           releaseValue:SDL_MIN_SINT16
                                                  shape:SOHAndroidButtonShapeLeftShoulder];
        self.buttonZR =
            [[SOHAndroidTouchButton alloc] initWithLabel:@"ZR"
                                                   axis:kAxisRightTrigger
                                                  value:SDL_MAX_SINT16
                                           releaseValue:SDL_MIN_SINT16
                                                  shape:SOHAndroidButtonShapeRightShoulder];
        self.buttonR =
            [[SOHAndroidTouchButton alloc] initWithLabel:@"R"
                                                 button:kButtonRightShoulder
                                                  shape:SOHAndroidButtonShapeRightShoulder];
        self.buttonBack =
            [[SOHAndroidTouchButton alloc] initWithLabel:@"Back"
                                                 button:kButtonBack
                                                  shape:SOHAndroidButtonShapeRectangle];
        self.buttonStart =
            [[SOHAndroidTouchButton alloc] initWithLabel:@"Start"
                                                 button:kButtonStart
                                                  shape:SOHAndroidButtonShapeRectangle];

        SOHAndroidTouchButton* cUp =
            [[SOHAndroidTouchButton alloc] initWithLabel:@""
                                                 button:kButtonDpadUp
                                                  shape:SOHAndroidButtonShapeRectangle];
        SOHAndroidTouchButton* cDown =
            [[SOHAndroidTouchButton alloc] initWithLabel:@""
                                                 button:kButtonDpadDown
                                                  shape:SOHAndroidButtonShapeRectangle];
        SOHAndroidTouchButton* cLeft =
            [[SOHAndroidTouchButton alloc] initWithLabel:@""
                                                 button:kButtonDpadLeft
                                                  shape:SOHAndroidButtonShapeRectangle];
        SOHAndroidTouchButton* cRight =
            [[SOHAndroidTouchButton alloc] initWithLabel:@""
                                                 button:kButtonDpadRight
                                                  shape:SOHAndroidButtonShapeRectangle];
        for (SOHAndroidTouchButton* button in @[ cUp, cDown, cLeft, cRight ]) {
            button.backgroundColor = UIColor.clearColor;
            button.layer.borderWidth = 0.0;
        }
        cUp.accessibilityLabel = @"C Up";
        cDown.accessibilityLabel = @"C Down";
        cLeft.accessibilityLabel = @"C Left";
        cRight.accessibilityLabel = @"C Right";
        self.cButtons = @[ cUp, cDown, cLeft, cRight ];

        [self.controlGroup addSubview:self.leftStick];
        [self.controlGroup addSubview:self.rightStick];
        [self.controlGroup addSubview:self.cCross];

        self.allInputButtons = @[
            self.buttonA, self.buttonB, self.buttonX, self.buttonY, self.buttonL,
            self.buttonZL, self.buttonZR, self.buttonR, self.buttonBack, self.buttonStart,
            cUp, cDown, cLeft, cRight,
        ];
        for (SOHAndroidTouchButton* button in self.allInputButtons) {
            [self.controlGroup addSubview:button];
        }
        [self.buttonBack addTarget:self
                            action:@selector(requestMenuToggle)
                  forControlEvents:UIControlEventTouchUpInside];

        self.visibilityButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.visibilityButton.backgroundColor = UIColor.clearColor;
        [self.visibilityButton setTitle:@"◉" forState:UIControlStateNormal];
        [self.visibilityButton setTitleColor:AndroidControlFill() forState:UIControlStateNormal];
        self.visibilityButton.titleLabel.font =
            [UIFont systemFontOfSize:22.0 weight:UIFontWeightRegular];
        self.visibilityButton.accessibilityLabel = @"Show or hide touch controls";
        [self.visibilityButton addTarget:self
                                  action:@selector(toggleControlsVisibility)
                        forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.visibilityButton];
    }
    return self;
}

- (void)setSOHFaceButtonLayout:(NSInteger)layout {
    self.faceButtonLayout = std::clamp<NSInteger>(layout, 0, 2);

    // Match Linkzenic Android's positional SDL mappings exactly.
    if (self.faceButtonLayout == 0) {
        self.buttonA.controllerButton = kButtonB;
        self.buttonB.controllerButton = kButtonA;
        self.buttonX.controllerButton = kButtonY;
        self.buttonY.controllerButton = kButtonX;
    } else {
        self.buttonA.controllerButton = kButtonA;
        self.buttonB.controllerButton = kButtonB;
        self.buttonX.controllerButton = kButtonX;
        self.buttonY.controllerButton = kButtonY;
    }
    [self setNeedsLayout];
}

- (void)requestMenuToggle {
    sTouchControlsMenuToggleRequested.store(true);
}

- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    UIView* hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.controlGroup) {
        return nil;
    }
    return hit;
}

- (void)toggleControlsVisibility {
    self.controlsHiddenByUser = !self.controlsHiddenByUser;
    [self applyVisibility];
}

- (void)applyVisibility {
    BOOL hideGameplayControls = self.controlsHiddenByUser || self.menuVisible;
    for (UIView* view in self.controlGroup.subviews) {
        view.hidden = hideGameplayControls;
    }
    if (self.menuVisible) {
        self.buttonBack.hidden = NO;
    }
    self.visibilityButton.hidden = self.menuVisible;
}

- (void)setSOHMenuVisible:(BOOL)visible {
    if (self.menuVisible == visible) {
        return;
    }
    self.menuVisible = visible;
    [self cancelAllInputs];
    [self applyVisibility];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    BOOL isPad = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
    CGFloat maximumScale = isPad ? 1.35 : 1.15;
    CGFloat scale = std::clamp(height / 390.0, 0.82, maximumScale);
    CGFloat left = safe.left + 16.0 * scale;
    CGFloat right = safe.right + 16.0 * scale;
    CGFloat top = safe.top + 16.0 * scale;
    CGFloat bottom = safe.bottom + 16.0 * scale;

    CGFloat shoulderWidth = 84.0 * scale;
    CGFloat shoulderHeight = 40.0 * scale;
    CGFloat shoulderGap = 8.0 * scale;
    self.buttonZL.frame = CGRectMake(left, top, shoulderWidth, shoulderHeight);
    self.buttonL.frame =
        CGRectMake(left, CGRectGetMaxY(self.buttonZL.frame) + shoulderGap,
                   shoulderWidth, shoulderHeight);
    self.buttonZR.frame =
        CGRectMake(width - right - shoulderWidth, top, shoulderWidth, shoulderHeight);
    self.buttonR.frame =
        CGRectMake(width - right - shoulderWidth,
                   CGRectGetMaxY(self.buttonZR.frame) + shoulderGap,
                   shoulderWidth, shoulderHeight);

    CGFloat stickSize = 150.0 * scale;
    self.leftStick.stickDiameter = stickSize;
    self.leftStick.frame = CGRectMake(0.0, 0.0, width * 0.46, height);
    CGFloat rightStickSize = 132.0 * scale;
    self.rightStick.stickDiameter = rightStickSize;
    CGFloat rightStickStart = width * 0.52;
    self.rightStick.frame =
        CGRectMake(rightStickStart, 0.0, width - rightStickStart, height);

    CGFloat crossSize = 90.0 * scale;
    self.cCross.frame =
        CGRectMake(left + (stickSize - crossSize) * 0.5 - 30.0 * scale,
                   height - bottom - stickSize - crossSize - 6.0 * scale,
                   crossSize, crossSize);
    CGFloat cHit = 30.0 * scale;
    CGFloat crossMidX = CGRectGetMidX(self.cCross.frame);
    CGFloat crossMidY = CGRectGetMidY(self.cCross.frame);
    self.cButtons[0].frame =
        CGRectMake(crossMidX - cHit * 0.5, CGRectGetMinY(self.cCross.frame), cHit, cHit);
    self.cButtons[1].frame =
        CGRectMake(crossMidX - cHit * 0.5, CGRectGetMaxY(self.cCross.frame) - cHit, cHit, cHit);
    self.cButtons[2].frame =
        CGRectMake(CGRectGetMinX(self.cCross.frame), crossMidY - cHit * 0.5, cHit, cHit);
    self.cButtons[3].frame =
        CGRectMake(CGRectGetMaxX(self.cCross.frame) - cHit, crossMidY - cHit * 0.5, cHit, cHit);

    CGFloat faceSize = 48.0 * scale;
    CGFloat faceOffset = 45.0 * scale;
    CGFloat faceCenterX = width - right - faceSize - faceOffset;
    CGFloat faceCenterY = height - bottom - faceSize - faceOffset;
    for (SOHAndroidTouchButton* button in
         @[ self.buttonA, self.buttonB, self.buttonX, self.buttonY ]) {
        button.bounds = CGRectMake(0.0, 0.0, faceSize, faceSize);
    }
    if (self.faceButtonLayout == 0) {
        // Nintendo: X top, Y left, A right, B bottom.
        self.buttonX.center = CGPointMake(faceCenterX, faceCenterY - faceOffset);
        self.buttonY.center = CGPointMake(faceCenterX - faceOffset, faceCenterY);
        self.buttonA.center = CGPointMake(faceCenterX + faceOffset, faceCenterY);
        self.buttonB.center = CGPointMake(faceCenterX, faceCenterY + faceOffset);
    } else if (self.faceButtonLayout == 2) {
        // GameCube: prominent A, B lower-left, X upper-right, Y upper-center.
        self.buttonA.bounds = CGRectMake(0.0, 0.0, faceSize * 1.35, faceSize * 1.35);
        self.buttonA.center = CGPointMake(faceCenterX + 12.0 * scale,
                                          faceCenterY + 20.0 * scale);
        self.buttonB.center = CGPointMake(faceCenterX - faceOffset,
                                          faceCenterY + faceOffset * 0.65);
        self.buttonX.center = CGPointMake(faceCenterX + faceOffset,
                                          faceCenterY - faceOffset * 0.55);
        self.buttonY.center = CGPointMake(faceCenterX - 8.0 * scale,
                                          faceCenterY - faceOffset);
    } else {
        // Xbox: Y top, X left, B right, A bottom.
        self.buttonY.center = CGPointMake(faceCenterX, faceCenterY - faceOffset);
        self.buttonX.center = CGPointMake(faceCenterX - faceOffset, faceCenterY);
        self.buttonB.center = CGPointMake(faceCenterX + faceOffset, faceCenterY);
        self.buttonA.center = CGPointMake(faceCenterX, faceCenterY + faceOffset);
    }

    CGFloat centerX = CGRectGetMidX(self.bounds);
    CGFloat systemWidth = 50.0 * scale;
    CGFloat systemHeight = 30.0 * scale;
    self.buttonBack.frame =
        CGRectMake(centerX - 100.0 * scale - systemWidth * 0.5,
                   height - safe.bottom - systemHeight - 10.0 * scale,
                   systemWidth, systemHeight);
    self.buttonStart.frame =
        CGRectMake(centerX + 100.0 * scale - systemWidth * 0.5,
                   height - safe.bottom - systemHeight - 10.0 * scale,
                   systemWidth, systemHeight);

    CGFloat toggleSize = 30.0 * scale;
    self.visibilityButton.frame =
        CGRectMake(width - safe.right - toggleSize - 10.0 * scale,
                   height - safe.bottom - toggleSize - 10.0 * scale,
                   toggleSize, toggleSize);

    [self.controlGroup sendSubviewToBack:self.rightStick];
    [self.controlGroup sendSubviewToBack:self.leftStick];
    [self applyVisibility];
}

- (void)cancelAllInputs {
    [self.leftStick cancelInput];
    [self.rightStick cancelInput];
    for (SOHAndroidTouchButton* button in self.allInputButtons) {
        [button cancelInput];
    }
}

@end

static SOHAndroidTouchOverlay* sTouchOverlay;
static BOOL sTouchControlsDesired;
static NSInteger sTouchFaceButtonLayout;
static std::atomic_bool sTouchControlsMenuVisible(false);

static UIWindow* ActiveWindow() {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static void ApplyTouchControlsState() {
    UIWindow* window = ActiveWindow();
    if (window == nil) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           ApplyTouchControlsState();
                       });
        return;
    }

    if (!sTouchControlsDesired) {
        [sTouchOverlay cancelAllInputs];
        [sTouchOverlay removeFromSuperview];
        sTouchOverlay = nil;
        return;
    }

    if (sTouchOverlay == nil) {
        sTouchOverlay = [[SOHAndroidTouchOverlay alloc] initWithFrame:window.bounds];
        sTouchOverlay.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    [sTouchOverlay setSOHFaceButtonLayout:sTouchFaceButtonLayout];
    if (sTouchOverlay.superview != window) {
        [sTouchOverlay removeFromSuperview];
        sTouchOverlay.frame = window.bounds;
        [window addSubview:sTouchOverlay];
    }
    [sTouchOverlay setSOHMenuVisible:sTouchControlsMenuVisible.load()];
    [window bringSubviewToFront:sTouchOverlay];
}

int SOHiOS_TouchControlsAvailable(void) {
    return 1;
}

void SOHiOS_SetTouchControlsEnabled(int enabled) {
    dispatch_async(dispatch_get_main_queue(), ^{
        sTouchControlsDesired = enabled != 0;
        ApplyTouchControlsState();
    });
}

void SOHiOS_SetFaceButtonLayout(int layout) {
    dispatch_async(dispatch_get_main_queue(), ^{
        sTouchFaceButtonLayout = std::clamp(layout, 0, 2);
        [sTouchOverlay setSOHFaceButtonLayout:sTouchFaceButtonLayout];
    });
}

void SOHiOS_SetTouchControlsMenuVisible(int visible) {
    bool menuVisible = visible != 0;
    sTouchControlsMenuVisible.store(menuVisible);
    dispatch_async(dispatch_get_main_queue(), ^{
        ApplyTouchControlsState();
    });
}

int SOHiOS_ConsumeMenuToggleRequest(void) {
    return sTouchControlsMenuToggleRequested.exchange(false) ? 1 : 0;
}
