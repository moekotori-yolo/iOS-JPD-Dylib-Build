// ForceUserSelect.m
// 编译目标: iOS Dynamic Library (.dylib)

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@implementation WKWebView (ForceUserSelect)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[ForceUserSelect] 插件已加载 - 针对 custom.css 优化版");
        
        // Hook 两种常用的初始化方法
        [self swizzleSelector:@selector(initWithFrame:configuration:) 
                 withSelector:@selector(fus_initWithFrame:configuration:)];
        [self swizzleSelector:@selector(initWithCoder:) 
                 withSelector:@selector(fus_initWithCoder:)];
    });
}

+ (void)swizzleSelector:(SEL)orig withSelector:(SEL)swiz {
    Class cls = [self class];
    Method mOrig = class_getInstanceMethod(cls, orig);
    Method mSwiz = class_getInstanceMethod(cls, swiz);
    if (class_addMethod(cls, orig, method_getImplementation(mSwiz), method_getTypeEncoding(mSwiz))) {
        class_replaceMethod(cls, swiz, method_getImplementation(mOrig), method_getTypeEncoding(mOrig));
    } else {
        method_exchangeImplementations(mOrig, mSwiz);
    }
}

// --- 注入逻辑 ---

- (void)injectAntiBlockerScript {
    if (!self.configuration.userContentController) return;

    // 针对你发现的 custom.css，我们使用 !important 覆盖它
    // 并添加 setInterval 暴力守护，防止它被后续加载的 CSS 覆盖
    NSString *jsSource = 
    @"var css = 'html, body, * { -webkit-user-select: text !important; user-select: text !important; -webkit-touch-callout: default !important; }';"
    @"var style = document.createElement('style');"
    @"style.innerHTML = css;"
    @"document.head.appendChild(style);"
    
    // 定时器守护 (每500毫秒强制改一次，专门对付顽固的 css 文件)
    @"setInterval(function() {"
    @"  document.documentElement.style.webkitUserSelect = 'text';"
    @"  document.documentElement.style.userSelect = 'text';"
    @"  document.body.style.webkitUserSelect = 'text';"
    @"}, 500);";

    WKUserScript *script = [[WKUserScript alloc] initWithSource:jsSource
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd // 改为 End，确保在 custom.css 加载后执行
                                               forMainFrameOnly:NO];
    
    [self.configuration.userContentController addUserScript:script];
    NSLog(@"[ForceUserSelect] 注入脚本成功 (Targeting custom.css)");
}

// --- Swizzled Methods ---

- (instancetype)fus_initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    WKWebView *webView = [self fus_initWithFrame:frame configuration:configuration];
    [webView injectAntiBlockerScript];
    return webView;
}

- (instancetype)fus_initWithCoder:(NSCoder *)coder {
    WKWebView *webView = [self fus_initWithCoder:coder];
    [webView injectAntiBlockerScript];
    return webView;
}

@end
