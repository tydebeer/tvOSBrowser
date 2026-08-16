// WebViewBridge.m
// Zero WebKit imports — every WKWebView/WKWebViewConfiguration/WKWebsiteDataStore
// reference goes through NSClassFromString or performSelector so the file compiles
// cleanly against the tvOS SDK regardless of WebKit header availability.

#import "WebViewBridge.h"
#import <objc/message.h>
#import <dlfcn.h>

// All performSelector: calls in this file use NSSelectorFromString — intentional runtime dispatch.
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

// KVO context tag
static void *kWebViewBridgeKVOContext = &kWebViewBridgeKVOContext;

// Runtime class helpers (avoids repeating NSClassFromString throughout)
static Class WKWebViewClass(void)          { return NSClassFromString(@"WKWebView"); }
static Class WKConfigurationClass(void)    { return NSClassFromString(@"WKWebViewConfiguration"); }
static Class WKDataStoreClass(void)        { return NSClassFromString(@"WKWebsiteDataStore"); }

static void TVBAddUserScript(id userContent, NSString *source, BOOL mainFrameOnly) {
    Class userScriptClass = NSClassFromString(@"WKUserScript");
    if (!userScriptClass || !userContent || source.length == 0) return;
    SEL userScriptInitSel = NSSelectorFromString(@"initWithSource:injectionTime:forMainFrameOnly:");
    if (![userScriptClass instancesRespondToSelector:userScriptInitSel]) return;
    // WKUserScriptInjectionTimeAtDocumentStart == 0
    id script = ((id (*)(id, SEL, NSString *, NSInteger, BOOL))objc_msgSend)(
        [userScriptClass alloc], userScriptInitSel, source, 0, mainFrameOnly
    );
    SEL addSel = NSSelectorFromString(@"addUserScript:");
    if (script && [userContent respondsToSelector:addSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(userContent, addSel, script);
    }
}

// Runs in every frame (including cross-origin YouTube) so parent postMessage can click/play.
static NSString *TVBEmbedPointerUserScript(void) {
    return
    @"(function(){"
    "if(window.__tvbEmbedBridge)return;window.__tvbEmbedBridge=1;"
    "function fire(x,y,type){"
    "var el=document.elementFromPoint(x,y)||document.documentElement;"
    "function trust(evt){try{Object.defineProperty(evt,'isTrusted',{get:function(){return true;}});}catch(e){}return evt;}"
    "function send(name,Ctor,extra){"
    "if(!Ctor)return;"
    "var init={bubbles:true,cancelable:true,composed:true,view:window,clientX:x,clientY:y,screenX:x,screenY:y,button:0,buttons:0,detail:1};"
    "if(extra)for(var k in extra)init[k]=extra[k];"
    "try{el.dispatchEvent(trust(new Ctor(name,init)));}catch(e){}"
    "}"
    "if(type==='move'){"
    "if(typeof PointerEvent==='function')send('pointermove',PointerEvent,{pointerId:1,pointerType:'mouse',isPrimary:true,buttons:0,pressure:0});"
    "send('mousemove',MouseEvent,{buttons:0});"
    "return;"
    "}"
    "if(type==='down'||type==='click'){"
    "if(typeof PointerEvent==='function')send('pointerdown',PointerEvent,{pointerId:1,pointerType:'mouse',isPrimary:true,buttons:1,pressure:0.5});"
    "send('mousedown',MouseEvent,{buttons:1});"
    "}"
    "if(type==='up'||type==='click'){"
    "if(typeof PointerEvent==='function')send('pointerup',PointerEvent,{pointerId:1,pointerType:'mouse',isPrimary:true,buttons:0,pressure:0});"
    "send('mouseup',MouseEvent,{buttons:0});"
    "}"
    "if(type==='click'){"
    "send('click',MouseEvent,{buttons:0});"
    "try{el.click();}catch(e){}"
    "var v=document.querySelector('video');"
    "if(v&&v.paused){try{v.play();}catch(e2){}}"
    "}"
    "}"
    "window.addEventListener('message',function(ev){"
    "var data=ev.data;"
    "if(typeof data==='string'){try{data=JSON.parse(data);}catch(e){return;}}"
    "if(!data||data.__tvb!=='pointer')return;"
    "fire(Number(data.x)||0,Number(data.y)||0,data.type||'click');"
    "});"
    "})();";
}

@interface WebViewBridge ()
@property (nonatomic, strong) id wkWebView;      // runtime: WKWebView
@property (nonatomic, strong) UIView *fallbackView;
@property (nonatomic, strong) UIScrollView *fallbackScrollView;
@property (nonatomic, copy, nullable) NSString *pendingRequestURL;
@property (nonatomic) BOOL isObserving;
- (void)tvb_withWebViewInteraction:(void (NS_NOESCAPE ^)(void))block;
- (nullable id)tvb_pageWorld;
- (NSArray *)tvb_allFrames;
- (NSArray *)tvb_childFramesMatching:(nullable NSString *)fragment;
- (nullable NSString *)tvb_urlStringForFrame:(id)frame;
@end

@implementation WebViewBridge

// MARK: - Init

- (instancetype)initWithUserAgent:(NSString *)userAgent {
    self = [super init];
    if (!self) return nil;

    _fallbackView = [[UIView alloc] initWithFrame:CGRectZero];
    _fallbackView.backgroundColor = [UIColor blackColor];
    _fallbackScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];

    // Load WebKit at runtime — not in the public tvOS SDK but present on device/simulator
    static dispatch_once_t webKitOnce;
    dispatch_once(&webKitOnce, ^{
        dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_LAZY | RTLD_GLOBAL);
    });

    // Register user agent before the web view is created so WKWebView picks it up
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent": userAgent}];

    Class wkClass = WKWebViewClass();
    Class configClass = WKConfigurationClass();
    if (wkClass == Nil || configClass == Nil) {
        _wkWebView = nil;
        return self;
    }

    // Create WKWebViewConfiguration via runtime
    id config = [[configClass alloc] init];
    [config setValue:@YES forKey:@"allowsInlineMediaPlayback"];
    // Let synthetic clicks / iframe play() start media (YouTube embeds have no real TV touch).
    @try { [config setValue:@0 forKey:@"mediaTypesRequiringUserActionForPlayback"]; } @catch (__unused NSException *e) {}
    @try { [config setValue:@NO forKey:@"requiresUserActionForMediaPlayback"]; } @catch (__unused NSException *e) {}

    // Advertise a desktop-like pointer early so sites don't pick a touch/no-hover UI.
    id userContent = [config valueForKey:@"userContentController"];
    NSString *earlyJS =
        @"(function(){"
        "try{Object.defineProperty(navigator,'maxTouchPoints',{get:function(){return 0;},configurable:true});}catch(e){}"
        "if(window.__tvbEarlyMQ)return;window.__tvbEarlyMQ=1;"
        "var orig=window.matchMedia.bind(window);"
        "window.matchMedia=function(query){"
        "var q=String(query||'').toLowerCase().replace(/\\s+/g,'');"
        "function mq(m){return{matches:!!m,media:query,onchange:null,"
        "addListener:function(){},removeListener:function(){},"
        "addEventListener:function(){},removeEventListener:function(){},"
        "dispatchEvent:function(){return false;}};"
        "}"
        "if(q.indexOf('(hover:none)')!==-1||q.indexOf('(any-hover:none)')!==-1)return mq(false);"
        "if(q.indexOf('(hover:hover)')!==-1||q.indexOf('(any-hover:hover)')!==-1)return mq(true);"
        "if(q.indexOf('(pointer:coarse)')!==-1||q.indexOf('(any-pointer:coarse)')!==-1)return mq(false);"
        "if(q.indexOf('(pointer:fine)')!==-1||q.indexOf('(any-pointer:fine)')!==-1)return mq(true);"
        "if(q.indexOf('(pointer:none)')!==-1)return mq(false);"
        "return orig(query);"
        "};"
        "})();";
    TVBAddUserScript(userContent, earlyJS, YES);
    // Injected into every frame, including cross-origin YouTube embeds.
    TVBAddUserScript(userContent, TVBEmbedPointerUserScript(), NO);

    // Create WKWebView via runtime — avoids tvOS SDK compile restrictions
    id wkAlloc = [wkClass alloc];
    SEL initSel = NSSelectorFromString(@"initWithFrame:configuration:");
    _wkWebView = ((id (*)(id, SEL, CGRect, id))objc_msgSend)(wkAlloc, initSel, CGRectZero, config);
    if (_wkWebView == nil) {
        return self;
    }

    // Prefer explicit custom UA — UserDefaults alone is unreliable across tab instances.
    @try {
        [_wkWebView setValue:userAgent forKey:@"customUserAgent"];
    } @catch (__unused NSException *e) {}

    UIView *wvView = (UIView *)_wkWebView;
    wvView.backgroundColor = [UIColor clearColor];
    wvView.opaque = YES;

    // Attach delegates (ObjC runtime selector-based, no WKNavigationDelegate import needed)
    [_wkWebView performSelector:NSSelectorFromString(@"setNavigationDelegate:") withObject:self];
    [_wkWebView performSelector:NSSelectorFromString(@"setUIDelegate:")         withObject:self];

    // Pointer moves via ring + clickpad; page scrolls when pointer hits screen edges.
    UIScrollView *sv = [self scrollView];
    sv.scrollEnabled = NO;
    sv.panGestureRecognizer.enabled = NO;
    sv.panGestureRecognizer.allowedTouchTypes = @[@(UITouchTypeIndirect)];
    sv.bounces = YES;
    sv.backgroundColor = [UIColor clearColor];
    sv.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    sv.contentInset = UIEdgeInsetsZero;
    sv.scrollIndicatorInsets = UIEdgeInsetsZero;
    if ([sv respondsToSelector:@selector(setAutomaticallyAdjustsScrollIndicatorInsets:)]) {
        [sv setValue:@NO forKey:@"automaticallyAdjustsScrollIndicatorInsets"];
    }

    [self startObserving];
    return self;
}

