#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@implementation WKWebView (ForceUserSelect)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[ForceUserSelect] Dylib loaded!");
        
        // --- 1. 调试弹窗 (确认 Dylib 是否注入成功) ---
        // 这里的延迟是为了等待 KeyWindow 创建，否则弹窗可能不显示
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
            if (root) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"NEkoHAck注入成功"
                                                                             message:@"ForceUserSelect 插件已加载\n如果你看到这个，说明 NEkoPJ复制 运行正常。"
                                                                      preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [root presentViewController:alert animated:YES completion:nil];
            }
        });

        // --- 2. 执行 Swizzling ---
        [self swizzleSelector:@selector(initWithFrame:configuration:) with:@selector(fus_initWithFrame:configuration:)];
        [self swizzleSelector:@selector(initWithCoder:) with:@selector(fus_initWithCoder:)];
    });
}

// 辅助 Swizzle 方法
+ (void)swizzleSelector:(SEL)originalSelector with:(SEL)swizzledSelector {
    Class class = [self class];
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);

    BOOL didAddMethod = class_addMethod(class, originalSelector,
                                        method_getImplementation(swizzledMethod),
                                        method_getTypeEncoding(swizzledMethod));
    if (didAddMethod) {
        class_replaceMethod(class, swizzledSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

// --- Hook 1: 代码初始化 ---
- (instancetype)fus_initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    WKWebView *webView = [self fus_initWithFrame:frame configuration:configuration];
    [webView applyUserSelectSettings];
    return webView;
}

// --- Hook 2: Storyboard/XIB 初始化 (关键！很多 App 用这个) ---
- (instancetype)fus_initWithCoder:(NSCoder *)coder {
    WKWebView *webView = [self fus_initWithCoder:coder];
    [webView applyUserSelectSettings];
    return webView;
}

// --- 通用配置逻辑 ---
- (void)applyUserSelectSettings {
    if (!self) return;
    
    NSLog(@"[ForceUserSelect] Configuring WebView instance...");

    // 1. 开启私有 API
    @try {
        [self setValue:@YES forKey:@"_userSelectEnabled"];
        if (self.configuration.preferences) {
            [self.configuration.preferences setValue:@YES forKey:@"_userSelectEnabled"];
        }
    } @catch (NSException *e) { }

    // 2. 注入 CSS (核心)
    NSString *css = @"var style = document.createElement('style');"
                    @"style.innerHTML = 'html, body, * { -webkit-user-select: text !important; user-select: text !important; -webkit-touch-callout: default !important; }';"
                    @"document.head.appendChild(style);";
    
    WKUserScript *script = [[WKUserScript alloc] initWithSource:css
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                               forMainFrameOnly:NO];
    
    if (self.configuration.userContentController) {
        [self.configuration.userContentController addUserScript:script];
    }
}

@end

