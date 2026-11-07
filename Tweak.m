// ============================================================================
//  VideoStar Tool  -  hson Edition  (V2.1 - hardened, compile fixed)
//  Author : hson (Hoàng Văn Sơn)
// ============================================================================

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreMedia/CoreMedia.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

#pragma mark - Theme

#define VS_CYAN    [UIColor colorWithRed:0.18 green:0.86 blue:1.00 alpha:1]
#define VS_VIOLET  [UIColor colorWithRed:0.60 green:0.38 blue:1.00 alpha:1]
#define VS_PINK    [UIColor colorWithRed:1.00 green:0.32 blue:0.66 alpha:1]
#define VS_INK     [UIColor colorWithRed:0.04 green:0.05 blue:0.10 alpha:1]
#define VS_TEXT2   [UIColor colorWithWhite:1 alpha:0.62]
#define VS_TEXT3   [UIColor colorWithWhite:1 alpha:0.42]
#define VS_TOOL_VERSION @"V2.1"

typedef NS_ENUM(NSInteger, VSFeature) {
    VSFeatureNone     = -1,
    VSFeatureMedia    = 0,
    VSFeatureLastCode = 1,
    VSFeatureBeat     = 2,
    VSFeatureMulti    = 3,
};

// Forward declarations
void VSInstallHooksForce(void);

#pragma mark - Logging

static void VSLog(NSString *msg) {
    NSLog(@"[VideoStarTool] %@", msg);
    @try {
        NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        NSString *path = [dir stringByAppendingPathComponent:@"VideoStarTool.log"];
        NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        if ([attr fileSize] > 512 * 1024) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        NSString *line = [NSString stringWithFormat:@"%@  %@\n", [NSDate date], msg];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (h) {
            [h seekToEndOfFile];
            [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [h closeFile];
        } else {
            [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    } @catch (__unused NSException *e) {}
}
#define VSLOG(fmt, ...) VSLog([NSString stringWithFormat:fmt, ##__VA_ARGS__])

#pragma mark - Safe runtime helpers

static id VSInvokeEx(id target, SEL sel, NSArray *args, BOOL *invoked) {
    if (invoked) *invoked = NO;
    if (!target || !sel || ![target respondsToSelector:sel]) return nil;
    @try {
        NSMethodSignature *sig = [target methodSignatureForSelector:sel];
        if (!sig) return nil;
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        inv.target = target;
        inv.selector = sel;
        NSUInteger n = sig.numberOfArguments > 2 ? sig.numberOfArguments - 2 : 0;
        if (args.count < n) return nil;
        for (NSUInteger i = 0; i < n; i++) {
            id a = args[i];
            const char *t = [sig getArgumentTypeAtIndex:i + 2];
            while (*t == 'r' || *t == 'n' || *t == 'N' || *t == 'o' || *t == 'O' || *t == 'R' || *t == 'V') t++;
            NSUInteger idx = i + 2;
            if (*t == '@') {
                __unsafe_unretained id v = (a == (id)[NSNull null]) ? nil : a;
                [inv setArgument:&v atIndex:idx];
            } else if ([a isKindOfClass:[NSNumber class]]) {
                NSNumber *num = a;
                switch (*t) {
                    case 'B': { BOOL v = num.boolValue; [inv setArgument:&v atIndex:idx]; break; }
                    case 'c': { char v = num.charValue; [inv setArgument:&v atIndex:idx]; break; }
                    case 'C': { unsigned char v = num.unsignedCharValue; [inv setArgument:&v atIndex:idx]; break; }
                    case 'i': { int v = num.intValue; [inv setArgument:&v atIndex:idx]; break; }
                    case 'I': { unsigned int v = num.unsignedIntValue; [inv setArgument:&v atIndex:idx]; break; }
                    case 'l': case 'q': { long long v = num.longLongValue; [inv setArgument:&v atIndex:idx]; break; }
                    case 'L': case 'Q': { unsigned long long v = num.unsignedLongLongValue; [inv setArgument:&v atIndex:idx]; break; }
                    case 'd': { double v = num.doubleValue; [inv setArgument:&v atIndex:idx]; break; }
                    case 'f': { float v = num.floatValue; [inv setArgument:&v atIndex:idx]; break; }
                    default: return nil;
                }
            } else {
                return nil;
            }
        }
        [inv invoke];
        if (invoked) *invoked = YES;
        const char *rt = sig.methodReturnType;
        while (*rt == 'r' || *rt == 'n' || *rt == 'N' || *rt == 'o' || *rt == 'O' || *rt == 'R' || *rt == 'V') rt++;
        switch (*rt) {
            case 'v': return [NSNull null];
            case '@': case '#': { __unsafe_unretained id r = nil; [inv getReturnValue:&r]; return r; }
            case 'B': { BOOL v = NO; [inv getReturnValue:&v]; return @(v); }
            case 'c': { char v = 0; [inv getReturnValue:&v]; return @(v); }
            case 'C': { unsigned char v = 0; [inv getReturnValue:&v]; return @(v); }
            case 'i': { int v = 0; [inv getReturnValue:&v]; return @(v); }
            case 'I': { unsigned int v = 0; [inv getReturnValue:&v]; return @(v); }
            case 'l': case 'q': { long long v = 0; [inv getReturnValue:&v]; return @(v); }
            case 'L': case 'Q': { unsigned long long v = 0; [inv getReturnValue:&v]; return @(v); }
            case 'd': { double v = 0; [inv getReturnValue:&v]; return @(v); }
            case 'f': { float v = 0; [inv getReturnValue:&v]; return @(v); }
            default:  return [NSNull null];
        }
    } @catch (NSException *e) {
        VSLOG(@"invoke %@ exception: %@", NSStringFromSelector(sel), e.reason ?: e.name);
        if (invoked) *invoked = NO;
        return nil;
    }
}

static id VSInvoke(id target, SEL sel, NSArray *args) {
    id r = VSInvokeEx(target, sel, args, NULL);
    return r == (id)[NSNull null] ? nil : r;
}
static BOOL VSPerform(id target, SEL sel, NSArray *args) {
    BOOL ok = NO;
    VSInvokeEx(target, sel, args, &ok);
    return ok;
}
static id VSGet(id target, SEL sel) { return VSInvoke(target, sel, nil); }
static NSUInteger VSUInt(id target, SEL sel, NSUInteger def) {
    id r = VSInvoke(target, sel, nil);
    return [r isKindOfClass:[NSNumber class]] ? [r unsignedIntegerValue] : def;
}
static BOOL VSBool(id target, SEL sel, NSArray *args) {
    id r = VSInvoke(target, sel, args);
    return [r isKindOfClass:[NSNumber class]] ? [r boolValue] : NO;
}

static id VSKey(id obj, NSString *key) {
    if (!obj || !key.length) return nil;
    @try { return [obj valueForKey:key]; } @catch (__unused NSException *e) {}
    @try {
        Class c = [obj class];
        Ivar iv = class_getInstanceVariable(c, key.UTF8String);
        if (!iv) iv = class_getInstanceVariable(c, [@"_" stringByAppendingString:key].UTF8String);
        if (iv) {
            const char *enc = ivar_getTypeEncoding(iv);
            if (enc && enc[0] == '@') return object_getIvar(obj, iv);
        }
    } @catch (__unused NSException *e) {}
    return nil;
}
static BOOL VSSetKey(id obj, NSString *key, id value) {
    if (!obj || !key.length) return NO;
    @try { [obj setValue:value forKey:key]; return YES; } @catch (__unused NSException *e) {}
    return NO;
}

static NSString *VSNorm(id s) {
    if (![s isKindOfClass:[NSString class]]) return @"";
    NSString *t = [(NSString *)s stringByReplacingOccurrencesOfString:@"đ" withString:@"d"];
    t = [t stringByReplacingOccurrencesOfString:@"Đ" withString:@"d"];
    t = [t stringByFoldingWithOptions:NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch | NSCaseInsensitiveSearch
                               locale:[NSLocale localeWithLocaleIdentifier:@"vi_VN"]];
    t = [t.lowercaseString stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static void VSAfter(NSTimeInterval d, dispatch_block_t b) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)), dispatch_get_main_queue(), b);
}

static BOOL VSPressButton(id b) {
    if (![b isKindOfClass:[UIButton class]]) return NO;
    @try { [(UIButton *)b sendActionsForControlEvents:UIControlEventTouchUpInside]; return YES; }
    @catch (__unused NSException *e) { return NO; }
}

static BOOL VSTrigger(id target, NSString *buttonIvar, SEL sel) {
    if (!target) return NO;
    if (sel && VSPerform(target, sel, nil)) return YES;
    id btn = VSKey(target, buttonIvar);
    return VSPressButton(btn);
}

static BOOL VSCurrentTime(id t, CMTime *out) {
    if (!t) return NO;
    @try {
        if ([t respondsToSelector:@selector(currentTime)]) {
            NSMethodSignature *sig = [t methodSignatureForSelector:@selector(currentTime)];
            if (sig && sig.methodReturnLength == sizeof(CMTime)) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                inv.target = t;
                inv.selector = @selector(currentTime);
                [inv invoke];
                CMTime v = kCMTimeInvalid;
                [inv getReturnValue:&v];
                if (CMTIME_IS_VALID(v)) { if (out) *out = v; return YES; }
            }
        }
        if ([t isKindOfClass:[UIView class]]) {
            NSMutableArray *stack = [NSMutableArray arrayWithObject:t];
            NSUInteger guard = 0;
            while (stack.count && guard++ < 400) {
                UIView *v = stack.firstObject; [stack removeObjectAtIndex:0];
                if ([v isKindOfClass:NSClassFromString(@"AVPlayerView")] ||
                    [v isKindOfClass:NSClassFromString(@"AVPlayerLayer")]) {
                    id player = VSKey(v, @"player");
                    if ([player isKindOfClass:[AVPlayer class]]) {
                        CMTime c = [(AVPlayer *)player currentTime];
                        if (CMTIME_IS_VALID(c)) { if (out) *out = c; return YES; }
                    }
                }
                [stack addObjectsFromArray:v.subviews];
            }
        }
    } @catch (__unused NSException *e) {}
    return NO;
}

// FIX: khai báo VSFindSubviewDepth TRƯỚC VSFindSubview
static UIView *VSFindSubviewDepth(UIView *v, Class cls, NSUInteger depth) {
    if (!v || !cls || depth > 80) return nil;
    if ([v isKindOfClass:cls]) return v;
    for (UIView *s in [v.subviews reverseObjectEnumerator]) {
        UIView *r = VSFindSubviewDepth(s, cls, depth + 1);
        if (r) return r;
    }
    return nil;
}
static UIView *VSFindSubview(UIView *v, Class cls) {
    return VSFindSubviewDepth(v, cls, 0);
}

static void VSCollectTexts(UIView *v, NSMutableArray *out) {
    if (!v || out.count > 200) return;
    if ([v isKindOfClass:[UILabel class]]) {
        NSString *t = ((UILabel *)v).text;
        if (t.length) [out addObject:t];
    }
    for (UIView *s in v.subviews) VSCollectTexts(s, out);
}

static UIViewController *VSResolveTop(UIViewController *vc) {
    if (!vc) return nil;
    if (vc.presentedViewController) return VSResolveTop(vc.presentedViewController);
    if ([vc isKindOfClass:[UINavigationController class]]) {
        UIViewController *v = ((UINavigationController *)vc).visibleViewController;
        return v ? VSResolveTop(v) : vc;
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        UIViewController *s = ((UITabBarController *)vc).selectedViewController;
        return s ? VSResolveTop(s) : vc;
    }
    if ([vc isKindOfClass:[UISplitViewController class]]) {
        UIViewController *l = ((UISplitViewController *)vc).viewControllers.lastObject;
        return l ? VSResolveTop(l) : vc;
    }
    return vc;
}

static UIWindow *VSAppKeyWindow(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return nil;
    UIWindow *fallback = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *sc in app.connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)sc;
            if (ws.activationState != UISceneActivationStateForegroundActive &&
                ws.activationState != UISceneActivationStateForegroundInactive) continue;
            for (UIWindow *w in ws.windows) {
                if ([w isKindOfClass:NSClassFromString(@"VSPassthroughWindow")]) continue;
                if (w.hidden || !w.rootViewController) continue;
                if (w.isKeyWindow) return w;
                if (!fallback) fallback = w;
            }
        }
    }
    if (!fallback) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *w in app.windows) {
            if ([w isKindOfClass:NSClassFromString(@"VSPassthroughWindow")]) continue;
            if (w.hidden || !w.rootViewController) continue;
            if (w.isKeyWindow) return w;
            if (!fallback) fallback = w;
        }
#pragma clang diagnostic pop
    }
    return fallback;
}
static UIViewController *VSTopVC(void) {
    return VSResolveTop(VSAppKeyWindow().rootViewController);
}

#pragma mark - QR cache

static NSData *sLastQRData = nil;

static NSString *VSLastQRPath(void) {
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
            stringByAppendingPathComponent:@"VideoStarTool_LastQR.png"];
}

static NSData *VSLastQRData(void) {
    NSData *d = [NSData dataWithContentsOfFile:VSLastQRPath() options:NSDataReadingMappedIfSafe error:nil];
    if (d.length) sLastQRData = [d copy];
    return sLastQRData;
}

static void VSCacheQR(id obj) {
    if (!obj) return;
    NSData *png = nil;
    @try {
        if ([obj isKindOfClass:[NSData class]]) {
            png = [(NSData *)obj copy];
        } else if ([obj isKindOfClass:[UIImage class]]) {
            png = UIImagePNGRepresentation(obj);
        } else if ([obj isKindOfClass:[CIImage class]]) {
            CIContext *ctx = [CIContext contextWithOptions:nil];
            CGImageRef cg = [ctx createCGImage:obj fromRect:[(CIImage *)obj extent]];
            if (cg) { png = UIImagePNGRepresentation([UIImage imageWithCGImage:cg]); CGImageRelease(cg); }
        }
        if (png.length && [UIImage imageWithData:png]) {
            sLastQRData = [png copy];
            [png writeToFile:VSLastQRPath() atomically:YES];
            VSLOG(@"QR cached (%lu bytes)", (unsigned long)png.length);
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - Small UI building blocks

@interface VSGradientView : UIView
- (void)setColors:(NSArray<UIColor *> *)colors start:(CGPoint)s end:(CGPoint)e;
@end
@implementation VSGradientView
+ (Class)layerClass { return [CAGradientLayer class]; }
- (void)setColors:(NSArray<UIColor *> *)colors start:(CGPoint)s end:(CGPoint)e {
    CAGradientLayer *g = (CAGradientLayer *)self.layer;
    NSMutableArray *cg = [NSMutableArray array];
    for (UIColor *c in colors) [cg addObject:(id)c.CGColor];
    g.colors = cg;
    g.startPoint = s;
    g.endPoint = e;
}
@end

@interface VSNeonButton : UIButton
@end
@implementation VSNeonButton
+ (Class)layerClass { return [CAGradientLayer class]; }
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        CAGradientLayer *g = (CAGradientLayer *)self.layer;
        g.colors = @[(id)VS_CYAN.CGColor, (id)VS_VIOLET.CGColor];
        g.startPoint = CGPointMake(0, 0.5);
        g.endPoint = CGPointMake(1, 0.5);
        self.layer.cornerRadius = 14;
        self.clipsToBounds = YES;
        self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        [self setTitleColor:VS_INK forState:UIControlStateNormal];
        [self setTitleColor:[VS_INK colorWithAlphaComponent:0.5] forState:UIControlStateDisabled];
    }
    return self;
}
- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1 : 0.55;
}
@end