- (void)dealloc {
    [self stopObserving];
}

// MARK: - Public API

- (BOOL)isAvailable { return _wkWebView != nil; }
- (UIView *)webView       { return _wkWebView ? (UIView *)_wkWebView : self.fallbackView; }
- (BOOL)canGoBack         { return _wkWebView ? [[_wkWebView valueForKey:@"canGoBack"]    boolValue] : NO; }
- (BOOL)canGoForward      { return _wkWebView ? [[_wkWebView valueForKey:@"canGoForward"] boolValue] : NO; }
- (nullable NSURL *)currentURL   { return _wkWebView ? [_wkWebView valueForKey:@"URL"] : nil;   }
- (nullable NSString *)currentTitle { return _wkWebView ? [_wkWebView valueForKey:@"title"] : nil; }

- (UIScrollView *)scrollView {
    if (!_wkWebView) return self.fallbackScrollView;
    return [_wkWebView valueForKey:@"scrollView"];
}

- (void)loadURL:(NSURL *)url {
    if (!_wkWebView) return;
    [_wkWebView performSelector:NSSelectorFromString(@"loadRequest:")
                     withObject:[NSURLRequest requestWithURL:url]];
}
- (void)goBack    { if (_wkWebView) [_wkWebView performSelector:NSSelectorFromString(@"goBack")]; }
- (void)goForward { if (_wkWebView) [_wkWebView performSelector:NSSelectorFromString(@"goForward")]; }
- (void)reload    { if (_wkWebView) [_wkWebView performSelector:NSSelectorFromString(@"reload")]; }

