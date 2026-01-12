// ForceUserSelect.m
// 适用于非越狱环境注入

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

@implementation WKWebView (ForceUserSelect)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[ForceUserSelect] === Dylib Loaded ===");
        
        // 1. Hook 代码初始化方法 (initWithFrame:configuration:)
        [self swizzleSelector:@selector(initWithFrame:configuration:) 
                 withSelector:@selector(fus_initWithFrame:configuration:)];
        
        // 2. Hook Storyboard/XIB 初始化方法 (initWithCoder:)
        // 很多 App 界面是拖出来的，必须 Hook 这个，否则无效！
        [self swizzleSelector:@selector(initWithCoder:) 
                 withSelector:@selector(fus_initWithCoder:)];
    });
}

// 通用 Swizzle 工具方法
+ (void)swizzleSelector:(SEL)originalSelector withSelector:(SEL)swizzledSelector {
    Class class = [self class];
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);

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
}

// --- 你的 Flex 3 逻辑实现 ---

- (void)applyFlexLogic {
    // 这里的 self 就是 webView 实例
    NSLog(@"[ForceUserSelect] Applying logic to WebView: %@", self);

    @try {
        // 1. 启用用户选择功能 (对应 Flex: [self setValue:@YES forKey:@"_userSelectEnabled"])
        [self setValue:@YES forKey:@"_userSelectEnabled"];
        
        // 2. 启用 Preferences 设置 (对应 Flex: [self.preferences setValue...])
        // 注意：WKWebView 本身没有 preferences 属性，通常在 configuration 里
        if (self.configuration && self.configuration.preferences) {
            [self.configuration.preferences setValue:@YES forKey:@"_userSelectEnabled"];
        }
        
        // 3. 创建 CSS 注入脚本 (你的原始 CSS)
        NSString *cssInjection = @"var style = document.createElement('style'); style.innerHTML = 'html, body, * { -webkit-user-select: text !important; -khtml-user-select: text !important; -moz-user-select: text !important; -o-user-select: text !important; user-select: text !important; cursor: text !important; }'; document.head.appendChild(style);";
        
        // 4. 创建并添加用户脚本
        WKUserScript *userScript = [[WKUserScript alloc] initWithSource:cssInjection 
                                                          injectionTime:WKUserScriptInjectionTimeAtDocumentStart 
                                                       forMainFrameOnly:NO]; // 建议改为 NO 以支持 iframe，Flex代码里是YES
        
        if (self.configuration && self.configuration.userContentController) {
            [self.configuration.userContentController addUserScript:userScript];
            NSLog(@"[ForceUserSelect] CSS Script Injected Successfully");
        }
        
    } @catch (NSException *exception) {
        NSLog(@"[ForceUserSelect] Error: %@", exception);
    }
}

// --- Swizzled Methods ---

- (instancetype)fus_initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    // 调用原始方法 (相当于 ORIG())
    WKWebView *webView = [self fus_initWithFrame:frame configuration:configuration];
    
    // 执行你的逻辑
    [webView applyFlexLogic];
    
    return webView;
}

- (instancetype)fus_initWithCoder:(NSCoder *)coder {
    // 调用原始方法 (相当于 ORIG())
    WKWebView *webView = [self fus_initWithCoder:coder];
    
    // 执行你的逻辑
    [webView applyFlexLogic];
    
    return webView;
}

@end