static UILabel *VSLabel(NSString *text, CGFloat size, UIFontWeight w, UIColor *color, NSTextAlignment al) {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:size weight:w];
    l.textColor = color;
    l.textAlignment = al;
    l.numberOfLines = 0;
    return l;
}

static UIImage *VSSymbol(NSString *name, CGFloat pt, UIFontWeight w) {
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightSemibold];
    (void)w;
    return [UIImage systemImageNamed:name withConfiguration:c];
}

static void VSHaptic(UIImpactFeedbackStyle st) {
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:st];
    [g impactOccurred];
}

#pragma mark - VSLogoView

@interface VSLogoView : UIView
@end
@implementation VSLogoView {
    VSGradientView *_ring;
    UIVisualEffectView *_core;
    UIImageView *_icon;
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.shadowColor = VS_CYAN.CGColor;
        self.layer.shadowRadius = 14;
        self.layer.shadowOpacity = 0.55;
        self.layer.shadowOffset = CGSizeZero;

        _ring = [[VSGradientView alloc] initWithFrame:self.bounds];
        [_ring setColors:@[VS_CYAN, VS_VIOLET, VS_PINK] start:CGPointMake(0, 0) end:CGPointMake(1, 1)];
        _ring.layer.cornerRadius = f.size.width / 2;
        _ring.clipsToBounds = YES;
        [self addSubview:_ring];

        UIBlurEffect *be = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
        _core = [[UIVisualEffectView alloc] initWithEffect:be];
        _core.frame = CGRectInset(self.bounds, 2.5, 2.5);
        _core.layer.cornerRadius = _core.bounds.size.width / 2;
        _core.clipsToBounds = YES;
        _core.contentView.backgroundColor = [VS_INK colorWithAlphaComponent:0.72];
        [self addSubview:_core];

        _icon = [[UIImageView alloc] initWithFrame:CGRectInset(_core.bounds, 11, 11)];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        UIImage *custom = [VSLogoView loadCustomLogo];
        if (custom) { _icon.image = custom; _icon.layer.cornerRadius = _icon.bounds.size.width / 2; _icon.clipsToBounds = YES; }
        else { _icon.image = VSSymbol(@"sparkles", 20, UIFontWeightBold); _icon.tintColor = [UIColor whiteColor]; }
        [_core.contentView addSubview:_icon];
    }
    return self;
}
+ (UIImage *)loadCustomLogo {
    NSMutableArray *paths = [NSMutableArray array];
    [paths addObject:[[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"VideoStarToolLogo.png"]];
    [paths addObject:[[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"VideoStarToolLogo.png"]];
    Dl_info info;
    if (dladdr((const void *)&VSLog, &info) && info.dli_fname) {
        NSString *dir = [[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent];
        [paths addObject:[dir stringByAppendingPathComponent:@"VideoStarToolLogo.png"]];
    }
    for (NSString *p in paths) {
        UIImage *im = [UIImage imageWithContentsOfFile:p];
        if (im) return im;
    }
    return nil;
}
- (void)startAnimations {
    if (![_ring.layer animationForKey:@"spin"]) {
        CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        spin.fromValue = @0; spin.toValue = @(M_PI * 2);
        spin.duration = 7; spin.repeatCount = HUGE_VALF;
        [_ring.layer addAnimation:spin forKey:@"spin"];
    }
    if (![self.layer animationForKey:@"glow"]) {
        CABasicAnimation *glow = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
        glow.fromValue = @0.30; glow.toValue = @0.85;
        glow.duration = 1.8; glow.autoreverses = YES; glow.repeatCount = HUGE_VALF;
        glow.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.layer addAnimation:glow forKey:@"glow"];
    }
}
- (void)didMoveToWindow { [super didMoveToWindow]; if (self.window) [self startAnimations]; }
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    return CGRectContainsPoint(CGRectInset(self.bounds, -8, -8), p);
}
@end

#pragma mark - VSQRCaptureProxy

@interface VSQRCaptureProxy : NSObject
@property (nonatomic, weak) id target;
@property (nonatomic, copy) void (^captured)(id data, id code);
@end
@implementation VSQRCaptureProxy
- (BOOL)respondsToSelector:(SEL)s { return [super respondsToSelector:s] || [self.target respondsToSelector:s]; }
- (id)forwardingTargetForSelector:(SEL)s {
    if ([self.target respondsToSelector:s]) return self.target;
    return [super forwardingTargetForSelector:s];
}
- (id)dataToShare {
    id t = self.target;
    return [t respondsToSelector:_cmd] ? ((id (*)(id, SEL))objc_msgSend)(t, _cmd) : nil;
}
- (void)importedData:(id)data code:(id)code {
    void (^cb)(id, id) = self.captured;
    if (cb) cb(data, code);
}
- (void)setActivityiPadPopup:(id)p {
    id t = self.target;
    if ([t respondsToSelector:_cmd]) ((void (*)(id, SEL, id))objc_msgSend)(t, _cmd, p);
}
- (id)codePrefix {
    id t = self.target;
    id r = [t respondsToSelector:_cmd] ? ((id (*)(id, SEL))objc_msgSend)(t, _cmd) : nil;
    return r ?: @"";
}
- (id)qrLabel {
    id t = self.target;
    id r = [t respondsToSelector:_cmd] ? ((id (*)(id, SEL))objc_msgSend)(t, _cmd) : nil;
    return r ?: @"";
}
- (id)qrSetupLabel {
    id t = self.target;
    id r = [t respondsToSelector:_cmd] ? ((id (*)(id, SEL))objc_msgSend)(t, _cmd) : nil;
    return r ?: @"";
}
- (id)qrImage {
    id t = self.target;
    return [t respondsToSelector:_cmd] ? ((id (*)(id, SEL))objc_msgSend)(t, _cmd) : nil;
}
- (id)qrIcon {
    id t = self.target;
    return [t respondsToSelector:_cmd] ? ((id (*)(id, SEL))objc_msgSend)(t, _cmd) : nil;
}
- (BOOL)validCode:(id)code {
    id t = self.target;
    return [t respondsToSelector:_cmd] ? ((BOOL (*)(id, SEL, id))objc_msgSend)(t, _cmd, code) : YES;
}
@end

#pragma mark - Overlay interface

@class VSToolOverlay;

@interface VSToolOverlay : UIView <UIGestureRecognizerDelegate>
- (void)handlePickedResponse:(id)resp editor:(id)editor;
- (void)handleNativeMergeImportedData:(id)data editor:(id)editor code:(id)code;
- (void)ensureOnTop;
@end

static __weak VSToolOverlay *sOverlay = nil;

@implementation VSToolOverlay {
    VSLogoView *_logo;
    UIView *_panel;
    UIVisualEffectView *_blur;
    UIView *_header;
    UIButton *_closeButton;
    UIView *_tabBar;
    VSGradientView *_tabIndicator;
    NSArray<UIButton *> *_tabButtons;
    UIView *_contentHost;
    NSArray<UIView *> *_pages;
    UILabel *_footer;
    NSMutableArray<UISwitch *> *_switches;
    NSInteger _selectedTab;
    BOOL _panelBuilt;
    BOOL _panelOpen;
    BOOL _nativeHidden;

    UIView *_dim;
    UIVisualEffectView *_flowCard;
    UILabel *_flowTitle;
    UILabel *_flowMessage;
    UIScrollView *_flowScroll;
    UIImageView *_flowImage;
    VSNeonButton *_flowPrimary;
    UIButton *_flowSecondary;
    BOOL _flowVisible;
    BOOL _flowFull;
    BOOL _flowBanner;

    NSInteger _activeFeature;
    NSInteger _generation;

    id _mediaEditor;
    BOOL _mediaPickerHandled;
    BOOL _mediaSawPresented;
    NSTimeInterval _mediaStart;
    id _pickedResponse;
    NSInteger _pickedLayerIndex;
    BOOL _replaying;

    BOOL _beatRunning;
    UIView *_beatView;
    id _beatProject;
    NSUInteger _beatSceneBefore, _beatQueued, _beatGuard, _beatNoAdvance;
    CMTime _beatLastTime;

    id _mergeReviewVC;
    NSUInteger _mergeOrigLastViewed;
    id _mergeProject;
    NSUInteger _mergeStart, _mergeEnd;
    NSMutableArray *_mergePresets;
    NSMutableArray *_mergeImages;
    BOOL _mergeRangeLocked;
    BOOL _mergeAwaitingMediaPick;
    BOOL _mergeWaitingImport;
    id _mergeImportEditor;
    NSUInteger _mergeImportOffset;
    NSTimeInterval _mergeQRStart;
    id _pendingResponse;
    id _qrPrevDelegate;
    VSQRCaptureProxy *_qrProxy;
    NSMutableArray *_flowRowViews;
    NSMutableArray<UIImageView *> *_flowRowThumbs;
}

#pragma mark Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        sOverlay = self;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _activeFeature = VSFeatureNone;
        _pickedLayerIndex = -1;
        _beatLastTime = kCMTimeInvalid;
        _mergePresets = [NSMutableArray array];
        _mergeImages = [NSMutableArray array];
        _switches = [NSMutableArray array];
        _flowRowThumbs = [NSMutableArray array];

        _logo = [[VSLogoView alloc] initWithFrame:CGRectMake(0, 0, 56, 56)];
        [self addSubview:_logo];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleLogoPan:)];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleLogoTap:)];
        [_logo addGestureRecognizer:pan];
        [_logo addGestureRecognizer:tap];
        [tap requireGestureRecognizerToFail:pan];

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        CGFloat x = [ud objectForKey:@"VSTool.logo.x"] ? [ud floatForKey:@"VSTool.logo.x"] : -1;
        CGFloat y = [ud objectForKey:@"VSTool.logo.y"] ? [ud floatForKey:@"VSTool.logo.y"] : -1;
        if (x < 0 || y < 0) { x = frame.size.width - 40; y = frame.size.height * 0.35; }
        _logo.center = CGPointMake(x, y);
    }
    return self;
}

- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    for (UIView *v in self.subviews) {
        if (!v.hidden && v.alpha > 0.01 && v.userInteractionEnabled && CGRectContainsPoint(v.frame, p)) return YES;
    }
    return NO;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self clampLogo];
    if (_panelBuilt && _panelOpen) [self clampPanel];
    if (_flowVisible) [self layoutFlow];
}

- (void)ensureOnTop {
    if (self.subviews.lastObject == _logo) return;
    [self bringSubviewToFront:_logo];
    if (_panel.superview) [self bringSubviewToFront:_panel];
    if (_dim.superview) { [self bringSubviewToFront:_dim]; [self bringSubviewToFront:_flowCard]; [self bringSubviewToFront:_logo]; }
}

#pragma mark Logo

- (UIEdgeInsets)safeInsets {
    UIEdgeInsets i = self.safeAreaInsets;
    i.top = MAX(i.top, 20);
    return i;
}

- (void)clampLogo {
    UIEdgeInsets si = [self safeInsets];
    CGFloat r = _logo.bounds.size.width / 2 + 6;
    CGPoint c = _logo.center;
    c.x = MIN(MAX(c.x, r), self.bounds.size.width - r);
    c.y = MIN(MAX(c.y, si.top + r), self.bounds.size.height - si.bottom - r);
    _logo.center = c;
}

- (void)handleLogoTap:(UITapGestureRecognizer *)g {
    VSHaptic(UIImpactFeedbackStyleLight);
    if (_nativeHidden) { [self restoreAfterNativeUI]; return; }
    if (_panelOpen) [self closePanel]; else [self openPanel];
}

- (void)handleLogoPan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan && _panelOpen) [self closePanel];
    CGPoint t = [g translationInView:self];
    _logo.center = CGPointMake(_logo.center.x + t.x, _logo.center.y + t.y);
    [g setTranslation:CGPointZero inView:self];
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        [self clampLogo];
        CGFloat edgeX = (_logo.center.x < self.bounds.size.width / 2) ? 34 : self.bounds.size.width - 34;
        CGPoint target = CGPointMake(edgeX, _logo.center.y);
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.8
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:^{ self->_logo.center = target; } completion:nil];
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setFloat:target.x forKey:@"VSTool.logo.x"];
        [ud setFloat:target.y forKey:@"VSTool.logo.y"];
    }
}

#pragma mark Panel

- (CGSize)panelSize {
    UIEdgeInsets si = [self safeInsets];
    CGFloat w = MIN(348, self.bounds.size.width - 24);
    CGFloat h = MIN(468, self.bounds.size.height - si.top - si.bottom - 24);
    return CGSizeMake(w, MAX(h, 320));
}

