// WebViewBridge.m
// Uses NSClassFromString to create WKWebView, bypassing tvOS SDK restrictions
// while keeping full WKWebView functionality for sideloaded apps.

#import "WebViewBridge.h"

// KVO context
static void *kWebViewBridgeKVOContext = &kWebViewBridgeKVOContext;

@interface WebViewBridge ()
@property (nonatomic, strong) id wkWebView; // runtime type: WKWebView
@property (nonatomic, copy, nullable) NSString *pendingRequestURL;
@property (nonatomic) BOOL isObserving;
@end

@implementation WebViewBridge

- (instancetype)initWithUserAgent:(NSString *)userAgent {
    self = [super init];
    if (!self) return nil;

    // Register user agent before creating the web view
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent": userAgent}];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;

    // Create WKWebView via NSClassFromString — avoids tvOS SDK compile restrictions
    Class wkClass = NSClassFromString(@"WKWebView");
    NSAssert(wkClass != nil, @"WKWebView not available at runtime");
    _wkWebView = [[wkClass alloc] initWithFrame:CGRectZero configuration:config];

    // Set delegates via performSelector to avoid type-checking on tvOS
    [_wkWebView performSelector:NSSelectorFromString(@"setNavigationDelegate:") withObject:self];
    [_wkWebView performSelector:NSSelectorFromString(@"setUIDelegate:") withObject:self];

    // Disable scroll so cursor mode can handle panning
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

- (UIView *)webView {
    return (UIView *)_wkWebView;
}

- (BOOL)canGoBack {
    return [[_wkWebView valueForKey:@"canGoBack"] boolValue];
}

- (BOOL)canGoForward {
    return [[_wkWebView valueForKey:@"canGoForward"] boolValue];
}

- (nullable NSURL *)currentURL {
    return [_wkWebView valueForKey:@"URL"];
}

- (nullable NSString *)currentTitle {
    return [_wkWebView valueForKey:@"title"];
}

- (UIScrollView *)scrollView {
    return [_wkWebView valueForKey:@"scrollView"];
}

- (void)loadURL:(NSURL *)url {
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [_wkWebView performSelector:NSSelectorFromString(@"loadRequest:") withObject:request];
}

- (void)goBack {
    [_wkWebView performSelector:NSSelectorFromString(@"goBack")];
}

- (void)goForward {
    [_wkWebView performSelector:NSSelectorFromString(@"goForward")];
}

- (void)reload {
    [_wkWebView performSelector:NSSelectorFromString(@"reload")];
}

- (void)setFrame:(CGRect)frame {
    ((UIView *)_wkWebView).frame = frame;
}

- (void)evaluateJavaScript:(NSString *)js completionHandler:(void (^)(id _Nullable, NSError * _Nullable))completionHandler {
    // ObjC blocks are objects — performSelector:withObject:withObject: works cleanly here.
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

- (void)clearCache {
    WKWebsiteDataStore *store = [WKWebsiteDataStore defaultDataStore];
    NSSet *types = [WKWebsiteDataStore allWebsiteDataTypes];
    [store fetchDataRecordsOfTypes:types completionHandler:^(NSArray *records) {
        [store removeDataOfTypes:types forDataRecords:records completionHandler:^{}];
    }];
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

- (void)clearCookiesWithCompletion:(void (^)(void))completion {
    WKWebsiteDataStore *store = [WKWebsiteDataStore defaultDataStore];
    NSSet *cookieTypes = [NSSet setWithObject:WKWebsiteDataTypeCookies];
    [store fetchDataRecordsOfTypes:cookieTypes completionHandler:^(NSArray *records) {
        [store removeDataOfTypes:cookieTypes forDataRecords:records completionHandler:^{
            NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
            for (NSHTTPCookie *cookie in storage.cookies.copy) {
                [storage deleteCookie:cookie];
            }
            if (completion) dispatch_async(dispatch_get_main_queue(), completion);
        }];
    }];
}

// MARK: - KVO

- (void)startObserving {
    if (_isObserving) return;
    NSObject *wv = (NSObject *)_wkWebView;
    [wv addObserver:self forKeyPath:@"loading" options:NSKeyValueObservingOptionNew context:kWebViewBridgeKVOContext];
    [wv addObserver:self forKeyPath:@"URL" options:NSKeyValueObservingOptionNew context:kWebViewBridgeKVOContext];
    [wv addObserver:self forKeyPath:@"title" options:NSKeyValueObservingOptionNew context:kWebViewBridgeKVOContext];
    [wv addObserver:self forKeyPath:@"canGoBack" options:NSKeyValueObservingOptionNew context:kWebViewBridgeKVOContext];
    [wv addObserver:self forKeyPath:@"canGoForward" options:NSKeyValueObservingOptionNew context:kWebViewBridgeKVOContext];
    _isObserving = YES;
}

- (void)stopObserving {
    if (!_isObserving) return;
    NSObject *wv = (NSObject *)_wkWebView;
    [wv removeObserver:self forKeyPath:@"loading" context:kWebViewBridgeKVOContext];
    [wv removeObserver:self forKeyPath:@"URL" context:kWebViewBridgeKVOContext];
    [wv removeObserver:self forKeyPath:@"title" context:kWebViewBridgeKVOContext];
    [wv removeObserver:self forKeyPath:@"canGoBack" context:kWebViewBridgeKVOContext];
    [wv removeObserver:self forKeyPath:@"canGoForward" context:kWebViewBridgeKVOContext];
    _isObserving = NO;
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath
                      ofObject:(nullable id)object
                        change:(nullable NSDictionary *)change
                       context:(nullable void *)context {
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
                NSString *url = self.currentURL.absoluteString ?: @"";
                NSString *title = self.currentTitle ?: @"";
                [self.delegate bridgeDidFinishLoadWithURL:url title:title];
            }
        } else if ([keyPath isEqualToString:@"canGoBack"] || [keyPath isEqualToString:@"canGoForward"]) {
            [self.delegate bridgeDidUpdateNavigationCanGoBack:self.canGoBack canGoForward:self.canGoForward];
        }
    });
}

// MARK: - WKNavigationDelegate (via ObjC runtime selector matching, no formal conformance needed)

// Called when load starts — supplemental to KVO, for pendingRequestURL tracking
- (void)webView:(id)webView didStartProvisionalNavigation:(id)navigation {
    self.pendingRequestURL = self.currentURL.absoluteString;
}

// Called on load failure
- (void)webView:(id)webView didFailProvisionalNavigation:(id)navigation withError:(NSError *)error {
    // Ignore cancelled (-999) and interim redirects (204)
    if (error.code == NSURLErrorCancelled || error.code == 204) return;
    [self.delegate bridgeDidFailLoadWithError:error requestURL:self.pendingRequestURL];
}

- (void)webView:(id)webView didFail:(id)navigation withError:(NSError *)error {
    if (error.code == NSURLErrorCancelled || error.code == 204) return;
    [self.delegate bridgeDidFailLoadWithError:error requestURL:self.pendingRequestURL];
}

// MARK: - WKUIDelegate (via ObjC runtime selector matching)

// Handle JS alert() calls from web pages
- (void)webView:(id)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(id)frame completionHandler:(void (^)(void))completionHandler {
    // Dispatch to delegate's view controller for presentation — not ideal from here,
    // but handle gracefully by completing without showing (WKWebView requires the block to be called)
    if (completionHandler) completionHandler();
}

@end
