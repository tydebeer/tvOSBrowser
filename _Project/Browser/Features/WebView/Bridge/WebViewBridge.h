// WebViewBridge.h
// Objective-C bridge for WKWebView. Keeps all WKWebView interaction in one place,
// isolating the private-API usage from the Swift codebase.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WebViewBridge : NSObject

@property (nonatomic, copy, nullable) void (^onStartLoad)(void);
@property (nonatomic, copy, nullable) void (^onFinishLoad)(NSString *url, NSString *title);
@property (nonatomic, copy, nullable) void (^onFailLoad)(NSError *error, NSString * _Nullable requestURL);
@property (nonatomic, copy, nullable) void (^onUpdateNavigation)(BOOL canGoBack, BOOL canGoForward);
@property (nonatomic, copy, nullable) void (^onJavaScriptAlert)(NSString *message, void (^completionHandler)(void));
@property (nonatomic, copy, nullable) void (^onJavaScriptConfirm)(NSString *message, void (^completionHandler)(BOOL result));
@property (nonatomic, readonly) BOOL isAvailable;
@property (nonatomic, readonly) UIView *webView;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
@property (nonatomic, readonly, nullable) NSURL *currentURL;
@property (nonatomic, readonly, nullable) NSString *currentTitle;
@property (nonatomic, readonly) UIScrollView *scrollView;

- (instancetype)initWithUserAgent:(NSString *)userAgent NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)loadURL:(NSURL *)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
/// Desktop-like page zoom (1.0 = 100%). Uses WKWebView `pageZoom` when available.
- (void)setPageZoom:(CGFloat)zoom;
- (CGFloat)pageZoom;
- (void)evaluateJavaScript:(NSString *)js completionHandler:(void (^ _Nullable)(id _Nullable result, NSError * _Nullable error))completionHandler;
/// Runs JS as a user gesture when a private selector is available (needed for click → navigation).
- (void)evaluateJavaScriptAsUserGesture:(NSString *)js completionHandler:(void (^ _Nullable)(id _Nullable result, NSError * _Nullable error))completionHandler;
/// Best-effort native click at a point in web-view coordinates.
- (void)simulateClickAtPoint:(CGPoint)point;
- (void)clearCache;
- (void)clearCookiesWithCompletion:(void (^)(void))completion;
- (void)setFrame:(CGRect)frame;

@end

NS_ASSUME_NONNULL_END
