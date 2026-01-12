#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <CoreGraphics/CoreGraphics.h> // 显式引入 CoreGraphics
#import <objc/runtime.h>

// 全局状态控制
static BOOL gIsCopyEnabled = NO; 
static __weak WKWebView *gCurrentWebView = nil; 
static UIButton *gFloatingButton = nil; 

@implementation WKWebView (ForceSwitch)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[ForceSwitch] 插件已加载 - 修复版");

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appDidFinishLaunching:)
                                                     name:UIApplicationDidFinishLaunchingNotification
                                                   object:nil];

        [self swizzleSelector:@selector(initWithFrame:configuration:) with:@selector(fs_initWithFrame:configuration:)];
        [self swizzleSelector:@selector(initWithCoder:) with:@selector(fs_initWithCoder:)];
    });
}

// --- 辅助方法：获取当前活跃的 Window (兼容 iOS 13+) ---
+ (UIWindow *)getCurrentWindow {
    UIWindow *foundWindow = nil;
    // 尝试适配 Scene (iOS 13+)
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in scene.windows) {
                    if (window.isKeyWindow) {
                        foundWindow = window;
                        break;
                    }
                }
            }
            if (foundWindow) break;
        }
    }
    // 降级方案：如果没找到，或者 iOS 版本低，遍历所有 windows
    if (!foundWindow) {
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) {
                foundWindow = window;
                break;
            }
        }
    }
    return foundWindow;
}

// --- 悬浮窗 UI 逻辑 ---

+ (void)appDidFinishLaunching:(NSNotification *)note {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self createFloatingButton];
    });
}

+ (void)createFloatingButton {
    UIWindow *window = [self getCurrentWindow];
    if (!window) return;

    gFloatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
    gFloatingButton.frame = CGRectMake(window.bounds.size.width - 80, 200, 60, 60);
    gFloatingButton.layer.cornerRadius = 30;
    gFloatingButton.layer.masksToBounds = YES;
    gFloatingButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.8]; 
    [gFloatingButton setTitle:@"关" forState:UIControlStateNormal];
    [gFloatingButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    gFloatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    
    [gFloatingButton addTarget:self action:@selector(toggleCopyState) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [gFloatingButton addGestureRecognizer:pan];

    [window addSubview:gFloatingButton];
    [window bringSubviewToFront:gFloatingButton];
}

+ (void)toggleCopyState {
    gIsCopyEnabled = !gIsCopyEnabled;
    
    if (gIsCopyEnabled) {
        [gFloatingButton setTitle:@"开" forState:UIControlStateNormal];
        gFloatingButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:0.8]; 
        
        if (gCurrentWebView) {
            [gCurrentWebView injectForceCopyScript];
            [self showToast:@"Neko:复制功能已开启"];
        }
    } else {
        [gFloatingButton setTitle:@"关" forState:UIControlStateNormal];
        gFloatingButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.8]; 
        
        if (gCurrentWebView) {
            [gCurrentWebView reload];
            [self showToast:@"Neko:复制功能已关闭"];
        }
    }
}

+ (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view;
    if (!view.superview) return;
    
    CGPoint translation = [pan translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:view.superview]; // 这里需要 CoreGraphics
}

+ (void)showToast:(NSString *)msg {
    UIWindow *window = [self getCurrentWindow];
    if (!window) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    // 尝试用 rootViewController 弹出，如果没有，就找最顶层的 presentedViewController
    UIViewController *topController = window.rootViewController;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    
    if (topController) {
        [topController presentViewController:alert animated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }
}

// --- 核心注入逻辑 ---

- (void)injectForceCopyScript {
    if (!gIsCopyEnabled) return;
    
    NSLog(@"[ForceSwitch] 正在注入...");

    NSString *jsSource = 
    @"var css = 'html, body, * { -webkit-user-select: text !important; user-select: text !important; -webkit-touch-callout: default !important; }';"
    @"var style = document.createElement('style');"
    @"style.innerHTML = css;"
    @"document.head.appendChild(style);"
    @"setInterval(function() {"
    @"  if(document.documentElement) document.documentElement.style.webkitUserSelect = 'text';"
    @"  if(document.body) document.body.style.webkitUserSelect = 'text';"
    @"}, 500);";

    [self evaluateJavaScript:jsSource completionHandler:nil];
}

// --- Swizzling ---

+ (void)swizzleSelector:(SEL)orig with:(SEL)swiz {
    Class cls = [self class];
    Method mOrig = class_getInstanceMethod(cls, orig);
    Method mSwiz = class_getInstanceMethod(cls, swiz);
    if (class_addMethod(cls, orig, method_getImplementation(mSwiz), method_getTypeEncoding(mSwiz))) {
        class_replaceMethod(cls, swiz, method_getImplementation(mOrig), method_getTypeEncoding(mOrig));
    } else {
        method_exchangeImplementations(mOrig, mSwiz);
    }
}

- (instancetype)fs_initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    WKWebView *webView = [self fs_initWithFrame:frame configuration:configuration];
    gCurrentWebView = webView; 
    return webView;
}

- (instancetype)fs_initWithCoder:(NSCoder *)coder {
    WKWebView *webView = [self fs_initWithCoder:coder];
    gCurrentWebView = webView; 
    return webView;
}

@end
