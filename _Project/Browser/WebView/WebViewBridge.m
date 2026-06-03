// WebViewBridge.m
// Zero WebKit imports — every WKWebView/WKWebViewConfiguration/WKWebsiteDataStore
// reference goes through NSClassFromString or performSelector so the file compiles
// cleanly against the tvOS SDK regardless of WebKit header availability.

#import "WebViewBridge.h"

// KVO context tag
static void *kWebViewBridgeKVOContext = &kWebViewBridgeKVOContext;

// Runtime class helpers (avoids repeating NSClassFromString throughout)
static Class WKWebViewClass(void)          { return NSClassFromString(@"WKWebView"); }
static Class WKConfigurationClass(void)    { return NSClassFromString(@"WKWebViewConfiguration"); }
static Class WKDataStoreClass(void)        { return NSClassFromString(@"WKWebsiteDataStore"); }

@interface WebViewBridge ()
@property (nonatomic, strong) id wkWebView;      // runtime: WKWebView
@property (nonatomic, copy, nullable) NSString *pendingRequestURL;
@property (nonatomic) BOOL isObserving;
@end

@implementation WebViewBridge

// MARK: - Init

- (instancetype)initWithUserAgent:(NSString *)userAgent {
    self = [super init];
    if (!self) return nil;

    // Register user agent before the web view is created so WKWebView picks it up
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent": userAgent}];

    // Create WKWebViewConfiguration via runtime
    id config = [[WKConfigurationClass() alloc] init];
    [config setValue:@YES forKey:@"allowsInlineMediaPlayback"];

    // Create WKWebView via runtime — avoids tvOS SDK compile restrictions
    NSAssert(WKWebViewClass() != nil, @"WKWebView not found in tvOS runtime");
    _wkWebView = [[WKWebViewClass() alloc] initWithFrame:CGRectZero configuration:config];

    // Attach delegates (ObjC runtime selector-based, no WKNavigationDelegate import needed)
    [_wkWebView performSelector:NSSelectorFromString(@"setNavigationDelegate:") withObject:self];
    [_wkWebView performSelector:NSSelectorFromString(@"setUIDelegate:")         withObject:self];

    // Disable native scroll — cursor mode handles panning
    UIScrollView *sv = [self scrollView];
    sv.scrollEnabled = NO;
    sv.panGestureRecognizer.allowedTouchTypes = @[@(UITouchTypeIndirect)];
    sv.bounces = YES;

    [self startObserving];
    return self;
}

- (void)dealloc {
    [self stopObserving];
}

// MARK: - Public API

- (UIView *)webView       { return (UIView *)_wkWebView; }
- (BOOL)canGoBack         { return [[_wkWebView valueForKey:@"canGoBack"]    boolValue]; }
- (BOOL)canGoForward      { return [[_wkWebView valueForKey:@"canGoForward"] boolValue]; }
- (nullable NSURL *)currentURL   { return [_wkWebView valueForKey:@"URL"];   }
- (nullable NSString *)currentTitle { return [_wkWebView valueForKey:@"title"]; }

- (UIScrollView *)scrollView {
    return [_wkWebView valueForKey:@"scrollView"];
}

- (void)loadURL:(NSURL *)url {
    [_wkWebView performSelector:NSSelectorFromString(@"loadRequest:")
                     withObject:[NSURLRequest requestWithURL:url]];
}
- (void)goBack    { [_wkWebView performSelector:NSSelectorFromString(@"goBack")]; }
- (void)goForward { [_wkWebView performSelector:NSSelectorFromString(@"goForward")]; }
- (void)reload    { [_wkWebView performSelector:NSSelectorFromString(@"reload")]; }

- (void)setFrame:(CGRect)frame {
    ((UIView *)_wkWebView).frame = frame;
}

// MARK: - JavaScript

