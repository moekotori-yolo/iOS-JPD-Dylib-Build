#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

// 全局状态控制
static BOOL gIsCopyEnabled = NO; // 默认关闭，确保能过校验
static __weak WKWebView *gCurrentWebView = nil; // 弱引用当前活跃的 WebView
static UIButton *gFloatingButton = nil; // 悬浮按钮

@implementation WKWebView (ForceSwitch)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[ForceSwitch] 插件已加载 - 悬浮窗版");

        // 1. 监听 App 启动完成，创建悬浮窗
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appDidFinishLaunching:)
                                                     name:UIApplicationDidFinishLaunchingNotification
                                                   object:nil];

        // 2. Hook 初始化方法以捕获 WebView 实例
        [self swizzleSelector:@selector(initWithFrame:configuration:) with:@selector(fs_initWithFrame:configuration:)];
        [self swizzleSelector:@selector(initWithCoder:) with:@selector(fs_initWithCoder:)];
    });
}

// --- 悬浮窗 UI 逻辑 ---

+ (void)appDidFinishLaunching:(NSNotification *)note {
    // 延迟一点点，确保 Window 已经创建
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self createFloatingButton];
    });
}

+ (void)createFloatingButton {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;

    // 创建按钮 (60x60)
    gFloatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
    gFloatingButton.frame = CGRectMake(keyWindow.bounds.size.width - 80, 200, 60, 60);
    gFloatingButton.layer.cornerRadius = 30;
    gFloatingButton.layer.masksToBounds = YES;
    gFloatingButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.8]; // 默认红色 (关闭状态)
    [gFloatingButton setTitle:@"关" forState:UIControlStateNormal];
    [gFloatingButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    gFloatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    
    // 添加点击事件
    [gFloatingButton addTarget:self action:@selector(toggleCopyState) forControlEvents:UIControlEventTouchUpInside];

    // 添加拖拽手势
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [gFloatingButton addGestureRecognizer:pan];

    [keyWindow addSubview:gFloatingButton];
    [keyWindow bringSubviewToFront:gFloatingButton];
}

+ (void)toggleCopyState {
    gIsCopyEnabled = !gIsCopyEnabled;
    
    if (gIsCopyEnabled) {
        // --- 开启模式 ---
        [gFloatingButton setTitle:@"开" forState:UIControlStateNormal];
        gFloatingButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:0.8]; // 绿色
        
        // 立即对当前 WebView 注入
        if (gCurrentWebView) {
            [gCurrentWebView injectForceCopyScript];
            [self showToast:@"Neko:复制功能已开启"];
        }
    } else {
        // --- 关闭模式 ---
        [gFloatingButton setTitle:@"关" forState:UIControlStateNormal];
        gFloatingButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.8]; // 红色
        
        // 刷新网页以清除注入的代码 (通过校验的关键!)
        if (gCurrentWebView) {
            [gCurrentWebView reload];
            [self showToast:@"Neko:复制功能已关闭"];
        }
    }
}

+ (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view;
    CGPoint translation = [pan translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:view.superview];
}

+ (void)showToast:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:nil];
    });
}

// --- 核心注入逻辑 ---

- (void)injectForceCopyScript {
    // 只有在开关开启时才注入
    if (!gIsCopyEnabled) return;
    
    NSLog(@"[ForceSwitch] 正在注入破解脚本...");

    // 针对 custom.css 的暴力破解脚本 (同之前版本)
    NSString *jsSource = 
    @"var css = 'html, body, * { -webkit-user-select: text !important; user-select: text !important; -webkit-touch-callout: default !important; }';"
    @"var style = document.createElement('style');"
    @"style.innerHTML = css;"
    @"document.head.appendChild(style);"
    @"setInterval(function() {"
    @"  if(document.documentElement) document.documentElement.style.webkitUserSelect = 'text';"
    @"  if(document.body) document.body.style.webkitUserSelect = 'text';"
    @"}, 500);"; // 这里的定时器确保即便页面部分刷新，也能维持可复制状态

    // 我们直接用 evaluateJavaScript 立即执行，不用 UserScript 了，这样开关响应更快
    [self evaluateJavaScript:jsSource completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        if (error) NSLog(@"注入错误: %@", error);
    }];
}

// --- Swizzling 实现 ---

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
    gCurrentWebView = webView; // 捕获实例
    return webView;
}

- (instancetype)fs_initWithCoder:(NSCoder *)coder {
    WKWebView *webView = [self fs_initWithCoder:coder];
    gCurrentWebView = webView; // 捕获实例
    return webView;
}

// 还需要 Hook 导航完成的方法，以防用户在开启状态下点击了网页内的链接跳转，需要补针
// 这里为了代码简洁，我们在 injectForceCopyScript 里用了 setInterval，所以不需要额外 Hook didFinishNavigation
// 但为了保险，建议更新 gCurrentWebView

@end