- (void)buildPanelIfNeeded {
    if (_panelBuilt) return;
    _panelBuilt = YES;
    CGSize ps = [self panelSize];
    _panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, ps.width, ps.height)];
    _panel.layer.shadowColor = VS_CYAN.CGColor;
    _panel.layer.shadowOpacity = 0.28;
    _panel.layer.shadowRadius = 28;
    _panel.layer.shadowOffset = CGSizeMake(0, 12);

    _blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    _blur.layer.cornerRadius = 28;
    _blur.clipsToBounds = YES;
    _blur.layer.borderWidth = 0.8;
    _blur.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
    _blur.contentView.backgroundColor = [VS_INK colorWithAlphaComponent:0.55];
    [_panel addSubview:_blur];

    VSGradientView *glow = [[VSGradientView alloc] init];
    [glow setColors:@[[VS_CYAN colorWithAlphaComponent:0.20], [UIColor clearColor], [VS_VIOLET colorWithAlphaComponent:0.16]]
              start:CGPointMake(0, 0) end:CGPointMake(1, 1)];
    glow.userInteractionEnabled = NO;
    glow.tag = 9001;
    [_blur.contentView addSubview:glow];

    _header = [UIView new];
    [_blur.contentView addSubview:_header];
    UILabel *title = VSLabel(@"VideoStar Tool", 18, UIFontWeightHeavy, [UIColor whiteColor], NSTextAlignmentLeft);
    title.tag = 9101;
    [_header addSubview:title];
    VSGradientView *badge = [VSGradientView new];
    badge.tag = 9102;
    [badge setColors:@[VS_PINK, VS_VIOLET] start:CGPointMake(0, 0.5) end:CGPointMake(1, 0.5)];
    badge.layer.cornerRadius = 7; badge.clipsToBounds = YES;
    UILabel *vip = VSLabel(@"VIP", 9.5, UIFontWeightHeavy, [UIColor whiteColor], NSTextAlignmentCenter);
    vip.tag = 9103;
    [badge addSubview:vip];
    [_header addSubview:badge];
    UIPanGestureRecognizer *hp = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanelPan:)];
    [_header addGestureRecognizer:hp];

    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_closeButton setImage:VSSymbol(@"xmark", 12, UIFontWeightBold) forState:UIControlStateNormal];
    _closeButton.tintColor = VS_TEXT2;
    _closeButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    _closeButton.layer.cornerRadius = 14;
    [_closeButton addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [_blur.contentView addSubview:_closeButton];

    _tabBar = [UIView new];
    _tabBar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    _tabBar.layer.cornerRadius = 21;
    [_blur.contentView addSubview:_tabBar];
    _tabIndicator = [VSGradientView new];
    [_tabIndicator setColors:@[VS_CYAN, VS_VIOLET] start:CGPointMake(0, 0.5) end:CGPointMake(1, 0.5)];
    _tabIndicator.layer.cornerRadius = 18;
    _tabIndicator.clipsToBounds = YES;
    [_tabBar addSubview:_tabIndicator];
    NSArray *tabTitles = @[@"Home", @"Function", @"Dev"];
    NSArray *tabIcons = @[@"house.fill", @"bolt.fill", @"person.crop.circle.fill"];
    NSMutableArray *btns = [NSMutableArray array];
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        if (@available(iOS 15.0, *)) {
            UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
            cfg.image = VSSymbol(tabIcons[i], 12, UIFontWeightSemibold);
            cfg.title = tabTitles[i];
            cfg.imagePadding = 5;
            cfg.contentInsets = NSDirectionalEdgeInsetsMake(0, 4, 0, 4);
            cfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attrs) {
                NSMutableDictionary *d = [attrs mutableCopy];
                d[NSFontAttributeName] = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
                return d;
            };
            b.configuration = cfg;
        } else {
            [b setImage:VSSymbol(tabIcons[i], 12, UIFontWeightSemibold) forState:UIControlStateNormal];
            [b setTitle:tabTitles[i] forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
            b.tintColor = VS_TEXT2;
            [b setTitleColor:VS_TEXT2 forState:UIControlStateNormal];
        }
        b.tag = i;
        [b addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_tabBar addSubview:b];
        [btns addObject:b];
    }
    _tabButtons = btns;

    _contentHost = [UIView new];
    _contentHost.clipsToBounds = YES;
    [_blur.contentView addSubview:_contentHost];
    UIView *home = [self buildHomePage];
    UIScrollView *func = [self buildFunctionPage];
    UIView *dev = [self buildDevPage];
    _pages = @[home, func, dev];
    for (UIView *p in _pages) { [_contentHost addSubview:p]; p.hidden = YES; }
    _selectedTab = 0;
    ((UIView *)_pages[0]).hidden = NO;

    _footer = VSLabel([NSString stringWithFormat:@"VideoStar Tool  •  %@", VS_TOOL_VERSION], 10.5, UIFontWeightMedium, VS_TEXT3, NSTextAlignmentCenter);
    [_blur.contentView addSubview:_footer];

    [self layoutPanelContents];
    [self updateTabAppearance];
}

- (UIView *)buildHomePage {
    UIView *v = [UIView new];
    UILabel *hi = VSLabel(@"Xin chào!", 26, UIFontWeightHeavy, [UIColor whiteColor], NSTextAlignmentLeft);
    hi.tag = 1001;
    [v addSubview:hi];
    UILabel *desc = VSLabel(@"Đây là VideoStar Tool, công cụ giúp bạn sử dụng Video Star thuận tiện, nhanh chóng và dễ dàng hơn.",
                            14, UIFontWeightRegular, VS_TEXT2, NSTextAlignmentLeft);
    desc.tag = 1002;
    [v addSubview:desc];
    NSArray *chips = @[@[@"photo.on.rectangle.angled", @"Auto ảnh"], @[@"qrcode", @"Last code"],
                       @[@"waveform.path", @"Chia beat"], @[@"square.stack.3d.up.fill", @"Nhiều cảnh"]];
    for (NSInteger i = 0; i < 4; i++) {
        UIControl *c = [UIControl new];
        c.tag = 1100 + i;
        c.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        c.layer.cornerRadius = 16;
        c.layer.borderWidth = 0.6;
        c.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
        UIImageView *iv = [[UIImageView alloc] initWithImage:VSSymbol(chips[i][0], 16, UIFontWeightSemibold)];
        iv.tintColor = (i % 2 == 0) ? VS_CYAN : VS_VIOLET;
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.tag = 1;
        [c addSubview:iv];
        UILabel *l = VSLabel(chips[i][1], 13, UIFontWeightSemibold, [UIColor whiteColor], NSTextAlignmentLeft);
        l.tag = 2;
        [c addSubview:l];
        [c addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [c addTarget:self action:@selector(chipDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [c addTarget:self action:@selector(chipUp:) forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit | UIControlEventTouchUpInside];
        [v addSubview:c];
    }
    UILabel *ver = VSLabel([NSString stringWithFormat:@"Phiên bản đang sử dụng: %@", VS_TOOL_VERSION], 11.5, UIFontWeightMedium, VS_CYAN, NSTextAlignmentCenter);
    ver.tag = 1003;
    [v addSubview:ver];
    return v;
}

- (UIScrollView *)buildFunctionPage {
    UIScrollView *sv = [UIScrollView new];
    sv.showsVerticalScrollIndicator = NO;
    sv.alwaysBounceVertical = YES;
    NSArray *items = @[
        @[@"photo.on.rectangle.angled", @"Auto nhập ảnh vào các lớp", @"Thay ảnh/video cho mọi lớp media cùng loại"],
        @[@"qrcode.viewfinder", @"Hiển thị code gần nhất", @"Xem lại ảnh code QR vừa nhập"],
        @[@"waveform.path", @"Auto chia beat", @"Tự đặt điểm chia theo từng beat"],
        @[@"square.stack.3d.up.fill", @"Auto code + ảnh nhiều phân cảnh", @"Nhập hàng loạt code cho nhiều phân cảnh"],
    ];
    NSArray *colors = @[@[VS_CYAN, VS_VIOLET], @[VS_VIOLET, VS_PINK], @[VS_PINK, [UIColor colorWithRed:1 green:0.62 blue:0.2 alpha:1]], @[VS_CYAN, [UIColor colorWithRed:0.2 green:0.9 blue:0.6 alpha:1]]];
    for (NSInteger i = 0; i < 4; i++) {
        UIView *row = [UIView new];
        row.tag = 2000 + i;
        row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        row.layer.cornerRadius = 18;
        row.layer.borderWidth = 0.6;
        row.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
        VSGradientView *tile = [VSGradientView new];
        tile.tag = 1;
        [tile setColors:colors[i] start:CGPointMake(0, 0) end:CGPointMake(1, 1)];
        tile.layer.cornerRadius = 12; tile.clipsToBounds = YES;
        UIImageView *iv = [[UIImageView alloc] initWithImage:VSSymbol(items[i][0], 17, UIFontWeightSemibold)];
        iv.tintColor = [UIColor whiteColor];
        iv.contentMode = UIViewContentModeCenter;
        iv.tag = 11;
        [tile addSubview:iv];
        [row addSubview:tile];
        UILabel *t = VSLabel(items[i][1], 14, UIFontWeightSemibold, [UIColor whiteColor], NSTextAlignmentLeft);
        t.numberOfLines = 2; t.tag = 2;
        [row addSubview:t];
        UILabel *s = VSLabel(items[i][2], 11, UIFontWeightRegular, VS_TEXT3, NSTextAlignmentLeft);
        s.numberOfLines = 2; s.tag = 3;
        [row addSubview:s];
        UISwitch *sw = [UISwitch new];
        sw.onTintColor = VS_CYAN;
        sw.transform = CGAffineTransformMakeScale(0.82, 0.82);
        [sw addTarget:self action:@selector(featureSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        sw.tag = 100 + i;
        [row addSubview:sw];
        [_switches addObject:sw];
        [sv addSubview:row];
    }
    return sv;
}

- (UIView *)buildDevPage {
    UIView *v = [UIView new];
    VSGradientView *av = [VSGradientView new];
    av.tag = 3001;
    [av setColors:@[VS_CYAN, VS_VIOLET, VS_PINK] start:CGPointMake(0, 0) end:CGPointMake(1, 1)];
    av.layer.cornerRadius = 38; av.clipsToBounds = YES;
    UILabel *h = VSLabel(@"H", 34, UIFontWeightHeavy, [UIColor whiteColor], NSTextAlignmentCenter);
    h.tag = 1;
    [av addSubview:h];
    [v addSubview:av];
    UILabel *cap = VSLabel(@"Người tạo ra sản phẩm này là", 12, UIFontWeightMedium, VS_TEXT3, NSTextAlignmentCenter);
    cap.tag = 3002; [v addSubview:cap];
    UILabel *name = VSLabel(@"hson", 30, UIFontWeightHeavy, [UIColor whiteColor], NSTextAlignmentCenter);
    name.tag = 3003; [v addSubview:name];
    UILabel *full = VSLabel(@"Hoàng Văn Sơn", 14.5, UIFontWeightMedium, VS_CYAN, NSTextAlignmentCenter);
    full.tag = 3004; [v addSubview:full];
    UILabel *role = VSLabel(@"Developer  •  VideoStar Tool", 11.5, UIFontWeightSemibold, VS_TEXT2, NSTextAlignmentCenter);
    role.tag = 3005;
    role.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    role.layer.cornerRadius = 12; role.clipsToBounds = YES;
    [v addSubview:role];

    UIButton *reload = [UIButton buttonWithType:UIButtonTypeSystem];
    reload.tag = 3100;
    [reload setTitle:@"Reload hooks" forState:UIControlStateNormal];
    [reload setTitleColor:VS_CYAN forState:UIControlStateNormal];
    reload.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    reload.layer.borderWidth = 1;
    reload.layer.borderColor = VS_CYAN.CGColor;
    reload.layer.cornerRadius = 12;
    reload.clipsToBounds = YES;
    [reload addTarget:self action:@selector(reloadHooksTapped) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:reload];
    return v;
}

- (void)reloadHooksTapped {
    VSHaptic(UIImpactFeedbackStyleMedium);
    VSInstallHooksForce();
}

- (void)layoutPanelContents {
    if (!_panelBuilt) return;
    CGSize ps = _panel.bounds.size;
    CGFloat W = ps.width, H = ps.height;
    _blur.frame = _panel.bounds;
    [_blur.contentView viewWithTag:9001].frame = _blur.bounds;

    _header.frame = CGRectMake(0, 0, W - 56, 58);
    UILabel *title = (UILabel *)[_header viewWithTag:9101];
    [title sizeToFit];
    title.frame = CGRectMake(20, 18, title.bounds.size.width, 24);
    UIView *badge = [_header viewWithTag:9102];
    badge.frame = CGRectMake(CGRectGetMaxX(title.frame) + 8, 22, 32, 16);
    [badge viewWithTag:9103].frame = badge.bounds;
    _closeButton.frame = CGRectMake(W - 16 - 28, 15, 28, 28);

    CGFloat cw = W - 32;
    _tabBar.frame = CGRectMake(16, 60, cw, 42);
    CGFloat tw = (cw - 6) / 3;
    for (NSInteger i = 0; i < 3; i++) _tabButtons[i].frame = CGRectMake(3 + i * tw, 3, tw, 36);
    _tabIndicator.frame = CGRectMake(3 + _selectedTab * tw, 3, tw, 36);

    CGFloat footerH = 22;
    _contentHost.frame = CGRectMake(16, 114, cw, H - 114 - footerH - 10);
    _footer.frame = CGRectMake(0, H - footerH - 8, W, footerH);
    CGRect pageFrame = _contentHost.bounds;
    for (UIView *p in _pages) p.frame = pageFrame;

    UIView *home = _pages[0];
    UILabel *hi = (UILabel *)[home viewWithTag:1001];
    hi.frame = CGRectMake(2, 2, cw, 32);
    UILabel *desc = (UILabel *)[home viewWithTag:1002];
    CGSize ds = [desc sizeThatFits:CGSizeMake(cw - 4, CGFLOAT_MAX)];
    desc.frame = CGRectMake(2, 42, cw - 4, ds.height);
    CGFloat gy = CGRectGetMaxY(desc.frame) + 16;
    CGFloat cwid = (cw - 10) / 2, chh = 62;
    for (NSInteger i = 0; i < 4; i++) {
        UIView *c = [home viewWithTag:1100 + i];
        c.frame = CGRectMake((i % 2) * (cwid + 10), gy + (i / 2) * (chh + 10), cwid, chh);
        [c viewWithTag:1].frame = CGRectMake(14, (chh - 20) / 2, 22, 20);
        [c viewWithTag:2].frame = CGRectMake(44, 0, cwid - 52, chh);
    }
    UILabel *ver = (UILabel *)[home viewWithTag:1003];
    ver.frame = CGRectMake(0, pageFrame.size.height - 20, cw, 18);

    UIScrollView *func = (UIScrollView *)_pages[1];
    CGFloat rh = 74, gap = 10;
    for (NSInteger i = 0; i < 4; i++) {
        UIView *row = [func viewWithTag:2000 + i];
        row.frame = CGRectMake(0, i * (rh + gap), cw, rh);
        [row viewWithTag:1].frame = CGRectMake(12, (rh - 40) / 2, 40, 40);
        [row viewWithTag:11].frame = [row viewWithTag:1].bounds;
        CGFloat tx = 64, sww = 58;
        [row viewWithTag:2].frame = CGRectMake(tx, 12, cw - tx - sww - 6, 34);
        [row viewWithTag:3].frame = CGRectMake(tx, 12 + 34 - 2, cw - tx - sww - 6, 26);
        UISwitch *sw = _switches[i];
        sw.center = CGPointMake(cw - 12 - sw.bounds.size.width * 0.82 / 2, rh / 2);
    }
    func.contentSize = CGSizeMake(cw, 4 * (rh + gap));

    UIView *dev = _pages[2];
    CGFloat cx = cw / 2, y0 = MAX(0, (pageFrame.size.height - 270) / 2);
    [dev viewWithTag:3001].frame = CGRectMake(cx - 38, y0, 76, 76);
    [[dev viewWithTag:3001] viewWithTag:1].frame = CGRectMake(0, 0, 76, 76);
    [dev viewWithTag:3002].frame = CGRectMake(0, y0 + 90, cw, 16);
    [dev viewWithTag:3003].frame = CGRectMake(0, y0 + 108, cw, 38);
    [dev viewWithTag:3004].frame = CGRectMake(0, y0 + 148, cw, 20);
    [dev viewWithTag:3005].frame = CGRectMake(cx - 100, y0 + 180, 200, 26);
    [dev viewWithTag:3100].frame = CGRectMake(cx - 80, y0 + 216, 160, 34);
}

- (void)updateTabAppearance {
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *b = _tabButtons[i];
        if (@available(iOS 15.0, *)) {
            UIButtonConfiguration *c = b.configuration;
            c.baseForegroundColor = (i == _selectedTab) ? VS_INK : VS_TEXT2;
            b.configuration = c;
        } else {
            UIColor *col = (i == _selectedTab) ? VS_INK : VS_TEXT2;
            [b setTitleColor:col forState:UIControlStateNormal];
            b.tintColor = col;
        }
    }
}

- (void)tabTapped:(UIButton *)b {
    VSHaptic(UIImpactFeedbackStyleLight);
    [self selectTab:b.tag animated:YES];
}

- (void)selectTab:(NSInteger)idx animated:(BOOL)animated {
    if (idx == _selectedTab || idx < 0 || idx > 2) return;
    UIView *old = _pages[_selectedTab], *nw = _pages[idx];
    CGFloat dir = idx > _selectedTab ? 1 : -1;
    _selectedTab = idx;
    CGFloat tw = (_tabBar.bounds.size.width - 6) / 3;
    nw.hidden = NO;
    nw.alpha = 0;
    nw.transform = CGAffineTransformMakeTranslation(26 * dir, 0);
    [self updateTabAppearance];
    void (^anim)(void) = ^{
        nw.alpha = 1; nw.transform = CGAffineTransformIdentity;
        old.alpha = 0; old.transform = CGAffineTransformMakeTranslation(-26 * dir, 0);
        self->_tabIndicator.frame = CGRectMake(3 + idx * tw, 3, tw, 36);
    };
    void (^done)(BOOL) = ^(BOOL f) { old.hidden = YES; old.alpha = 1; old.transform = CGAffineTransformIdentity; };
    if (animated) {
        [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.4
                            options:UIViewAnimationOptionAllowUserInteraction animations:anim completion:done];
    } else { anim(); done(YES); }
}

- (void)chipDown:(UIControl *)c {
    [UIView animateWithDuration:0.15 animations:^{ c.transform = CGAffineTransformMakeScale(0.95, 0.95); c.alpha = 0.8; }];
}
- (void)chipUp:(UIControl *)c {
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.5 options:0
                     animations:^{ c.transform = CGAffineTransformIdentity; c.alpha = 1; } completion:nil];
}
- (void)chipTapped:(UIControl *)c { VSHaptic(UIImpactFeedbackStyleLight); [self selectTab:1 animated:YES]; }

- (void)clampPanel {
    if (!_panel) return;
    UIEdgeInsets si = [self safeInsets];
    CGSize s = _panel.bounds.size;
    CGPoint c = _panel.center;
    c.x = MIN(MAX(c.x, s.width / 2 + 8), self.bounds.size.width - s.width / 2 - 8);
    c.y = MIN(MAX(c.y, si.top + s.height / 2 + 4), self.bounds.size.height - si.bottom - s.height / 2 - 4);
    _panel.center = c;
}

- (void)handlePanelPan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self];
    _panel.center = CGPointMake(_panel.center.x + t.x, _panel.center.y + t.y);
    [g setTranslation:CGPointZero inView:self];
    if (g.state == UIGestureRecognizerStateEnded) {
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0
                         animations:^{ [self clampPanel]; } completion:nil];
    }
}