- (void)evaluateJavaScript:(NSString *)js
         completionHandler:(void (^)(id _Nullable, NSError * _Nullable))completionHandler {
    SEL sel = NSSelectorFromString(@"evaluateJavaScript:completionHandler:");
    if (![_wkWebView respondsToSelector:sel]) {
        if (completionHandler) completionHandler(nil, nil);
        return;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [_wkWebView performSelector:sel withObject:js withObject:[completionHandler copy]];
#pragma clang diagnostic pop
}

// MARK: - Cache & Cookies (all via NSClassFromString — no WebKit headers needed)

- (void)clearCache {
    // WKWebsiteDataStore.defaultDataStore
    id store = [WKDataStoreClass() performSelector:NSSelectorFromString(@"defaultDataStore")];
    // WKWebsiteDataStore.allWebsiteDataTypes
    NSSet *allTypes = [WKDataStoreClass() performSelector:NSSelectorFromString(@"allWebsiteDataTypes")];

    [store performSelector:NSSelectorFromString(@"fetchDataRecordsOfTypes:completionHandler:")
                withObject:allTypes
                withObject:^(NSArray *records) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [store performSelector:NSSelectorFromString(@"removeDataOfTypes:forDataRecords:completionHandler:")
                    withObject:allTypes
                    withObject:records];
#pragma clang diagnostic pop
    }];
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

- (void)clearCookiesWithCompletion:(void (^)(void))completion {
    id store = [WKDataStoreClass() performSelector:NSSelectorFromString(@"defaultDataStore")];
    // WKWebsiteDataTypeCookies is the string "WKWebsiteDataTypeCookies"
    NSSet *cookieTypes = [NSSet setWithObject:@"WKWebsiteDataTypeCookies"];

    [store performSelector:NSSelectorFromString(@"fetchDataRecordsOfTypes:completionHandler:")
                withObject:cookieTypes
                withObject:^(NSArray *records) {
        void (^done)(void) = ^{
            NSHTTPCookieStorage *s = [NSHTTPCookieStorage sharedHTTPCookieStorage];
            for (NSHTTPCookie *c in s.cookies.copy) [s deleteCookie:c];
            if (completion) dispatch_async(dispatch_get_main_queue(), completion);
        };
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [store performSelector:NSSelectorFromString(@"removeDataOfTypes:forDataRecords:completionHandler:")
                    withObject:cookieTypes
                    withObject:records];
#pragma clang diagnostic pop
        done();
    }];
}

// MARK: - KVO

- (void)startObserving {
    if (_isObserving) return;
    NSObject *wv = (NSObject *)_wkWebView;
    for (NSString *kp in @[@"loading", @"URL", @"title", @"canGoBack", @"canGoForward"]) {
        [wv addObserver:self forKeyPath:kp options:NSKeyValueObservingOptionNew context:kWebViewBridgeKVOContext];
    }
    _isObserving = YES;
}

- (void)stopObserving {
    if (!_isObserving) return;
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
                [self.delegate bridgeDidStartLoad];
            } else {
                [self.delegate bridgeDidFinishLoadWithURL:self.currentURL.absoluteString ?: @""
                                                   title:self.currentTitle ?: @""];
            }
        } else if ([keyPath isEqualToString:@"canGoBack"] || [keyPath isEqualToString:@"canGoForward"]) {
            [self.delegate bridgeDidUpdateNavigationCanGoBack:self.canGoBack canGoForward:self.canGoForward];
        }
    });
}

// MARK: - Navigation delegate selectors (matched via ObjC runtime, no formal conformance)

- (void)webView:(id)webView didStartProvisionalNavigation:(id)navigation {
    self.pendingRequestURL = self.currentURL.absoluteString;
}

- (void)webView:(id)webView didFailProvisionalNavigation:(id)navigation withError:(NSError *)error {
    if (error.code == NSURLErrorCancelled || error.code == 204) return;
    [self.delegate bridgeDidFailLoadWithError:error requestURL:self.pendingRequestURL];
}

- (void)webView:(id)webView didFail:(id)navigation withError:(NSError *)error {
    if (error.code == NSURLErrorCancelled || error.code == 204) return;
    [self.delegate bridgeDidFailLoadWithError:error requestURL:self.pendingRequestURL];
}

// MARK: - UI delegate selectors

- (void)webView:(id)webView
    runJavaScriptAlertPanelWithMessage:(NSString *)message
                      initiatedByFrame:(id)frame
                     completionHandler:(void (^)(void))completionHandler {
    if (completionHandler) completionHandler(); // must always call the handler
}

@end