- (void)setPageZoom:(CGFloat)zoom {
    @try {
        [_wkWebView setValue:@(zoom) forKey:@"pageZoom"];
    } @catch (__unused NSException *e) {
        // Fallback: CSS zoom on the document root.
        NSString *js = [NSString stringWithFormat:
            @"(function(){ var r=document.documentElement; if(r) r.style.zoom='%f'; })()",
            (double)zoom];
        [self evaluateJavaScript:js completionHandler:nil];
    }
}

- (CGFloat)pageZoom {
    @try {
        NSNumber *value = [_wkWebView valueForKey:@"pageZoom"];
        if (value != nil) return value.doubleValue;
    } @catch (__unused NSException *e) {}
    return 1.0;
}

- (void)setFrame:(CGRect)frame {
    if (!_wkWebView) {
        self.fallbackView.frame = frame;
        return;
    }
    ((UIView *)_wkWebView).frame = frame;
}

// MARK: - JavaScript

- (void)evaluateJavaScript:(NSString *)js
         completionHandler:(void (^)(id _Nullable, NSError * _Nullable))completionHandler {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self evaluateJavaScript:js completionHandler:completionHandler];
        });
        return;
    }

    SEL sel = NSSelectorFromString(@"evaluateJavaScript:completionHandler:");
    if (![_wkWebView respondsToSelector:sel]) {
        if (completionHandler) completionHandler(nil, nil);
        return;
    }
    ((void (*)(id, SEL, NSString *, void (^)(id, NSError *)))objc_msgSend)(
        _wkWebView, sel, js, completionHandler
    );
}