- (void)openPanel {
    if (_panelOpen) return;
    [self buildPanelIfNeeded];
    CGSize ps = [self panelSize];
    _panel.transform = CGAffineTransformIdentity;
    _panel.bounds = CGRectMake(0, 0, ps.width, ps.height);
    [self layoutPanelContents];

    UIEdgeInsets si = [self safeInsets];
    CGPoint lc = _logo.center;
    CGFloat x = MIN(MAX(lc.x - ps.width / 2, 12), self.bounds.size.width - ps.width - 12);
    CGFloat y = (lc.y < self.bounds.size.height / 2) ? CGRectGetMaxY(_logo.frame) + 12 : CGRectGetMinY(_logo.frame) - 12 - ps.height;
    y = MIN(MAX(y, si.top + 6), self.bounds.size.height - si.bottom - ps.height - 6);
    _panel.frame = CGRectMake(x, y, ps.width, ps.height);

    _panelOpen = YES;
    [self addSubview:_panel];
    [self bringSubviewToFront:_logo];
    CGPoint pc = _panel.center;
    _panel.alpha = 0;
    _panel.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.2, 0.2),
                                               CGAffineTransformMakeTranslation(lc.x - pc.x, lc.y - pc.y));
    [UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:0.76 initialSpringVelocity:0.7
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self->_panel.alpha = 1; self->_panel.transform = CGAffineTransformIdentity; } completion:nil];
    [self syncSwitches];
}

- (void)closePanel {
    if (!_panelOpen) return;
    _panelOpen = NO;
    CGPoint lc = _logo.center, pc = _panel.center;
    [UIView animateWithDuration:0.26 delay:0 options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->_panel.alpha = 0;
        self->_panel.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.2, 0.2),
                                                         CGAffineTransformMakeTranslation(lc.x - pc.x, lc.y - pc.y));
    } completion:^(BOOL f) {
        if (!self->_panelOpen) [self->_panel removeFromSuperview];
    }];
}

- (void)syncSwitches {
    for (NSUInteger i = 0; i < _switches.count; i++) {
        BOOL on = (_activeFeature == (NSInteger)i);
        if (_switches[i].isOn != on) [_switches[i] setOn:on animated:NO];
    }
}

- (void)setFeatureState:(NSInteger)idx on:(BOOL)on {
    if (idx < 0 || idx >= (NSInteger)_switches.count) return;
    [_switches[idx] setOn:on animated:YES];
}

#pragma mark Flow card

- (void)ensureFlowViews {
    if (_dim) return;
    _dim = [[UIView alloc] init];
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    _dim.alpha = 0;
    _dim.hidden = YES;

    _flowCard = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    _flowCard.layer.cornerRadius = 26;
    _flowCard.clipsToBounds = YES;
    _flowCard.layer.borderWidth = 0.8;
    _flowCard.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    _flowCard.contentView.backgroundColor = [VS_INK colorWithAlphaComponent:0.62];
    _flowCard.alpha = 0;
    _flowCard.hidden = YES;

    _flowTitle = VSLabel(@"", 19, UIFontWeightHeavy, [UIColor whiteColor], NSTextAlignmentCenter);
    [_flowCard.contentView addSubview:_flowTitle];
    _flowMessage = VSLabel(@"", 14, UIFontWeightRegular, VS_TEXT2, NSTextAlignmentCenter);
    [_flowCard.contentView addSubview:_flowMessage];
    _flowImage = [UIImageView new];
    _flowImage.contentMode = UIViewContentModeScaleAspectFit;
    _flowImage.layer.cornerRadius = 14;
    _flowImage.clipsToBounds = YES;
    _flowImage.backgroundColor = [UIColor colorWithWhite:1 alpha:0.96];
    _flowImage.hidden = YES;
    [_flowCard.contentView addSubview:_flowImage];
    _flowScroll = [UIScrollView new];
    _flowScroll.showsVerticalScrollIndicator = NO;
    _flowScroll.hidden = YES;
    [_flowCard.contentView addSubview:_flowScroll];

    _flowPrimary = [[VSNeonButton alloc] initWithFrame:CGRectZero];
    [_flowPrimary addTarget:self action:@selector(flowPrimaryTapped) forControlEvents:UIControlEventTouchUpInside];
    [_flowCard.contentView addSubview:_flowPrimary];
    _flowSecondary = [UIButton buttonWithType:UIButtonTypeSystem];
    _flowSecondary.backgroundColor = [UIColor colorWithWhite:1 alpha:0.09];
    _flowSecondary.layer.cornerRadius = 14;
    _flowSecondary.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [_flowSecondary setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_flowSecondary addTarget:self action:@selector(flowSecondaryTapped) forControlEvents:UIControlEventTouchUpInside];
    [_flowCard.contentView addSubview:_flowSecondary];
}

- (void)showFlowTitle:(NSString *)title message:(NSString *)msg primary:(NSString *)primary secondary:(NSString *)secondary full:(BOOL)full {
    [self showFlowTitle:title message:msg primary:primary secondary:secondary full:full banner:NO];
}

- (void)showFlowTitle:(NSString *)title message:(NSString *)msg primary:(NSString *)primary secondary:(NSString *)secondary full:(BOOL)full banner:(BOOL)banner {
    [self ensureFlowViews];
    _flowBanner = banner;
    _dim.userInteractionEnabled = !banner;
    _flowTitle.text = title ?: @"";
    _flowMessage.text = msg ?: @"";
    [_flowPrimary setTitle:primary forState:UIControlStateNormal];
    [_flowSecondary setTitle:secondary forState:UIControlStateNormal];
    _flowPrimary.hidden = (primary.length == 0);
    _flowSecondary.hidden = (secondary.length == 0);
    _flowPrimary.enabled = YES;
    _flowImage.hidden = YES;
    _flowScroll.hidden = !full;
    _flowFull = full;
    BOOL first = !_flowVisible;
    _flowVisible = YES;
    _nativeHidden = NO;
    if (!_dim.superview) { [self addSubview:_dim]; [self addSubview:_flowCard]; }
    _dim.frame = self.bounds;
    _dim.hidden = banner;
    _flowCard.hidden = NO;
    [self layoutFlow];
    [self bringSubviewToFront:_dim];
    [self bringSubviewToFront:_flowCard];
    [self bringSubviewToFront:_logo];
    if (first) {
        _flowCard.transform = CGAffineTransformMakeScale(0.88, 0.88);
        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.6
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:^{ self->_dim.alpha = banner ? 0 : 1; self->_flowCard.alpha = 1; self->_flowCard.transform = CGAffineTransformIdentity; }
                         completion:nil];
    } else {
        [UIView transitionWithView:_flowCard duration:0.22 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{} completion:nil];
        _dim.alpha = banner ? 0 : 1; _flowCard.alpha = 1; _flowCard.transform = CGAffineTransformIdentity;
    }
}

- (void)layoutFlow {
    if (!_dim) return;
    _dim.frame = self.bounds;
    UIEdgeInsets si = [self safeInsets];
    CGFloat cw = MIN(344, self.bounds.size.width - 32);
    CGFloat pad = 20, inner = cw - pad * 2;
    CGFloat y = 22;
    CGSize ts = [_flowTitle sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)];
    _flowTitle.frame = CGRectMake(pad, y, inner, ts.height);
    y = CGRectGetMaxY(_flowTitle.frame) + 8;
    CGSize ms = [_flowMessage sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)];
    CGFloat msgH = _flowMessage.text.length ? ms.height : 0;
    _flowMessage.frame = CGRectMake(pad, y, inner, msgH);
    y = CGRectGetMaxY(_flowMessage.frame) + (msgH ? 14 : 0);

    BOOL hasBtn = !_flowPrimary.hidden || !_flowSecondary.hidden;
    CGFloat btnH = hasBtn ? 48 : 0;
    CGFloat maxH = self.bounds.size.height - si.top - si.bottom - 60;
    CGFloat extra = 0;
    if (!_flowImage.hidden) extra = MIN(inner, 250);
    if (_flowFull) extra = MIN(300, maxH - y - btnH - 40);
    CGRect area = CGRectMake(pad, y, inner, extra);
    _flowImage.frame = area;
    _flowScroll.frame = area;
    y += extra + (extra ? 14 : 0);
    if (hasBtn) {
        BOOL both = !_flowPrimary.hidden && !_flowSecondary.hidden;
        CGFloat bw = both ? (inner - 10) / 2 : inner;
        CGFloat x = pad;
        if (!_flowSecondary.hidden) { _flowSecondary.frame = CGRectMake(x, y, bw, 46); x += bw + 10; }
        if (!_flowPrimary.hidden) _flowPrimary.frame = CGRectMake(both ? x : pad, y, bw, 46);
        y += 46;
    }
    CGFloat ch = MIN(y + 20, maxH);
    _flowCard.bounds = CGRectMake(0, 0, cw, ch);
    if (_flowBanner) {
        _flowCard.center = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height - si.bottom - ch / 2 - 14);
    } else {
        _flowCard.center = CGPointMake(self.bounds.size.width / 2, si.top + (self.bounds.size.height - si.top - si.bottom) / 2);
    }
}

- (void)hideFlow {
    if (!_flowVisible) return;
    _flowVisible = NO;
    [UIView animateWithDuration:0.24 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_dim.alpha = 0; self->_flowCard.alpha = 0;
        self->_flowCard.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL f) {
        if (!self->_flowVisible) {
            self->_dim.hidden = YES; self->_flowCard.hidden = YES;
            self->_flowCard.transform = CGAffineTransformIdentity;
        }
    }];
}

#pragma mark Native-UI hand-off

- (void)hideToolOverlayForNativeUI {
    _nativeHidden = YES;
    [self closePanel];
    [UIView animateWithDuration:0.2 animations:^{ self->_dim.alpha = 0; self->_flowCard.alpha = 0; }
                     completion:^(BOOL f) { if (self->_nativeHidden) { self->_dim.hidden = YES; self->_flowCard.hidden = YES; } }];
    _logo.alpha = 0.55;
}

- (void)restoreAfterNativeUI {
    _nativeHidden = NO;
    _logo.alpha = 1;
    if (_flowVisible) {
        _dim.hidden = _flowBanner; _flowCard.hidden = NO;
        [UIView animateWithDuration:0.25 animations:^{ self->_dim.alpha = self->_flowBanner ? 0 : 1; self->_flowCard.alpha = 1; }];
        [self layoutFlow];
    }
    [self ensureOnTop];
}

#pragma mark Feature plumbing

