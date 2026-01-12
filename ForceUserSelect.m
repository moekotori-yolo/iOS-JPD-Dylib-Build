// ForceUserSelect.m
// 编译目标: iOS Dynamic Library (.dylib / .framework)

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

// -----------------------------------------------------------------------------
// 核心逻辑
// -----------------------------------------------------------------------------

@implementation WKWebView (ForceUserSelect)

/**
 * +load 方法会在类被加载进内存时自动调用
 * 这是在非越狱环境下注入代码的最佳时机
 */
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];

        // 我们要 Hook 的目标方法 (Designated Initializer)
        SEL originalSelector = @selector(initWithFrame:configuration:);
        // 我们自定义的方法
        SEL swizzledSelector = @selector(fus_initWithFrame:configuration:);

        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);

        // 开始交换方法实现
        BOOL didAddMethod = class_addMethod(class,
                                            originalSelector,
                                            method_getImplementation(swizzledMethod),
                                            method_getTypeEncoding(swizzledMethod));

        if (didAddMethod) {
            class_replaceMethod(class,
                                swizzledSelector,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
        
        NSLog(@"[ForceUserSelect] WKWebView hook installed successfully.");
    });
}

/**
 * 这是我们要替换成的方法
 * 注意：在 Swizzling 中，调用 [self fus_initWithFrame...] 实际上是在调用原始的 initWithFrame...
 */
- (instancetype)fus_initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    // 1. 调用原始初始化方法 (通过调用当前方法名实现，因为已经交换了)
    WKWebView *webView = [self fus_initWithFrame:frame configuration:configuration];
    
    if (!webView) return nil;

    // 2. 核心功能逻辑
    @try {
        NSLog(@"[ForceUserSelect] Configuring WebView: %@", webView);

        // --- 启用私有 API (KVC) ---
        // 注意：这是非公开 API，App Store 审核可能会拒绝，但企业签/自签没问题
        @try {
            [webView setValue:@YES forKey:@"_userSelectEnabled"];
        } @catch (NSException *e) {
            NSLog(@"[ForceUserSelect] Failed to set webView key: %@", e);
        }

        @try {
            if (configuration.preferences) {
                [configuration.preferences setValue:@YES forKey:@"_userSelectEnabled"];
            }
        } @catch (NSException *e) {
            NSLog(@"[ForceUserSelect] Failed to set preferences key: %@", e);
        }

        // --- 注入 CSS ---
        NSString *cssSource = @"var style = document.createElement('style'); "
                              @"style.innerHTML = 'html, body, * { "
                              @"-webkit-user-select: text !important; "
                              @"-khtml-user-select: text !important; "
                              @"-moz-user-select: text !important; "
                              @"-o-user-select: text !important; "
                              @"user-select: text !important; "
                              @"cursor: text !important; }'; "
                              @"document.head.appendChild(style);";

        // --- 创建脚本 ---
        // injectionTime: 0 = AtDocumentStart (页面加载最开始时注入)
        WKUserScript *userScript = [[WKUserScript alloc] initWithSource:cssSource
                                                          injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                       forMainFrameOnly:NO]; // NO = 对 iframe 也生效

        // --- 添加到 UserContentController ---
        if (webView.configuration && webView.configuration.userContentController) {
            [webView.configuration.userContentController addUserScript:userScript];
            NSLog(@"[ForceUserSelect] CSS Injection Script added.");
        }
        
    } @catch (NSException *exception) {
        NSLog(@"[ForceUserSelect] Error in hook logic: %@", exception);
    }

    return webView;
}

@end