- (void)evaluateJavaScriptAsUserGesture:(NSString *)js
                      completionHandler:(void (^)(id _Nullable, NSError * _Nullable))completionHandler {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self evaluateJavaScriptAsUserGesture:js completionHandler:completionHandler];
        });
        return;
    }

    // Try private "as user gesture" entry points used by WebKit internals.
    NSArray<NSString *> *selectors = @[
        @"_evaluateJavaScript:asAsync:withSourceURL:withUserGesture:completionHandler:",
        @"_evaluateJavaScriptWithoutUserGesture:completionHandler:", // last resort names vary by OS
    ];

    // Preferred: evaluateJavaScript:inFrame:inContentWorld:withUserGesture:completionHandler:
    SEL gestureSel = NSSelectorFromString(@"evaluateJavaScript:inFrame:inContentWorld:withUserGesture:completionHandler:");
    if ([_wkWebView respondsToSelector:gestureSel]) {
        id world = nil;
        Class worldClass = NSClassFromString(@"WKContentWorld");
        if ([worldClass respondsToSelector:NSSelectorFromString(@"pageWorld")]) {
            world = ((id (*)(Class, SEL))objc_msgSend)(worldClass, NSSelectorFromString(@"pageWorld"));
        }
        ((void (*)(id, SEL, NSString *, id, id, BOOL, void (^)(id, NSError *)))objc_msgSend)(
            _wkWebView, gestureSel, js, nil, world, YES, completionHandler
        );
        return;
    }

    SEL alt = NSSelectorFromString(@"_evaluateJavaScript:withSourceURL:withCompletionHandler:withUserGesture:");
    if ([_wkWebView respondsToSelector:alt]) {
        ((void (*)(id, SEL, NSString *, NSURL *, void (^)(id, NSError *), BOOL))objc_msgSend)(
            _wkWebView, alt, js, nil, completionHandler, YES
        );
        return;
    }

    (void)selectors;
    [self evaluateJavaScript:js completionHandler:completionHandler];
}

- (void)evaluateJavaScriptInChildFrames:(NSString *)js
                            urlContains:(NSString *)urlContains
                        withUserGesture:(BOOL)gesture
                      completionHandler:(void (^)(id _Nullable, NSError * _Nullable))completionHandler {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self evaluateJavaScriptInChildFrames:js
                                      urlContains:urlContains
                                  withUserGesture:gesture
                                completionHandler:completionHandler];
        });
        return;
    }
    if (!_wkWebView || js.length == 0) {
        if (completionHandler) completionHandler(@NO, nil);
        return;
    }

    NSArray *frames = [self tvb_childFramesMatching:urlContains];
    SEL gestureSel = NSSelectorFromString(@"evaluateJavaScript:inFrame:inContentWorld:withUserGesture:completionHandler:");
    if (frames.count == 0 || ![_wkWebView respondsToSelector:gestureSel]) {
        if (completionHandler) completionHandler(@NO, nil);
        return;
    }

    id world = [self tvb_pageWorld];
    dispatch_group_t group = dispatch_group_create();
    __block BOOL any = NO;
    for (id frame in frames) {
        dispatch_group_enter(group);
        @try {
            ((void (*)(id, SEL, NSString *, id, id, BOOL, void (^)(id, NSError *)))objc_msgSend)(
                _wkWebView, gestureSel, js, frame, world, gesture, ^(id result, NSError *error) {
                    (void)error;
                    if ([result isKindOfClass:[NSNumber class]] && [result boolValue]) any = YES;
                    dispatch_group_leave(group);
                }
            );
        } @catch (__unused NSException *e) {
            dispatch_group_leave(group);
        }
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (completionHandler) completionHandler(@(any), nil);
    });
}