- (void)featureSwitchChanged:(UISwitch *)sw {
    VSHaptic(UIImpactFeedbackStyleMedium);
    NSInteger idx = sw.tag - 100;
    [UIView animateWithDuration:0.12 animations:^{ sw.transform = CGAffineTransformMakeScale(0.95, 0.95); }
                     completion:^(BOOL f) {
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.8 options:0
                         animations:^{ sw.transform = CGAffineTransformMakeScale(0.82, 0.82); } completion:nil];
    }];
    if (!sw.isOn) {
        if (_activeFeature == idx) { [self cancelActiveFlow]; }
        return;
    }
    if (_activeFeature != VSFeatureNone && _activeFeature != idx) {
        NSInteger old = _activeFeature;
        [self cancelActiveFlow];
        [self setFeatureState:old on:NO];
    }
    _activeFeature = idx;
    _generation++;
    [self closePanel];
    switch (idx) {
        case VSFeatureMedia:    [self startFeatureReplaceMedia]; break;
        case VSFeatureLastCode: [self startFeatureLastCode]; break;
        case VSFeatureBeat:     [self startFeatureBeatSplit]; break;
        case VSFeatureMulti:    [self startFeatureMultiSceneApply]; break;
        default: break;
    }
}

- (void)finishFeature:(NSInteger)idx {
    _generation++;
    [self restoreAfterNativeUI];
    [self hideFlow];
    _activeFeature = VSFeatureNone;
    _beatRunning = NO;
    _replaying = NO;
    _mergeAwaitingMediaPick = NO;
    _mergeWaitingImport = NO;
    [self restoreQRDelegate];
    [self setFeatureState:idx on:NO];
}

- (void)cancelActiveFlow {
    NSInteger idx = _activeFeature;
    [self finishFeature:idx];
    _mediaEditor = nil; _pickedResponse = nil; _pendingResponse = nil;
    _beatView = nil; _beatProject = nil;
    if (_mergeReviewVC) {
        VSPerform(_mergeReviewVC, @selector(setLastViewedSceneIndex:), @[@(_mergeOrigLastViewed)]);
    }
    _mergeReviewVC = nil; _mergeProject = nil; _mergeRangeLocked = NO;
    [_mergePresets removeAllObjects]; [_mergeImages removeAllObjects];
}

- (void)restoreQRDelegate {
    if (!_qrProxy) return;
    Class qc = NSClassFromString(@"QRCodeManager");
    id mgr = VSInvoke(qc, @selector(sharedInstance), nil);
    if (mgr && VSKey(mgr, @"delegate") == _qrProxy) VSSetKey(mgr, @"delegate", _qrPrevDelegate);
    _qrProxy = nil; _qrPrevDelegate = nil;
}

- (void)showSimpleAlert:(NSString *)title message:(NSString *)msg index:(NSInteger)idx {
    [self finishFeature:idx];
    [self showFlowTitle:title ?: @"Thông báo" message:msg primary:@"OK" secondary:@"" full:NO];
}

- (void)showCompletion:(NSString *)title message:(NSString *)msg index:(NSInteger)idx {
    [self showSimpleAlert:title message:msg index:idx];
}

- (void)flowPrimaryTapped {
    VSHaptic(UIImpactFeedbackStyleLight);
    if (_activeFeature == VSFeatureMulti) {
        if (!_mergeRangeLocked) { [self beginMergeRangeFromNativePanel]; return; }
        NSUInteger count = (_mergeEnd >= _mergeStart) ? (_mergeEnd - _mergeStart + 1) : 0;
        NSUInteger got = 0;
        for (id p in _mergePresets) if (p != [NSNull null]) got++;
        if (count && got == count) [self beginNativeMediaChoiceForMergeProject];
        return;
    }
    if (_activeFeature == VSFeatureLastCode) { [self finishFeature:VSFeatureLastCode]; return; }
    [self hideFlow];
}

- (void)flowSecondaryTapped {
    VSHaptic(UIImpactFeedbackStyleLight);
    [self cancelActiveFlow];
}

#pragma mark - Feature 0

- (void)startFeatureReplaceMedia {
    UIViewController *top = VSTopVC();
    Class wiz = NSClassFromString(@"MultiLayerWizEffectVC");
    if (!top || !wiz || ![top isKindOfClass:wiz] || ![top respondsToSelector:@selector(pickNewContent)]) {
        [self showSimpleAlert:@"Thông báo"
                      message:@"Không tìm thấy bộ chọn nội dung gốc của Video Star. Hãy mở màn hình Nhiều lớp (Multi-layer) rồi bật lại."
                        index:VSFeatureMedia];
        return;
    }
    _mediaEditor = top;
    _pickedResponse = nil;
    _pickedLayerIndex = -1;
    _mediaPickerHandled = NO;
    _mediaSawPresented = NO;
    _mediaStart = CACurrentMediaTime();
    [self hideToolOverlayForNativeUI];
    [self waitForEditorReady:top attempt:0 gen:_generation then:^{
        VSPerform(top, @selector(pickNewContent), nil);
        [self mediaPickWatchdogGen:self->_generation];
    } fail:^{
        [self showSimpleAlert:@"Thông báo" message:@"Bộ chọn ảnh/video gốc của Video Star chưa sẵn sàng." index:VSFeatureMedia];
    }];
}

- (void)waitForEditorReady:(id)editor attempt:(NSUInteger)n gen:(NSInteger)gen then:(dispatch_block_t)ok fail:(dispatch_block_t)fail {
    if (gen != _generation) return;
    UIViewController *vc = editor;
    BOOL ready = vc.viewIfLoaded.window != nil && VSGet(vc, @selector(navigationController)) != nil;
    if (ready) { VSAfter(0.08, ^{ if (gen == self->_generation) ok(); }); return; }
    if (n > 60) { fail(); return; }
    VSAfter(0.1, ^{ [self waitForEditorReady:editor attempt:n + 1 gen:gen then:ok fail:fail]; });
}

- (void)mediaPickWatchdogGen:(NSInteger)gen {
    VSAfter(0.5, ^{
        if (gen != self->_generation || self->_activeFeature != VSFeatureMedia || self->_mediaPickerHandled) return;
        UIViewController *ed = self->_mediaEditor;
        if (ed.presentedViewController) self->_mediaSawPresented = YES;
        BOOL gone = self->_mediaSawPresented && !ed.presentedViewController;
        if ((gone && CACurrentMediaTime() - self->_mediaStart > 2.0) || CACurrentMediaTime() - self->_mediaStart > 180) {
            [self restoreAfterNativeUI];
            [self showSimpleAlert:@"Thông báo" message:@"Bạn chưa chọn ảnh/video nào." index:VSFeatureMedia];
            return;
        }
        [self mediaPickWatchdogGen:gen];
    });
}

- (void)handlePickedResponse:(id)resp editor:(id)editor {
    if (!resp || _replaying) return;
    if (_activeFeature == VSFeatureMedia && editor == _mediaEditor && !_mediaPickerHandled) {
        _mediaPickerHandled = YES;
        _pickedResponse = resp;
        id engine = VSGet(editor, @selector(getMultiLayerEngine)) ?: editor;
        id last = VSGet(engine, @selector(lastSelectedLayer));
        id ln = VSInvoke(last, @selector(layerNum), nil);
        _pickedLayerIndex = [ln isKindOfClass:[NSNumber class]] ? [ln integerValue] : -1;
        NSInteger gen = _generation;
        VSAfter(0.7, ^{
            if (gen != self->_generation) return;
            [self restoreAfterNativeUI];
            [self showFlowTitle:@"Đang xử lý" message:@"Đang thay nội dung cho các lớp media…" primary:@"Đang xử lý…" secondary:@"" full:NO];
            self->_flowPrimary.enabled = NO;
            [self applyResponse:resp toEditor:editor skipLayer:self->_pickedLayerIndex completion:^(NSUInteger done, NSUInteger total, NSString *err) {
                if (gen != self->_generation) return;
                if (err) { [self showSimpleAlert:@"Thông báo" message:err index:VSFeatureMedia]; return; }
                NSString *m = [NSString stringWithFormat:@"Đã thay nội dung cho %lu lớp media.", (unsigned long)(done + 1)];
                [self showCompletion:@"Thay thành công" message:m index:VSFeatureMedia];
            }];
        });
        return;
    }
    if (_activeFeature == VSFeatureMulti && _mergeAwaitingMediaPick && editor == _mediaEditor) {
        _mergeAwaitingMediaPick = NO;
        _pendingResponse = resp;
        VSLOG(@"merge: media response captured");
        VSAfter(0.6, ^{ [self restoreAfterNativeUI]; [self applyMergePresetsAndMedia]; });
    }
}

- (NSString *)kindOfResponse:(id)resp {
    id asset = VSKey(resp, @"asset");
    if ([asset isKindOfClass:[AVAsset class]]) {
        return [[(AVAsset *)asset tracksWithMediaType:AVMediaTypeVideo] count] ? @"video" : @"image";
    }
    id img = VSKey(resp, @"image") ?: VSKey(resp, @"uiImage");
    if (img) return @"image";
    id type = VSGet(resp, @selector(clipPickerResponseType)) ?: VSKey(resp, @"clipPickerResponseType");
    NSString *t = VSNorm([type description]);
    if ([t containsString:@"video"]) return @"video";
    if ([t containsString:@"image"] || [t containsString:@"photo"]) return @"image";
    return nil;
}

- (NSString *)kindOfLayer:(id)layer {
    if (!layer) return nil;
    id asset = VSGet(layer, @selector(asset));
    if ([asset isKindOfClass:[AVAsset class]] && [[(AVAsset *)asset tracksWithMediaType:AVMediaTypeVideo] count]) return @"video";
    if (VSGet(layer, @selector(layerImage)) || VSGet(layer, @selector(layerGIF))) return @"image";
    return nil;
}

- (NSUInteger)layerCountForEditor:(id)editor engine:(id)engine {
    NSUInteger n = VSUInt(engine, @selector(numActiveLayers), 0);
    if (!n) n = VSUInt(editor, @selector(numActiveLayers), 0);
    if (!n) {
        id arr = VSGet(engine ?: editor, @selector(layersWithContent)) ?: VSGet(engine ?: editor, @selector(multiLayerLayersWithContent));
        if ([arr isKindOfClass:[NSArray class]]) n = [(NSArray *)arr count];
    }
    return n ?: 10;
}

- (void)refreshEditor:(id)editor engine:(id)engine {
    NSArray *sels = @[@"reloadLayerEffects", @"handleImageGenUpdate", @"engineResync", @"refreshDisplay"];
    for (NSString *s in sels) {
        SEL sel = NSSelectorFromString(s);
        if (!VSPerform(editor, sel, nil)) VSPerform(engine, sel, nil);
    }
}

- (void)applyResponse:(id)resp toEditor:(id)editor skipLayer:(NSInteger)skip
           completion:(void (^)(NSUInteger done, NSUInteger total, NSString *err))completion {
    id engine = VSGet(editor, @selector(getMultiLayerEngine));
    id lay = engine ?: editor;
    NSString *kind = [self kindOfResponse:resp];
    NSUInteger count = [self layerCountForEditor:editor engine:engine];
    NSMutableArray<NSNumber *> *targets = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) {
        if ((NSInteger)i == skip) continue;
        id layer = VSInvoke(lay, @selector(layerAtLayerNum:), @[@(i)]);
        if (!layer) continue;
        if (VSBool(layer, @selector(isNullLayer), nil)) continue;
        if (VSBool(lay, @selector(drawingExistsOnLayerNum:), @[@(i)]) ||
            VSBool(lay, @selector(overlayObjectExistsOnLayerNum:), @[@(i)]) ||
            VSBool(lay, @selector(particlesExistOnLayerNum:), @[@(i)])) {
            VSLOG(@"skip excluded/non-media layer %lu", (unsigned long)i);
            continue;
        }
        NSString *lk = [self kindOfLayer:layer];
        if (!lk) continue;
        if (kind && ![kind isEqualToString:lk]) continue;
        [targets addObject:@(i)];
    }
    if (!targets.count) {
        if (completion) completion(0, 0, nil);
        return;
    }
    VSLOG(@"native layer replace: targets=%lu kind=%@", (unsigned long)targets.count, kind ?: @"?");
    NSInteger gen = _generation;
    __block NSUInteger okCount = 0;
    __block void (^step)(NSUInteger) = nil;
    __weak typeof(self) wself = self;
    void (^stepImpl)(NSUInteger) = ^(NSUInteger k) {
        __strong typeof(wself) s = wself;
        if (!s || gen != s->_generation) { step = nil; return; }
        if (k >= targets.count) {
            [s refreshEditor:editor engine:engine];
            void (^cb)(NSUInteger, NSUInteger, NSString *) = completion;
            step = nil;
            if (cb) cb(okCount, targets.count, nil);
            return;
        }
        NSUInteger idx = targets[k].unsignedIntegerValue;
        id layer = VSInvoke(lay, @selector(layerAtLayerNum:), @[@(idx)]);
        id beforeImg = VSGet(layer, @selector(layerImage));
        id beforeAsset = VSGet(layer, @selector(asset));
        if (!VSPerform(editor, @selector(selectLayer:bordered:), @[@(idx), @NO]))
            VSPerform(engine, @selector(selectLayer:bordered:), @[@(idx), @NO]);
        VSAfter(0.35, ^{
            if (gen != s->_generation) { step = nil; return; }
            s->_replaying = YES;
            VSPerform(editor, @selector(pickedWithClipPickerResponse:), @[resp]);
            __block NSUInteger tries = 0;
            __block void (^verify)(void) = nil;
            void (^verifyImpl)(void) = ^{
                if (gen != s->_generation) { verify = nil; step = nil; return; }
                id nl = VSInvoke(lay, @selector(layerAtLayerNum:), @[@(idx)]);
                BOOL changed = (VSGet(nl, @selector(layerImage)) != beforeImg) || (VSGet(nl, @selector(asset)) != beforeAsset);
                if (changed) { okCount++; }
                if (changed || ++tries > 15) {
                    if (!changed) VSLOG(@"native media state did not verify for layer %lu", (unsigned long)idx);
                    s->_replaying = NO;
                    verify = nil;
                    [s refreshEditor:editor engine:engine];
                    VSAfter(0.15, ^{ if (step) step(k + 1); });
                    return;
                }
                VSAfter(0.2, verify);
            };
            verify = verifyImpl;
            VSAfter(0.3, verify);
        });
    };
    step = stepImpl;
    step(0);
}

#pragma mark - Feature 1

- (void)startFeatureLastCode {
    NSData *cached = VSLastQRData();
    if (cached.length && [UIImage imageWithData:cached]) { [self presentLastCodeData:cached]; return; }
    [self showFlowTitle:@"Code gần nhất" message:@"Đang tìm ảnh code đã nhập gần nhất…" primary:@"Đang tìm…" secondary:@"" full:NO];
    _flowPrimary.enabled = NO;
    NSInteger gen = _generation;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *found = [self scanDiskForRecentQR];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gen != self->_generation) return;
            if (found.length) { VSCacheQR(found); [self presentLastCodeData:found]; }
            else [self showSimpleAlert:@"Thông báo" message:@"Không tìm thấy ảnh code đã nhập gần nhất." index:VSFeatureLastCode];
        });
    });
}

