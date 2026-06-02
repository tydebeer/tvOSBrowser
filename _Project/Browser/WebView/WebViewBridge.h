// WebViewBridge.h
// Objective-C bridge for WKWebView. Keeps all WKWebView interaction in one place,
// isolating the private-API usage from the Swift codebase.

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol WebViewBridgeDelegate <NSObject>
- (void)bridgeDidStartLoad;
- (void)bridgeDidFinishLoadWithURL:(NSString *)url title:(NSString *)title;
- (void)bridgeDidFailLoadWithError:(NSError *)error requestURL:(nullable NSString *)requestURL;
- (void)bridgeDidUpdateNavigationCanGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward;
@end

@interface WebViewBridge : NSObject

@property (nonatomic, weak, nullable) id<WebViewBridgeDelegate> delegate;
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
- (void)evaluateJavaScript:(NSString *)js completionHandler:(void (^ _Nullable)(id _Nullable result, NSError * _Nullable error))completionHandler;
- (void)clearCache;
- (void)clearCookiesWithCompletion:(void (^)(void))completion;
- (void)setFrame:(CGRect)frame;

@end

NS_ASSUME_NONNULL_END