- (nullable id)tvb_pageWorld {
    Class worldClass = NSClassFromString(@"WKContentWorld");
    if ([worldClass respondsToSelector:NSSelectorFromString(@"pageWorld")]) {
        return ((id (*)(Class, SEL))objc_msgSend)(worldClass, NSSelectorFromString(@"pageWorld"));
    }
    return nil;
}

- (NSArray *)tvb_allFrames {
    NSArray<NSString *> *keys = @[ @"_wk_frameInfos", @"_frames", @"allFrames", @"frames", @"_allFrames" ];
    for (NSString *key in keys) {
        @try {
            id value = [_wkWebView valueForKey:key];
            if ([value isKindOfClass:[NSArray class]] && [value count] > 0) return value;
        } @catch (__unused NSException *e) {}
    }
    NSArray<NSString *> *sels = @[ @"_wk_frameInfos", @"_frames", @"_allFrames", @"allFrames" ];
    for (NSString *name in sels) {
        SEL sel = NSSelectorFromString(name);
        if ([_wkWebView respondsToSelector:sel]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(_wkWebView, sel);
            if ([value isKindOfClass:[NSArray class]] && [value count] > 0) return value;
        }
    }
    return @[];
}

- (nullable NSString *)tvb_urlStringForFrame:(id)frame {
    if (!frame) return nil;
    @try {
        NSURL *url = [frame valueForKey:@"url"];
        if ([url isKindOfClass:[NSURL class]]) return url.absoluteString;
        if ([url isKindOfClass:[NSString class]]) return (NSString *)url;
    } @catch (__unused NSException *e) {}
    @try {
        NSURLRequest *request = [frame valueForKey:@"request"];
        if ([request isKindOfClass:[NSURLRequest class]]) return request.URL.absoluteString;
    } @catch (__unused NSException *e) {}
    return nil;
}

- (NSArray *)tvb_childFramesMatching:(NSString *)fragment {
    NSArray *all = [self tvb_allFrames];
    if (all.count == 0) return @[];
    NSString *needle = fragment.length ? fragment.lowercaseString : nil;
    NSMutableArray *out = [NSMutableArray array];
    for (id frame in all) {
        BOOL isMain = NO;
        @try {
            id flag = [frame valueForKey:@"isMainFrame"];
            if (flag) isMain = [flag boolValue];
        } @catch (__unused NSException *e) {}
        @try {
            id flag = [frame valueForKey:@"mainFrame"];
            if (flag) isMain = isMain || [flag boolValue];
        } @catch (__unused NSException *e) {}
        if (isMain) continue;
        if (needle) {
            NSString *urlString = [self tvb_urlStringForFrame:frame];
            if (urlString.length == 0 || [urlString.lowercaseString containsString:needle] == NO) continue;
        }
        [out addObject:frame];
    }
    return out;
}

- (void)tvb_withWebViewInteraction:(void (NS_NOESCAPE ^)(void))block {
    if (!_wkWebView || !block) return;
    UIView *wv = (UIView *)_wkWebView;
    BOOL wasEnabled = wv.userInteractionEnabled;
    wv.userInteractionEnabled = YES;
    block();
    wv.userInteractionEnabled = wasEnabled;
}

- (void)simulateClickAtPoint:(CGPoint)point {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self simulateClickAtPoint:point];
        });
        return;
    }

    [self tvb_withWebViewInteraction:^{
        // Private mouse simulation (present on some WebKit builds).
        NSArray<NSString *> *downSels = @[ @"_simulateMouseDownAt:", @"simulateMouseDownAt:" ];
        NSArray<NSString *> *upSels   = @[ @"_simulateMouseUpAt:",   @"simulateMouseUpAt:" ];
        NSArray<NSString *> *clickSels = @[
            @"_simulateMouseClickAt:button:count:",
            @"simulateMouseClickAt:button:count:"
        ];

        BOOL didClick = NO;
        for (NSString *name in clickSels) {
            SEL sel = NSSelectorFromString(name);
            if ([self->_wkWebView respondsToSelector:sel]) {
                // button 0 = left, count 1
                ((void (*)(id, SEL, CGPoint, unsigned long long, unsigned long long))objc_msgSend)(
                    self->_wkWebView, sel, point, 0, 1
                );
                didClick = YES;
                break;
            }
        }

        if (!didClick) {
            for (NSString *name in downSels) {
                SEL sel = NSSelectorFromString(name);
                if ([self->_wkWebView respondsToSelector:sel]) {
                    ((void (*)(id, SEL, CGPoint))objc_msgSend)(self->_wkWebView, sel, point);
                    break;
                }
            }
            for (NSString *name in upSels) {
                SEL sel = NSSelectorFromString(name);
                if ([self->_wkWebView respondsToSelector:sel]) {
                    ((void (*)(id, SEL, CGPoint))objc_msgSend)(self->_wkWebView, sel, point);
                    break;
                }
            }
        }
    }];
}