- (NSData *)scanDiskForRecentQR {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *home = NSHomeDirectory();
    NSArray *roots = @[[home stringByAppendingPathComponent:@"Library/Caches"],
                       [home stringByAppendingPathComponent:@"Library/Application Support"],
                       [home stringByAppendingPathComponent:@"Documents"]];
    NSSet *exts = [NSSet setWithArray:@[@"png", @"jpg", @"jpeg", @"heic", @"webp"]];
    NSMutableArray<NSDictionary *> *cands = [NSMutableArray array];
    for (NSString *root in roots) {
        NSDirectoryEnumerator *en = [fm enumeratorAtURL:[NSURL fileURLWithPath:root]
                             includingPropertiesForKeys:@[NSURLContentModificationDateKey, NSURLIsDirectoryKey]
                                                options:NSDirectoryEnumerationSkipsHiddenFiles
                                           errorHandler:nil];
        NSUInteger visited = 0;
        for (NSURL *u in en) {
            if (++visited > 6000) break;
            NSNumber *isDir = nil; [u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
            if (isDir.boolValue) continue;
            if (![exts containsObject:u.pathExtension.lowercaseString]) continue;
            if ([u.lastPathComponent isEqualToString:@"VideoStarTool_LastQR.png"]) continue;
            NSDate *d = nil; [u getResourceValue:&d forKey:NSURLContentModificationDateKey error:nil];
            [cands addObject:@{@"url": u, @"date": d ?: [NSDate distantPast]}];
        }
    }
    [cands sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"date"] compare:a[@"date"]]; }];
    if (cands.count > 300) [cands removeObjectsInRange:NSMakeRange(300, cands.count - 300)];
    CIDetector *det = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil options:@{CIDetectorAccuracy: CIDetectorAccuracyHigh}];
    for (NSDictionary *c in cands) {
        @autoreleasepool {
            NSData *data = [NSData dataWithContentsOfURL:c[@"url"] options:NSDataReadingMappedIfSafe error:nil];
            UIImage *img = data.length ? [UIImage imageWithData:data] : nil;
            if (!img) continue;
            CIImage *ci = img.CIImage ?: (img.CGImage ? [CIImage imageWithCGImage:img.CGImage] : nil);
            if (!ci) continue;
            if ([det featuresInImage:ci].count) {
                VSLOG(@"last QR found on disk: %@", [(NSURL *)c[@"url"] lastPathComponent]);
                return UIImagePNGRepresentation(img);
            }
        }
    }
    return nil;
}

- (void)presentLastCodeData:(NSData *)data {
    UIImage *img = [UIImage imageWithData:data];
    if (!img) { [self showSimpleAlert:@"Thông báo" message:@"Không tìm thấy ảnh code đã nhập gần nhất." index:VSFeatureLastCode]; return; }
    [self showFlowTitle:@"Code gần nhất" message:@"" primary:@"OK" secondary:@"" full:NO];
    _flowImage.image = img;
    _flowImage.hidden = NO;
    _flowScroll.hidden = YES;
    [self layoutFlow];
}

#pragma mark - Feature 2

- (void)startFeatureBeatSplit {
    UIViewController *top = VSTopVC();
    Class review = NSClassFromString(@"VideoReviewEditVC");
    Class split = NSClassFromString(@"MultiSplitView");
    if (!top || !review || !split || ![top isKindOfClass:review]) {
        [self showSimpleAlert:@"Thông báo" message:@"Bạn chưa trong phần chia phân cảnh." index:VSFeatureBeat]; return;
    }
    UIView *sv = VSFindSubview(top.view, split);
    if (!sv) { [self showSimpleAlert:@"Thông báo" message:@"Không tìm thấy chức năng chia beat gốc của Video Star." index:VSFeatureBeat]; return; }
    id project = VSGet(top, @selector(project));
    NSUInteger sceneIdx = VSUInt(top, @selector(sceneIndex), 0);
    BOOL hasToggle = [sv respondsToSelector:@selector(toggleBeatMode)] || [sv respondsToSelector:@selector(jumpToNextBeat)];
    if (!hasToggle) {
        [self showSimpleAlert:@"Thông báo" message:@"Không tìm thấy chức năng chia beat gốc của Video Star." index:VSFeatureBeat]; return;
    }

    NSString *err = nil;
    if ([sv respondsToSelector:@selector(isEnoughStorageAvailableForSplit)] && !VSBool(sv, @selector(isEnoughStorageAvailableForSplit), nil)) {
        err = @"Bộ nhớ trống không đủ để chia phân cảnh.";
    }
    if (!err && project && [project respondsToSelector:@selector(sceneHasAtLeastOneClipWithSceneIndex:)] &&
        !VSBool(project, @selector(sceneHasAtLeastOneClipWithSceneIndex:), @[@(sceneIdx)])) {
        err = @"Phân cảnh chưa có clip nào.";
    }
    if (!err) {
        id fm = VSGet(sv, @selector(fileManager)) ?: VSGet(project, @selector(fileManager));
        NSUInteger clips = 0;
        id c = VSInvoke(sv, @selector(clipCountForSceneIndex:), @[@(sceneIdx)]);
        if (![c isKindOfClass:[NSNumber class]]) c = VSInvoke(project, @selector(clipCountForSceneIndex:), @[@(sceneIdx)]);
        if ([c isKindOfClass:[NSNumber class]]) clips = [c unsignedIntegerValue];
        for (NSUInteger i = 0; i < clips && fm; i++) {
            id url = VSInvoke(fm, @selector(clipURLForSceneIndex:clipIndex:), @[@(sceneIdx), @(i)]);
            if ([url isKindOfClass:[NSString class]]) url = [NSURL fileURLWithPath:url];
            if (![url isKindOfClass:[NSURL class]]) { err = [NSString stringWithFormat:@"Không đọc được clip %lu của phân cảnh.", (unsigned long)(i + 1)]; break; }
            if ([(NSURL *)url isFileURL] && ![[NSFileManager defaultManager] fileExistsAtPath:[(NSURL *)url path]]) {
                err = [NSString stringWithFormat:@"Clip %lu không còn trên máy.", (unsigned long)(i + 1)]; break;
            }
            AVURLAsset *a = [AVURLAsset URLAssetWithURL:url options:nil];
            if (![a tracksWithMediaType:AVMediaTypeVideo].count || CMTimeGetSeconds(a.duration) <= 0) {
                err = [NSString stringWithFormat:@"Clip %lu không hợp lệ.", (unsigned long)(i + 1)]; break;
            }
        }
    }
    if (err) { [self showSimpleAlert:@"Thông báo" message:err ?: @"Tất cả clip trong phân cảnh phải hợp lệ trước khi chia." index:VSFeatureBeat]; return; }
    if (_beatRunning) return;

    _beatRunning = YES;
    _beatView = sv;
    _beatProject = project;
    _beatSceneBefore = VSUInt(project, @selector(sceneCount), 0);
    _beatQueued = 0; _beatGuard = 0; _beatNoAdvance = 0;
    _beatLastTime = kCMTimeInvalid;
    if ([sv respondsToSelector:@selector(beatModeOn)] && !VSBool(sv, @selector(beatModeOn), nil)) {
        VSPerform(sv, @selector(toggleBeatMode), nil);
    }
    [self showFlowTitle:@"Auto chia beat" message:@"Đang đặt điểm chia theo beat…" primary:@"Đang xử lý…" secondary:@"" full:NO];
    _flowPrimary.enabled = NO;
    NSInteger gen = _generation;
    VSAfter(0.18, ^{ if (gen == self->_generation) [self beatSplitAdvanceStepWithAttempt:0]; });
}

- (BOOL)beatHasNextFallback {
    CMTime cur = kCMTimeInvalid;
    if (!VSCurrentTime(_beatView, &cur)) return YES;
    id dur = VSInvoke(_beatView, @selector(duration), nil);
    if (![dur isKindOfClass:[NSValue class]] && ![dur isKindOfClass:[NSNumber class]]) {
        return (_beatGuard < 4000);
    }
    double d = 0;
    if ([dur isKindOfClass:[NSNumber class]]) d = [dur doubleValue];
    else {
        AVAsset *asset = (AVAsset *)dur;
        if ([asset isKindOfClass:[AVAsset class]]) d = CMTimeGetSeconds(asset.duration);
    }
    if (d <= 0) return YES;
    return CMTimeGetSeconds(cur) < d - 0.05;
}

- (void)beatSplitAdvanceStepWithAttempt:(NSUInteger)attempt {
    if (!_beatRunning || !_beatView) return;
    if (++_beatGuard >= 4096) { [self finishBeatSplitNativeWorkflow]; return; }
    CMTime before = kCMTimeInvalid;
    if (!VSCurrentTime(_beatView, &before)) before = kCMTimeInvalid;
    NSInteger gen = _generation;
    if (VSTrigger(_beatView, @"nextButton", @selector(jumpToNextBeat))) {
        [self waitForBeatAdvanceFromTime:before attempt:0 gen:gen];
        return;
    }
    if (attempt > 29) { [self finishBeatSplitNativeWorkflow]; return; }
    VSAfter(0.015, ^{ if (gen == self->_generation) [self beatSplitAdvanceStepWithAttempt:attempt + 1]; });
}

- (void)waitForBeatAdvanceFromTime:(CMTime)from attempt:(NSUInteger)attempt gen:(NSInteger)gen {
    if (!_beatRunning || !_beatView || gen != _generation) return;
    CMTime now = kCMTimeInvalid;
    BOOL valid = VSCurrentTime(_beatView, &now);
    BOOL advanced = valid && (CMTIME_IS_INVALID(from) || CMTimeCompare(now, from) > 0);
    if (advanced) {
        if (CMTIME_IS_VALID(_beatLastTime) && CMTimeCompare(now, _beatLastTime) <= 0) { [self finishBeatSplitNativeWorkflow]; return; }
        _beatLastTime = now;
        _beatNoAdvance = 0;
        if (VSTrigger(_beatView, @"setButton", @selector(setSplitPoint))) {
            _beatQueued++;
            VSAfter(0.015, ^{ if (gen == self->_generation) [self beatSplitAdvanceStepWithAttempt:0]; });
        } else { [self finishBeatSplitNativeWorkflow]; }
        return;
    }
    if (attempt <= 99) {
        VSAfter(0.012, ^{ [self waitForBeatAdvanceFromTime:from attempt:attempt + 1 gen:gen]; });
        return;
    }
    BOOL hasNext = [_beatView respondsToSelector:@selector(hasNextBeat)]
        ? VSBool(_beatView, @selector(hasNextBeat), nil)
        : [self beatHasNextFallback];
    if (hasNext && _beatNoAdvance <= 1) { _beatNoAdvance++; [self beatSplitAdvanceStepWithAttempt:0]; return; }
    [self finishBeatSplitNativeWorkflow];
}

- (void)finishBeatSplitNativeWorkflow {
    if (!_beatRunning) return;
    _beatRunning = NO;
    UIView *view = _beatView; id project = _beatProject;
    NSUInteger queued = _beatQueued, before = _beatSceneBefore;
    _beatView = nil; _beatProject = nil;
    if (!queued) {
        [self showSimpleAlert:@"Thông báo" message:@"Không còn beat nào để chia trong phân cảnh hiện tại." index:VSFeatureBeat]; return;
    }
    if (!VSTrigger(view, @"splitButton", @selector(doSplit))) {
        [self showSimpleAlert:@"Thông báo" message:@"Không tìm thấy nút Chia của Video Star." index:VSFeatureBeat]; return;
    }
    VSLOG(@"native manual beat workflow queued=%lu sceneCountBefore=%lu", (unsigned long)queued, (unsigned long)before);
    [self waitForBeatSplitCompletionOnProject:project before:before attempt:0 gen:_generation];
}

- (void)waitForBeatSplitCompletionOnProject:(id)project before:(NSUInteger)before attempt:(NSUInteger)n gen:(NSInteger)gen {
    if (gen != _generation || _activeFeature != VSFeatureBeat) return;
    NSUInteger now = VSUInt(project, @selector(sceneCount), 0);
    if (now > before) {
        NSString *m = [NSString stringWithFormat:@"Đã chia %lu phân cảnh từ các beat.", (unsigned long)(now - before)];
        [self showCompletion:@"Chia beat thành công" message:m index:VSFeatureBeat]; return;
    }
    if (n > 119) {
        [self showSimpleAlert:@"Thông báo" message:@"Video Star chưa hoàn tất thao tác chia beat. Vui lòng kiểm tra lại phân cảnh." index:VSFeatureBeat]; return;
    }
    VSAfter(0.1, ^{ [self waitForBeatSplitCompletionOnProject:project before:before attempt:n + 1 gen:gen]; });
}

#pragma mark - Feature 3

- (void)startFeatureMultiSceneApply {
    UIViewController *top = VSTopVC();
    Class review = NSClassFromString(@"VideoReviewEditVC");
    if (!top || !review || ![top isKindOfClass:review] || ![top respondsToSelector:@selector(showMergeScenes)]) {
        [self showSimpleAlert:@"Thông báo" message:@"Không tìm thấy giao diện nhiều lớp của Video Star. Hãy mở màn hình chia phân cảnh." index:VSFeatureMulti]; return;
    }
    _mergeReviewVC = top;
    _mergeOrigLastViewed = VSUInt(top, @selector(lastViewedSceneIndex), 0);
    _mergeRangeLocked = NO;
    _mergeProject = nil;
    [_mergePresets removeAllObjects]; [_mergeImages removeAllObjects];
    VSPerform(top, @selector(showMergeScenes), nil);
    [self showFlowTitle:@"Chọn phân cảnh"
                message:@"Chọn điểm bắt đầu và điểm cuối trong Hợp nhất phân cảnh, rồi bấm Bắt đầu."
                primary:@"Bắt đầu" secondary:@"Hủy" full:NO banner:YES];
}

- (id)keyOwnerForKey:(NSString *)key in:(id)vc {
    if (VSKey(vc, key)) return vc;
    UIView *v = ((UIViewController *)vc).viewIfLoaded;
    NSMutableArray *stack = v ? [NSMutableArray arrayWithObject:v] : [NSMutableArray array];
    NSUInteger guard = 0;
    while (stack.count && guard++ < 600) {
        UIView *c = stack.firstObject; [stack removeObjectAtIndex:0];
        if (VSKey(c, key)) return c;
        [stack addObjectsFromArray:c.subviews];
    }
    return nil;
}