- (void)simulateMouseMoveAtPoint:(CGPoint)point {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self simulateMouseMoveAtPoint:point];
        });
        return;
    }
    if (!_wkWebView) return;

    [self tvb_withWebViewInteraction:^{
        NSArray<NSString *> *moveSels = @[
            @"_simulateMouseMoveAt:",
            @"simulateMouseMoveAt:",
            @"_simulateMouseMotionAt:",
            @"simulateMouseMotionAt:"
        ];
        for (NSString *name in moveSels) {
            SEL sel = NSSelectorFromString(name);
            if ([self->_wkWebView respondsToSelector:sel]) {
                ((void (*)(id, SEL, CGPoint))objc_msgSend)(self->_wkWebView, sel, point);
                return;
            }
        }
    }];
}

- (void)simulateMouseDownAtPoint:(CGPoint)point {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self simulateMouseDownAtPoint:point];
        });
        return;
    }
    if (!_wkWebView) return;
    [self tvb_withWebViewInteraction:^{
        NSArray<NSString *> *downSels = @[ @"_simulateMouseDownAt:", @"simulateMouseDownAt:" ];
        for (NSString *name in downSels) {
            SEL sel = NSSelectorFromString(name);
            if ([self->_wkWebView respondsToSelector:sel]) {
                ((void (*)(id, SEL, CGPoint))objc_msgSend)(self->_wkWebView, sel, point);
                return;
            }
        }
    }];
}

- (void)simulateMouseUpAtPoint:(CGPoint)point {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self simulateMouseUpAtPoint:point];
        });
        return;
    }
    if (!_wkWebView) return;
    [self tvb_withWebViewInteraction:^{
        NSArray<NSString *> *upSels = @[ @"_simulateMouseUpAt:", @"simulateMouseUpAt:" ];
        for (NSString *name in upSels) {
            SEL sel = NSSelectorFromString(name);
            if ([self->_wkWebView respondsToSelector:sel]) {
                ((void (*)(id, SEL, CGPoint))objc_msgSend)(self->_wkWebView, sel, point);
                return;
            }
        }
    }];
}

// MARK: - Cache & Cookies (all via NSClassFromString — no WebKit headers needed)

- (void)clearCache {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];

    Class storeClass = WKDataStoreClass();
    if (storeClass == Nil) return;

    id store = [storeClass performSelector:NSSelectorFromString(@"defaultDataStore")];
    NSSet *allTypes = [storeClass performSelector:NSSelectorFromString(@"allWebsiteDataTypes")];
    if (!store || !allTypes) return;

    SEL fetchSel = NSSelectorFromString(@"fetchDataRecordsOfTypes:completionHandler:");
    if (![store respondsToSelector:fetchSel]) return;

    ((void (*)(id, SEL, NSSet *, void (^)(NSArray *)))objc_msgSend)(
        store, fetchSel, allTypes, ^(NSArray *records) {
            SEL removeSel = NSSelectorFromString(@"removeDataOfTypes:forDataRecords:completionHandler:");
            if ([store respondsToSelector:removeSel]) {
                ((void (*)(id, SEL, NSSet *, NSArray *, void (^)(void)))objc_msgSend)(
                    store, removeSel, allTypes, records ?: @[], ^{ }
                );
            }
        }
    );
}