- (void)beginMergeRangeFromNativePanel {
    UIViewController *vc = _mergeReviewVC ?: VSTopVC();
    id project = VSGet(vc, @selector(project));
    NSUInteger total = VSUInt(project, @selector(sceneCount), 0);
    id owner = [self keyOwnerForKey:@"startScene" in:vc] ?: vc;
    NSNumber *sNum = VSKey(owner, @"startScene"), *lNum = VSKey(owner, @"lastScene");
    NSUInteger s = [sNum respondsToSelector:@selector(unsignedIntegerValue)] ? sNum.unsignedIntegerValue : 0;
    NSUInteger l = [lNum respondsToSelector:@selector(unsignedIntegerValue)] ? lNum.unsignedIntegerValue : 0;
    if (!project || l < s || (total && l >= total)) {
        _flowMessage.text = @"Chưa chọn được phạm vi hợp lệ. Hãy chọn lại trong Hợp nhất phân cảnh.";
        [self layoutFlow];
        return;
    }
    _mergeProject = project; _mergeStart = s; _mergeEnd = l; _mergeRangeLocked = YES;
    [_mergePresets removeAllObjects]; [_mergeImages removeAllObjects];
    VSPerform(owner, @selector(closeMergePanel), nil);
    [self buildMergeCodePickerUI];
}

- (void)buildMergeCodePickerUI {
    NSUInteger count = _mergeEnd - _mergeStart + 1;
    for (NSUInteger i = 0; i < count; i++) { [_mergePresets addObject:[NSNull null]]; [_mergeImages addObject:[NSNull null]]; }
    NSString *msg = [NSString stringWithFormat:@"Có %lu phân cảnh. Nhập từng code một.", (unsigned long)count];
    [self showFlowTitle:@"Nhập code" message:msg primary:@"" secondary:@"Hủy" full:YES];
    _flowPrimary.hidden = YES;
    [self layoutFlow];
    for (UIView *s in [_flowScroll.subviews copy]) [s removeFromSuperview];
    _flowRowViews = [NSMutableArray array];
    [_flowRowThumbs removeAllObjects];
    CGFloat w = _flowScroll.bounds.size.width, rh = 62, gap = 8;
    for (NSUInteger i = 0; i < count; i++) {
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, i * (rh + gap), w, rh)];
        row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
        row.layer.cornerRadius = 16;
        UIImageView *thumb = [[UIImageView alloc] initWithFrame:CGRectMake(8, 8, 46, 46)];
        thumb.contentMode = UIViewContentModeScaleAspectFill;
        thumb.layer.cornerRadius = 8;
        thumb.clipsToBounds = YES;
        thumb.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        thumb.tag = 5002;
        thumb.hidden = YES;
        [row addSubview:thumb];
        [_flowRowThumbs addObject:thumb];
        UILabel *t = VSLabel([NSString stringWithFormat:@"Phân cảnh %lu", (unsigned long)(_mergeStart + i + 1)], 14.5, UIFontWeightSemibold, [UIColor whiteColor], NSTextAlignmentLeft);
        t.frame = CGRectMake(62, 10, w - 168, 22); t.numberOfLines = 1; [row addSubview:t];
        UILabel *st = VSLabel(@"Chưa có code", 12, UIFontWeightRegular, VS_TEXT3, NSTextAlignmentLeft);
        st.frame = CGRectMake(62, 33, w - 168, 18); st.numberOfLines = 1; st.tag = 5001; [row addSubview:st];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(w - 96, 15, 84, 32);
        b.tag = 6000 + i;
        b.layer.cornerRadius = 11; b.layer.borderWidth = 1; b.layer.borderColor = VS_CYAN.CGColor;
        b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [b setTitle:@"Nhập code" forState:UIControlStateNormal];
        [b setTitleColor:VS_CYAN forState:UIControlStateNormal];
        [b addTarget:self action:@selector(mergeCodeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:b];
        row.tag = 7000 + i;
        [_flowScroll addSubview:row];
        [_flowRowViews addObject:row];
    }
    _flowScroll.contentSize = CGSizeMake(w, count * (rh + gap));
}

- (void)mergeCodeButtonTapped:(UIButton *)b {
    VSHaptic(UIImpactFeedbackStyleLight);
    NSInteger idx = b.tag - 6000;
    if (idx < 0 || _activeFeature != VSFeatureMulti || idx >= (NSInteger)(_mergeEnd - _mergeStart + 1)) return;
    [self startNativeQRImportForIndex:idx];
}

- (void)startNativeQRImportForIndex:(NSUInteger)idx {
    Class qc = NSClassFromString(@"QRCodeManager");
    id mgr = VSInvoke(qc, @selector(sharedInstance), nil);
    if (!mgr || ![mgr respondsToSelector:@selector(startQRImport)]) {
        [self showSimpleAlert:@"Thông báo" message:@"Không tìm thấy chức năng nhập QR gốc của Video Star." index:VSFeatureMulti]; return;
    }
    id prev = VSKey(mgr, @"delegate");
    VSQRCaptureProxy *proxy = [VSQRCaptureProxy new];
    proxy.target = prev;
    NSInteger gen = _generation;
    __weak typeof(self) wself = self;
    proxy.captured = ^(id data, id code) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) s = wself;
            if (!s || gen != s->_generation) return;
            [s restoreQRDelegate];
            [s restoreAfterNativeUI];
            if (!data && !code) {
                [s showSimpleAlert:@"Thông báo" message:@"Ảnh đã chọn không chứa code Video Star hợp lệ." index:VSFeatureMulti]; return;
            }
            [s acceptMergePreset:@[data ?: [NSNull null], code ?: [NSNull null]] imageData:VSLastQRData() index:idx];
        });
    };
    _qrPrevDelegate = prev;
    _qrProxy = proxy;
    VSSetKey(mgr, @"delegate", proxy);
    [self hideToolOverlayForNativeUI];
    _mergeQRStart = CACurrentMediaTime();
    @try { VSPerform(mgr, @selector(startQRImport), nil); }
    @catch (NSException *e) {
        [self restoreQRDelegate]; [self restoreAfterNativeUI];
        [self showSimpleAlert:@"Thông báo" message:[NSString stringWithFormat:@"Video Star gặp lỗi khi mở nhập QR: %@", e.reason ?: e.name] index:VSFeatureMulti];
        return;
    }
    [self qrWatchdogGen:gen idx:idx];
}

- (void)qrWatchdogGen:(NSInteger)gen idx:(NSUInteger)idx {
    VSAfter(1.0, ^{
        if (gen != self->_generation || self->_activeFeature != VSFeatureMulti) return;
        if (!self->_qrProxy) return;
        NSTimeInterval elapsed = CACurrentMediaTime() - self->_mergeQRStart;
        if (elapsed > 120) {
            VSLOG(@"QR import watchdog timeout after %.0fs (scene idx=%lu)", elapsed, (unsigned long)idx);
            [self restoreQRDelegate];
            [self restoreAfterNativeUI];
            [self showSimpleAlert:@"Hết thời gian" message:@"Không nhận được code từ giao diện nhập QR gốc. Vui lòng thử lại." index:VSFeatureMulti];
            return;
        }
        [self qrWatchdogGen:gen idx:idx];
    });
}

- (void)acceptMergePreset:(NSArray *)preset imageData:(NSData *)img index:(NSUInteger)idx {
    if (_activeFeature != VSFeatureMulti || idx >= _mergePresets.count) return;
    _mergePresets[idx] = preset;
    _mergeImages[idx] = img ? [img copy] : (id)[NSNull null];
    UIView *row = idx < _flowRowViews.count ? _flowRowViews[idx] : nil;
    UILabel *st = (UILabel *)[row viewWithTag:5001];
    st.text = @"Đã nhận code"; st.textColor = VS_CYAN;
    UIImageView *thumb = idx < _flowRowThumbs.count ? _flowRowThumbs[idx] : nil;
    if (thumb && img) {
        thumb.image = [UIImage imageWithData:img];
        thumb.hidden = NO;
    }
    [(UIButton *)[row viewWithTag:6000 + idx] setTitle:@"Đổi code" forState:UIControlStateNormal];
    NSUInteger got = 0;
    for (id p in _mergePresets) if (p != [NSNull null]) got++;
    NSUInteger total = _mergePresets.count;
    _flowMessage.text = [NSString stringWithFormat:@"Đã nhận %lu/%lu code.", (unsigned long)got, (unsigned long)total];
    if (got == total) {
        _flowPrimary.hidden = NO;
        [_flowPrimary setTitle:@"Chọn ảnh/video" forState:UIControlStateNormal];
        _flowPrimary.enabled = YES;
    }
    [self layoutFlow];
}

- (void)beginNativeMediaChoiceForMergeProject {
    if (!_mergeReviewVC) return;
    id vc = _mergeReviewVC;
    if (![vc respondsToSelector:@selector(showMultiLayer)]) {
        [self showSimpleAlert:@"Thông báo" message:@"Không tìm thấy giao diện nhiều lớp của Video Star." index:VSFeatureMulti]; return;
    }
    [self hideToolOverlayForNativeUI];
    [self openMergeSceneEditorAtOffset:0 attempt:0 gen:_generation then:^(id editor) {
        if (![editor respondsToSelector:@selector(pickNewContent)]) {
            [self restoreAfterNativeUI];
            [self showSimpleAlert:@"Thông báo" message:@"Không tìm thấy bộ chọn nội dung gốc của Video Star." index:VSFeatureMulti]; return;
        }
        self->_mediaEditor = editor;
        self->_mergeAwaitingMediaPick = YES;
        self->_pendingResponse = nil;
        VSPerform(editor, @selector(pickNewContent), nil);
    }];
}

- (void)openMergeSceneEditorAtOffset:(NSUInteger)offset attempt:(NSUInteger)n gen:(NSInteger)gen then:(void (^)(id editor))ok {
    if (_activeFeature != VSFeatureMulti || gen != _generation) return;
    NSUInteger sceneIdx = _mergeStart + offset;
    UIViewController *top = VSTopVC();
    Class wiz = NSClassFromString(@"MultiLayerWizEffectVC");
    if (top && wiz && [top isKindOfClass:wiz]) {
        id nav = VSGet(top, @selector(navigationController));
        id nsi = VSInvoke(nav, @selector(navSceneIndex), nil);
        id np = VSInvoke(nav, @selector(navProject), nil);
        BOOL sceneOK = ![nsi isKindOfClass:[NSNumber class]] || [nsi unsignedIntegerValue] == sceneIdx;
        BOOL projOK = !np || np == _mergeProject;
        if (top.viewIfLoaded.window && sceneOK && projOK) { ok(top); return; }
    }
    if (n > 100) {
        [self restoreAfterNativeUI];
        [self showSimpleAlert:@"Thông báo" message:[NSString stringWithFormat:@"Không mở được phần nhiều lớp ở phân cảnh %lu.", (unsigned long)(sceneIdx + 1)] index:VSFeatureMulti];
        return;
    }
    if (n == 0 || (n % 25 == 0)) {
        id vc = _mergeReviewVC;
        if (top && vc && top == vc) {
            VSPerform(vc, @selector(setLastViewedSceneIndex:), @[@(sceneIdx)]);
            VSPerform(vc, @selector(showMultiLayer), nil);
        } else if (!vc) {
            [self restoreAfterNativeUI];
            [self showSimpleAlert:@"Thông báo" message:@"Không tìm thấy giao diện nhiều lớp của Video Star." index:VSFeatureMulti]; return;
        }
    }
    VSAfter(0.08, ^{ [self openMergeSceneEditorAtOffset:offset attempt:n + 1 gen:gen then:ok]; });
}

- (void)applyMergePresetsAndMedia {
    if (_activeFeature != VSFeatureMulti) return;
    NSUInteger count = _mergeEnd - _mergeStart + 1;
    if (_mergePresets.count != count || !_pendingResponse) return;
    [self showFlowTitle:@"Đang áp dụng" message:@"Đang mở từng phân cảnh, nhập code và thay media…" primary:@"Đang xử lý…" secondary:@"" full:NO];
    _flowPrimary.enabled = NO;
    _mergeWaitingImport = NO;
    _mergeImportEditor = nil;
    [self applyMergeSceneOffset:0];
}

- (void)applyMergeSceneOffset:(NSUInteger)offset {
    if (_activeFeature != VSFeatureMulti) return;
    NSUInteger count = _mergeEnd - _mergeStart + 1;
    NSInteger gen = _generation;
    if (offset >= count) {
        _mergeWaitingImport = NO; _mergeImportEditor = nil;
        [self restoreQRDelegate];
        if (_mergeReviewVC) VSPerform(_mergeReviewVC, @selector(setLastViewedSceneIndex:), @[@(_mergeOrigLastViewed)]);
        NSString *m = [NSString stringWithFormat:@"Đã áp dụng %lu code cho %lu phân cảnh.", (unsigned long)count, (unsigned long)count];
        _mediaEditor = nil;
        [self showCompletion:@"Thành công" message:m index:VSFeatureMulti];
        return;
    }
    _flowMessage.text = [NSString stringWithFormat:@"Phân cảnh %lu/%lu…", (unsigned long)(offset + 1), (unsigned long)count];
    [self layoutFlow];
    [self openMergeSceneEditorAtOffset:offset attempt:0 gen:gen then:^(id editor) {
        [self beginNativeMergeCodeImportForEditor:editor offset:offset];
    }];
}

- (void)beginNativeMergeCodeImportForEditor:(id)editor offset:(NSUInteger)offset {
    if (_activeFeature != VSFeatureMulti || offset >= _mergePresets.count) return;
    NSArray *pair = _mergePresets[offset];
    if (![pair isKindOfClass:[NSArray class]]) {
        [self showSimpleAlert:@"Thông báo" message:[NSString stringWithFormat:@"Thiếu code cho phân cảnh %lu.", (unsigned long)(_mergeStart + offset + 1)] index:VSFeatureMulti]; return;
    }
    id a1 = pair[0] == [NSNull null] ? nil : pair[0];
    id a2 = pair.count > 1 && pair[1] != [NSNull null] ? pair[1] : nil;
    _mergeWaitingImport = YES;
    _mergeImportEditor = editor;
    _mergeImportOffset = offset;
    VSLOG(@"native QR import requested for scene %lu", (unsigned long)(_mergeStart + offset + 1));
    @try {
        if (!VSPerform(editor, @selector(importedData:code:), @[a1 ?: [NSNull null], a2 ?: [NSNull null]])) {
            [self showSimpleAlert:@"Thông báo" message:@"Không tìm thấy chức năng nhập QR gốc của Video Star." index:VSFeatureMulti];
        }
    } @catch (NSException *e) {
        [self showSimpleAlert:@"Thông báo" message:[NSString stringWithFormat:@"Video Star gặp lỗi khi mở nhập QR: %@", e.reason ?: e.name] index:VSFeatureMulti];
    }
}