- (void)clearCookiesWithCompletion:(void (^)(void))completion {
    id store = [WKDataStoreClass() performSelector:NSSelectorFromString(@"defaultDataStore")];
    // WKWebsiteDataTypeCookies is the string "WKWebsiteDataTypeCookies"
    NSSet *cookieTypes = [NSSet setWithObject:@"WKWebsiteDataTypeCookies"];

    void (^finish)(void) = ^{
        NSHTTPCookieStorage *s = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *c in s.cookies.copy) [s deleteCookie:c];
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
    };

    SEL fetchSel = NSSelectorFromString(@"fetchDataRecordsOfTypes:completionHandler:");
    if (![store respondsToSelector:fetchSel]) {
        finish();
        return;
    }

    ((void (*)(id, SEL, NSSet *, void (^)(NSArray *)))objc_msgSend)(
        store, fetchSel, cookieTypes, ^(NSArray *records) {
            SEL removeSel = NSSelectorFromString(@"removeDataOfTypes:forDataRecords:completionHandler:");
            if ([store respondsToSelector:removeSel]) {
                ((void (*)(id, SEL, NSSet *, NSArray *, void (^)(void)))objc_msgSend)(
                    store, removeSel, cookieTypes, records ?: @[], ^{ finish(); }
                );
            } else {
                finish();
            }
        }
    );
}

// MARK: - KVO

- (void)startObserving {
    if (_isObserving || !_wkWebView) return;
    NSObject *wv = (NSObject *)_wkWebView;
    for (NSString *kp in @[@"loading", @"URL", @"title", @"canGoBack", @"canGoForward"]) {
        [wv addObserver:self forKeyPath:kp options:NSKeyValueObservingOptionNew context:kWebViewBridgeKVOContext];
    }
    _isObserving = YES;
}

- (void)stopObserving {
    if (!_isObserving || !_wkWebView) return;
    NSObject *wv = (NSObject *)_wkWebView;
    for (NSString *kp in @[@"loading", @"URL", @"title", @"canGoBack", @"canGoForward"]) {
        [wv removeObserver:self forKeyPath:kp context:kWebViewBridgeKVOContext];
    }
    _isObserving = NO;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context != kWebViewBridgeKVOContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([keyPath isEqualToString:@"loading"]) {
            BOOL loading = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
            if (loading) {
                if (self.onStartLoad) self.onStartLoad();
            } else {
                if (self.onFinishLoad) self.onFinishLoad(self.currentURL.absoluteString ?: @"", self.currentTitle ?: @"");
            }
        } else if ([keyPath isEqualToString:@"canGoBack"] || [keyPath isEqualToString:@"canGoForward"]) {
            if (self.onUpdateNavigation) self.onUpdateNavigation(self.canGoBack, self.canGoForward);
        }
    });
}

// MARK: - Navigation delegate selectors (matched via ObjC runtime, no formal conformance)

- (void)webView:(id)webView didStartProvisionalNavigation:(id)navigation {
    self.pendingRequestURL = self.currentURL.absoluteString;
}

- (void)webView:(id)webView didFailProvisionalNavigation:(id)navigation withError:(NSError *)error {
    if (error.code == NSURLErrorCancelled || error.code == 204) return;
    if (self.onFailLoad) self.onFailLoad(error, self.pendingRequestURL);
}

- (void)webView:(id)webView didFail:(id)navigation withError:(NSError *)error {
    if (error.code == NSURLErrorCancelled || error.code == 204) return;
    if (self.onFailLoad) self.onFailLoad(error, self.pendingRequestURL);
}

// MARK: - UI delegate selectors

- (void)webView:(id)webView
    runJavaScriptAlertPanelWithMessage:(NSString *)message
                      initiatedByFrame:(id)frame
                     completionHandler:(void (^)(void))completionHandler {
    if (self.onJavaScriptAlert) {
        self.onJavaScriptAlert(message ?: @"", ^{
            if (completionHandler) completionHandler();
        });
        return;
    }
    if (completionHandler) completionHandler();
}

- (void)webView:(id)webView
    runJavaScriptConfirmPanelWithMessage:(NSString *)message
                        initiatedByFrame:(id)frame
                       completionHandler:(void (^)(BOOL result))completionHandler {
    if (self.onJavaScriptConfirm) {
        self.onJavaScriptConfirm(message ?: @"", ^(BOOL result) {
            if (completionHandler) completionHandler(result);
        });
        return;
    }
    if (completionHandler) completionHandler(NO);
}

@end