- (void)handleNativeMergeImportedData:(id)data editor:(id)editor code:(id)code {
    if (_activeFeature != VSFeatureMulti || !_mergeWaitingImport || editor != _mergeImportEditor) return;
    _mergeWaitingImport = NO;
    [self waitForMergeImportMatch:editor offset:_mergeImportOffset attempt:0 gen:_generation];
}

static NSString *VSPopupText(id popup) {
    if (!popup) return @"";
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *k in @[@"_title", @"_message", @"_messageLabel", @"text"]) {
        id v = VSKey(popup, k);
        if ([v isKindOfClass:[NSString class]]) [parts addObject:v];
        else if ([v isKindOfClass:[UILabel class]] && [(UILabel *)v text]) [parts addObject:[(UILabel *)v text]];
    }
    id bs = VSKey(popup, @"_buttonStrings");
    if ([bs isKindOfClass:[NSArray class]]) for (id s in bs) if ([s isKindOfClass:[NSString class]]) [parts addObject:s];
    if ([popup isKindOfClass:[UIView class]]) VSCollectTexts(popup, parts);
    return VSNorm([parts componentsJoinedByString:@" "]);
}

static BOOL VSPressPopupButton(id popup, NSArray<NSString *> *wantedNorm) {
    id btns = VSKey(popup, @"_buttons");
    NSMutableArray *buttons = [NSMutableArray array];
    if ([btns isKindOfClass:[NSArray class]]) for (id b in btns) if ([b isKindOfClass:[UIButton class]]) [buttons addObject:b];
    if (!buttons.count && [popup isKindOfClass:[UIView class]]) {
        NSMutableArray *stack = [NSMutableArray arrayWithObject:popup];
        NSUInteger guard = 0;
        while (stack.count && guard++ < 400) {
            UIView *v = stack.firstObject; [stack removeObjectAtIndex:0];
            if ([v isKindOfClass:[UIButton class]]) [buttons addObject:v];
            [stack addObjectsFromArray:v.subviews];
        }
    }
    for (UIButton *b in buttons) {
        NSString *t = VSNorm(b.currentTitle ?: b.titleLabel.text);
        for (NSString *w in wantedNorm) {
            if ([t isEqualToString:w] || [t containsString:w]) {
                if (VSPressButton(b)) return YES;
                if (VSPerform(popup, @selector(buttonPressed:), @[b])) return YES;
            }
        }
    }
    if ([popup respondsToSelector:@selector(buttonWithTitle:)]) {
        for (NSString *title in @[@"Trùng khớp", @"Match", @"Khớp", @"OK", @"Ok", @"Đồng ý", @"Tiếp tục", @"Continue"]) {
            NSString *n = VSNorm(title);
            BOOL wanted = NO; for (NSString *w in wantedNorm) if ([n containsString:w] || [w containsString:n]) wanted = YES;
            if (!wanted) continue;
            id b = VSInvoke(popup, @selector(buttonWithTitle:), @[title]);
            if (VSPressButton(b)) return YES;
        }
    }
    return NO;
}

- (void)waitForMergeImportMatch:(id)editor offset:(NSUInteger)offset attempt:(NSUInteger)n gen:(NSInteger)gen {
    if (_activeFeature != VSFeatureMulti || gen != _generation) return;
    if (n > 120) {
        [self showSimpleAlert:@"Thông báo" message:[NSString stringWithFormat:@"Code ở phân cảnh %lu chưa hoàn tất xử lý native.", (unsigned long)(_mergeStart + offset + 1)] index:VSFeatureMulti]; return;
    }
    id our = VSKey(editor, @"ourPopup");
    id warn = VSKey(editor, @"warningPopup");
    Class cp = NSClassFromString(@"CustomPopup");
    for (id popup in @[our ?: [NSNull null], warn ?: [NSNull null]]) {
        if (popup == [NSNull null] || !popup) continue;
        if (cp && ![popup isKindOfClass:cp]) continue;
        UIView *pv = [popup isKindOfClass:[UIView class]] ? popup : nil;
        if (pv && !pv.window) continue;
        NSString *txt = VSPopupText(popup);
        if (!txt.length) continue;
        BOOL mismatch = ([txt containsString:@"multi-layer qr"] && [txt containsString:@"than the scene"]);
        BOOL original = [txt containsString:@"original preset layers"] || [txt containsString:@"cai dat san"] || [txt containsString:@"original layers"];
        NSArray *want = (mismatch || original) ? @[@"trung khop", @"khop", @"match"] : @[@"dong y", @"tiep tuc", @"ok", @"continue"];
        BOOL pressed = VSPressPopupButton(popup, want);
        VSLOG(@"merge native popup press scene=%lu pressed=%d mismatch=%d", (unsigned long)(_mergeStart + offset + 1), pressed, mismatch);
        if (pressed) { VSAfter(0.4, ^{ [self waitForMergeImportMatch:editor offset:offset attempt:n + 1 gen:gen]; }); return; }
    }
    id engine = VSGet(editor, @selector(getMultiLayerEngine));
    NSUInteger layers = VSUInt(engine, @selector(numActiveLayers), VSUInt(editor, @selector(numActiveLayers), 0));
    if (layers > 0 && n >= 4) {
        VSAfter(0.5, ^{ [self waitForMergePresetReadyAndApplyMedia:editor offset:offset gen:gen]; });
        return;
    }
    VSAfter(0.25, ^{ [self waitForMergeImportMatch:editor offset:offset attempt:n + 1 gen:gen]; });
}

- (void)waitForMergePresetReadyAndApplyMedia:(id)editor offset:(NSUInteger)offset gen:(NSInteger)gen {
    if (_activeFeature != VSFeatureMulti || gen != _generation) return;
    [self applyResponse:_pendingResponse toEditor:editor skipLayer:-1 completion:^(NSUInteger done, NSUInteger total, NSString *err) {
        if (gen != self->_generation) return;
        if (!total) VSLOG(@"scene %lu has no eligible image/video layer; continue to native Create", (unsigned long)(self->_mergeStart + offset + 1));
        VSAfter(0.4, ^{ [self pressCreateOnEditor:editor offset:offset gen:gen]; });
    }];
}

- (void)pressCreateOnEditor:(id)editor offset:(NSUInteger)offset gen:(NSInteger)gen {
    if (_activeFeature != VSFeatureMulti || gen != _generation) return;
    BOOL ok = VSPerform(editor, @selector(create), nil);
    if (!ok) ok = VSPressButton(VSKey(editor, @"createButton"));
    if (!ok) {
        [self showSimpleAlert:@"Thông báo" message:@"Không tìm thấy nút tạo của phần nhiều lớp h/ả." index:VSFeatureMulti]; return;
    }
    [self waitForMergeCreateCompletionAtOffset:offset editor:editor attempt:0 gen:gen];
}

- (void)waitForMergeCreateCompletionAtOffset:(NSUInteger)offset editor:(id)editor attempt:(NSUInteger)n gen:(NSInteger)gen {
    if (_activeFeature != VSFeatureMulti || gen != _generation) return;
    UIViewController *e = editor;
    BOOL gone = !e.viewIfLoaded.window;
    if (gone || n > 120) {
        if (!gone) VSLOG(@"create wait timed out at scene %lu", (unsigned long)(_mergeStart + offset + 1));
        VSAfter(0.5, ^{ [self applyMergeSceneOffset:offset + 1]; });
        return;
    }
    VSAfter(0.1, ^{ [self waitForMergeCreateCompletionAtOffset:offset editor:editor attempt:n + 1 gen:gen]; });
}

@end

#pragma mark - Window / ViewController

@interface VSPassthroughWindow : UIWindow
@end
@implementation VSPassthroughWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

@interface VSOverlayViewController : UIViewController
@end
@implementation VSOverlayViewController
- (void)loadView { self.view = [[VSToolOverlay alloc] initWithFrame:[UIScreen mainScreen].bounds]; }
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end

#pragma mark - Hooks

static BOOL sHookRead = NO, sHookSelected = NO, sHookImported = NO, sHookPicked = NO;
static NSUInteger sHookAttempts = 0;
static NSUInteger sHookLastSuccess = 0;

static BOOL VSInstallHookForMethod(Class cls, SEL sel, BOOL *flag, IMP (^makeBlock)(IMP orig)) {
    if (!cls || *flag) return *flag;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    IMP orig = method_getImplementation(m);
    method_setImplementation(m, makeBlock(orig));
    *flag = YES;
    return YES;
}

static void VSInstallHooksOnce(void) {
    sHookAttempts++;
    BOOL installed = NO;

    Class qr = NSClassFromString(@"QRCodeManager");
    if (qr) {
        if (VSInstallHookForMethod(qr, @selector(readQRCode:), &sHookRead, ^IMP(IMP orig) {
            return imp_implementationWithBlock(^id(id self_, id arg) {
                VSCacheQR(arg);
                return ((id (*)(id, SEL, id))orig)(self_, @selector(readQRCode:), arg);
            });
        })) { installed = YES; VSLOG(@"hook QRCodeManager.readQRCode"); }

        if (VSInstallHookForMethod(qr, @selector(selectedCode:withImageData:), &sHookSelected, ^IMP(IMP orig) {
            return imp_implementationWithBlock(^(id self_, id code, id imgData) {
                VSCacheQR(imgData);
                ((void (*)(id, SEL, id, id))orig)(self_, @selector(selectedCode:withImageData:), code, imgData);
            });
        })) { installed = YES; VSLOG(@"hook QRCodeManager.selectedCode"); }
    }

    Class wiz = NSClassFromString(@"MultiLayerWizEffectVC");
    if (wiz) {
        if (VSInstallHookForMethod(wiz, @selector(importedData:code:), &sHookImported, ^IMP(IMP orig) {
            return imp_implementationWithBlock(^(id self_, id data, id code) {
                ((void (*)(id, SEL, id, id))orig)(self_, @selector(importedData:code:), data, code);
                __weak id weakSelf = self_;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [sOverlay handleNativeMergeImportedData:data editor:weakSelf code:code];
                });
            });
        })) { installed = YES; VSLOG(@"hook MultiLayerWizEffectVC.importedData:code:"); }

        if (VSInstallHookForMethod(wiz, @selector(pickedWithClipPickerResponse:), &sHookPicked, ^IMP(IMP orig) {
            return imp_implementationWithBlock(^(id self_, id resp) {
                ((void (*)(id, SEL, id))orig)(self_, @selector(pickedWithClipPickerResponse:), resp);
                __weak id weakSelf = self_;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [sOverlay handlePickedResponse:resp editor:weakSelf];
                });
            });
        })) { installed = YES; VSLOG(@"hook MultiLayerWizEffectVC.pickedWithClipPickerResponse:"); }
    }

    if (installed) sHookLastSuccess = sHookAttempts;
}

void VSInstallHooksForce(void) {
    sHookRead = sHookSelected = sHookImported = sHookPicked = NO;
    VSInstallHooksOnce();
    VSLOG(@"force reload hooks (attempt=%lu)", (unsigned long)sHookAttempts);
}

static void VSInstallHooks(void) {
    if (sHookRead && sHookSelected && sHookImported && sHookPicked) return;
    if (sHookAttempts > 200 && sHookAttempts - sHookLastSuccess > 60) {
        static BOOL warned = NO;
        if (!warned) { warned = YES; VSLOG(@"hook retry limit reached, some classes unavailable"); }
        return;
    }
    static NSUInteger tick = 0;
    if ((tick++ % 5) != 0) return;
    VSInstallHooksOnce();
}

#pragma mark - Overlay bootstrap

static VSPassthroughWindow *sWindow = nil;

static void VSEnsureOverlayWindow(void) {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ VSEnsureOverlayWindow(); }); return; }
    @try {
        UIApplication *app = [UIApplication sharedApplication];
        if (!app) return;
        UIWindowScene *scene = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *sc in app.connectedScenes) {
                if (![sc isKindOfClass:[UIWindowScene class]]) continue;
                if (sc.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)sc; break; }
                if (!scene && sc.activationState == UISceneActivationStateForegroundInactive) scene = (UIWindowScene *)sc;
            }
        }
        if (sWindow) {
            if (@available(iOS 13.0, *)) {
                if (scene && sWindow.windowScene != scene) sWindow.windowScene = scene;
            }
            sWindow.hidden = NO;
            sWindow.windowLevel = UIWindowLevelAlert + 100;
            return;
        }
        VSPassthroughWindow *w = nil;
        if (@available(iOS 13.0, *)) {
            if (scene) w = [[VSPassthroughWindow alloc] initWithWindowScene:scene];
        }
        if (!w && app.applicationState == UIApplicationStateActive) {
            w = [[VSPassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        if (!w) return;
        w.windowLevel = UIWindowLevelAlert + 100;
        w.backgroundColor = [UIColor clearColor];
        w.rootViewController = [VSOverlayViewController new];
        w.hidden = NO;
        sWindow = w;
        VSLOG(@"overlay window created (scene=%@)", scene);
    } @catch (NSException *e) {
        VSLOG(@"overlay error: %@ - %@", e.name, e.reason);
    }
}

static void VSTick(void) {
    VSEnsureOverlayWindow();
    VSInstallHooks();
    [sOverlay ensureOnTop];
}

#pragma mark - Init guard

static BOOL VSIsVideoStarApp(void) {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier.lowercaseString;
    if (!bid.length) return NO;
    NSArray *accept = @[@"videostar", @"video.star", @"com.videostar", @"com.video.star", @"com.djw."];
    for (NSString *needle in accept) {
        if ([bid containsString:needle]) return YES;
    }
    NSString *bundleName = [NSBundle mainBundle].infoDictionary[@"CFBundleName"] ?: @"";
    if ([VSNorm(bundleName) containsString:@"videostar"] || [VSNorm(bundleName) containsString:@"video star"]) return YES;
    if (NSClassFromString(@"QRCodeManager")) return YES;
    return NO;
}

__attribute__((constructor))
static void VSToolInit(void) {
    @autoreleasepool {
        NSString *bp = [NSBundle mainBundle].bundlePath;
        VSLOG(@"dylib ctor: bundle=%@ id=%@ path=%@", [NSBundle mainBundle].infoDictionary[@"CFBundleName"],
              [NSBundle mainBundle].bundleIdentifier, bp);
        if (![bp.pathExtension isEqualToString:@"app"]) {
            VSLOG(@"skip: not .app"); return;
        }
        if (!VSIsVideoStarApp()) {
            VSLOG(@"skip: bundleIdentifier không khớp Video Star");
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
            NSOperationQueue *mq = [NSOperationQueue mainQueue];
            [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:mq usingBlock:^(NSNotification *n) { VSTick(); }];
            if (@available(iOS 13.0, *)) {
                [nc addObserverForName:UISceneDidActivateNotification object:nil queue:mq usingBlock:^(NSNotification *n) { VSTick(); }];
            }
            [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { VSTick(); }];
            VSTick();
        });
    }
}
