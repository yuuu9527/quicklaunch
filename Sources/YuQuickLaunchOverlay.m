#import "YuQuickLaunchOverlay.h"
#import "YuQuickLaunchConfig.h"
#import "YuQuickLaunchPreferences.h"
#import "YuQuickLaunchPanel.h"
#import "YuQuickLaunchApps.h"

static const NSInteger YuQuickLaunchTriggerBottomRight = 0;
static const NSInteger YuQuickLaunchTriggerBottomFull = 1;
static const NSInteger YuQuickLaunchTriggerHold = 2;
static const NSInteger YuQuickLaunchTriggerOff = 3;

static const UIWindowLevel YuQuickLaunchWindowLevel = 10000000.0;
static const CGFloat YuQuickLaunchPullThreshold = 42.0;

#pragma mark - Window

@interface YuQuickLaunchWindow : UIWindow
@end

@implementation YuQuickLaunchWindow

// The window only takes key status when the search field needs the keyboard;
// showing it never steals focus from the app below.
- (BOOL)canBecomeKeyWindow {
    return YES;
}

@end

#pragma mark - Hit testing view

@interface YuQuickLaunchHitView : UIView
@property (nonatomic, copy) CGRect (^yu_quicklaunch_zoneProvider)(void);
@property (nonatomic, assign) BOOL yu_quicklaunch_blocksAllTouches;
@end

@implementation YuQuickLaunchHitView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.yu_quicklaunch_blocksAllTouches) {
        return [super hitTest:point withEvent:event];
    }
    if (!self.yu_quicklaunch_zoneProvider) {
        return nil;
    }
    CGRect zone = self.yu_quicklaunch_zoneProvider();
    if (CGRectIsEmpty(zone) || !CGRectContainsPoint(zone, point)) {
        // Outside the trigger strip every touch belongs to the app below.
        return nil;
    }
    return [super hitTest:point withEvent:event];
}

@end

#pragma mark - Overlay

@interface YuQuickLaunchOverlay () <YuQuickLaunchPanelControllerDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) YuQuickLaunchWindow *yu_quicklaunch_window;
@property (nonatomic, strong) YuQuickLaunchHitView *yu_quicklaunch_hitView;
@property (nonatomic, strong) UIPanGestureRecognizer *yu_quicklaunch_pan;
@property (nonatomic, strong) UILongPressGestureRecognizer *yu_quicklaunch_hold;
@property (nonatomic, strong) YuQuickLaunchPanelController *yu_quicklaunch_panel;
@property (nonatomic, assign) NSInteger yu_quicklaunch_mode;
@property (nonatomic, assign) BOOL yu_quicklaunch_fired;
@property (nonatomic, assign) NSInteger yu_quicklaunch_retries;
@property (nonatomic, assign) BOOL yu_quicklaunch_hiding;
@end

@implementation YuQuickLaunchOverlay

+ (instancetype)yu_quicklaunch_shared {
    static YuQuickLaunchOverlay *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yu_quicklaunch_preferencesChanged)
                                                     name:YuQuickLaunchPreferencesChanged
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Lifecycle

- (void)yu_quicklaunch_install {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self yu_quicklaunch_install];
        });
        return;
    }
    YuQuickLaunchConfig *config = [YuQuickLaunchConfig yu_quicklaunch_shared];
    NSInteger mode = [[config yu_quicklaunch_valueForKey:@"triggerMode" defaultValue:@(YuQuickLaunchTriggerBottomRight)] integerValue];
    self.yu_quicklaunch_mode = mode;

    if (![config yu_quicklaunch_isEnabled] || mode == YuQuickLaunchTriggerOff) {
        [self yu_quicklaunch_uninstall];
        return;
    }

    if (!self.yu_quicklaunch_window && ![self yu_quicklaunch_createWindow]) {
        [self yu_quicklaunch_scheduleRetry];
        return;
    }
    [self yu_quicklaunch_applyGestures];
}

- (void)yu_quicklaunch_reconfigure {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self yu_quicklaunch_reconfigure];
        });
        return;
    }
    [self yu_quicklaunch_install];
    if (self.yu_quicklaunch_panel) {
        [self yu_quicklaunch_hidePanel];
    }
}

- (void)yu_quicklaunch_uninstall {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self yu_quicklaunch_uninstall];
        });
        return;
    }
    if (self.yu_quicklaunch_panel) {
        [self yu_quicklaunch_hidePanel];
    }
    self.yu_quicklaunch_window.hidden = YES;
    [self.yu_quicklaunch_window.rootViewController.view removeFromSuperview];
    self.yu_quicklaunch_window.rootViewController = nil;
    self.yu_quicklaunch_window = nil;
    self.yu_quicklaunch_hitView = nil;
    self.yu_quicklaunch_pan = nil;
    self.yu_quicklaunch_hold = nil;
    self.yu_quicklaunch_retries = 0;
}

- (void)yu_quicklaunch_scheduleRetry {
    if (self.yu_quicklaunch_retries >= 40) {
        return;
    }
    self.yu_quicklaunch_retries += 1;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self yu_quicklaunch_install];
    });
}

- (BOOL)yu_quicklaunch_createWindow {
    UIWindowScene *scene = nil;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.windowScene) {
            scene = window.windowScene;
            break;
        }
    }
    if (!scene) {
        return NO;
    }

    YuQuickLaunchWindow *window = [[YuQuickLaunchWindow alloc] initWithWindowScene:scene];
    window.frame = [UIScreen mainScreen].bounds;
    window.windowLevel = YuQuickLaunchWindowLevel;
    window.backgroundColor = [UIColor clearColor];
    window.opaque = NO;
    window.hidden = YES;
    window.rootViewController = [[UIViewController alloc] init];
    window.rootViewController.view.backgroundColor = [UIColor clearColor];

    YuQuickLaunchHitView *hitView = [[YuQuickLaunchHitView alloc] initWithFrame:window.rootViewController.view.bounds];
    hitView.backgroundColor = [UIColor clearColor];
    hitView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    __weak typeof(self) weakSelf = self;
    hitView.yu_quicklaunch_zoneProvider = ^CGRect{
        return [weakSelf yu_quicklaunch_zoneRect];
    };
    [window.rootViewController.view addSubview:hitView];

    self.yu_quicklaunch_window = window;
    self.yu_quicklaunch_hitView = hitView;
    window.hidden = NO;
    self.yu_quicklaunch_retries = 0;
    return YES;
}

- (void)yu_quicklaunch_applyGestures {
    if (!self.yu_quicklaunch_hitView) {
        return;
    }
    if (self.yu_quicklaunch_pan) {
        [self.yu_quicklaunch_hitView removeGestureRecognizer:self.yu_quicklaunch_pan];
        self.yu_quicklaunch_pan = nil;
    }
    if (self.yu_quicklaunch_hold) {
        [self.yu_quicklaunch_hitView removeGestureRecognizer:self.yu_quicklaunch_hold];
        self.yu_quicklaunch_hold = nil;
    }

    if (self.yu_quicklaunch_mode == YuQuickLaunchTriggerHold) {
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(yu_quicklaunch_handleHold:)];
        hold.minimumPressDuration = 0.35;
        hold.allowableMovement = 22.0;
        hold.cancelsTouchesInView = NO;
        hold.delegate = self;
        [self.yu_quicklaunch_hitView addGestureRecognizer:hold];
        self.yu_quicklaunch_hold = hold;
    } else {
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(yu_quicklaunch_handlePan:)];
        pan.maximumNumberOfTouches = 1;
        pan.cancelsTouchesInView = NO;
        pan.delegate = self;
        [self.yu_quicklaunch_hitView addGestureRecognizer:pan];
        self.yu_quicklaunch_pan = pan;
    }
}

#pragma mark - Zone

- (CGRect)yu_quicklaunch_zoneRect {
    CGRect bounds = self.yu_quicklaunch_hitView ? self.yu_quicklaunch_hitView.bounds : [UIScreen mainScreen].bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width <= 0 || height <= 0) {
        return CGRectZero;
    }
    switch (self.yu_quicklaunch_mode) {
        case YuQuickLaunchTriggerBottomFull:
            return CGRectMake(0, height - 34.0, width, 34.0);
        case YuQuickLaunchTriggerHold:
            return CGRectMake(width * 0.52, height - 44.0, width * 0.48, 44.0);
        case YuQuickLaunchTriggerOff:
            return CGRectZero;
        default:
            return CGRectMake(width * 0.58, height - 34.0, width * 0.42, 34.0);
    }
}

#pragma mark - Gestures

- (void)yu_quicklaunch_handlePan:(UIPanGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.yu_quicklaunch_fired = NO;
        return;
    }
    if (recognizer.state != UIGestureRecognizerStateChanged || self.yu_quicklaunch_fired) {
        return;
    }
    CGPoint translation = [recognizer translationInView:recognizer.view];
    if (translation.y > -YuQuickLaunchPullThreshold) {
        return;
    }
    if (fabs(translation.y) < fabs(translation.x) * 1.2) {
        return;
    }
    self.yu_quicklaunch_fired = YES;
    [self yu_quicklaunch_trigger];
}

- (void)yu_quicklaunch_handleHold:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan || self.yu_quicklaunch_fired) {
        return;
    }
    self.yu_quicklaunch_fired = YES;
    [self yu_quicklaunch_trigger];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    CGRect zone = [self yu_quicklaunch_zoneRect];
    CGPoint point = [touch locationInView:self.yu_quicklaunch_hitView];
    return CGRectContainsPoint(zone, point);
}

#pragma mark - Panel

- (void)yu_quicklaunch_trigger {
    if (self.yu_quicklaunch_panel) {
        return;
    }
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];

    UIViewController *host = self.yu_quicklaunch_window.rootViewController;
    if (!host) {
        return;
    }
    YuQuickLaunchPanelController *panel = [[YuQuickLaunchPanelController alloc] init];
    panel.delegate = self;
    [host addChildViewController:panel];
    panel.view.frame = host.view.bounds;
    panel.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host.view addSubview:panel.view];
    [panel didMoveToParentViewController:host];
    [panel yu_quicklaunch_prepareForPresentation];

    self.yu_quicklaunch_panel = panel;
    self.yu_quicklaunch_hitView.yu_quicklaunch_blocksAllTouches = YES;
    [panel yu_quicklaunch_animateInWithCompletion:nil];
}

- (void)yu_quicklaunch_hidePanel {
    YuQuickLaunchPanelController *panel = self.yu_quicklaunch_panel;
    if (!panel || self.yu_quicklaunch_hiding) {
        return;
    }
    self.yu_quicklaunch_hiding = YES;
    __weak typeof(self) weakSelf = self;
    [panel yu_quicklaunch_animateOutWithCompletion:^{
        __strong typeof(weakSelf) self = weakSelf;
        [panel willMoveToParentViewController:nil];
        [panel.view removeFromSuperview];
        [panel removeFromParentViewController];
        self.yu_quicklaunch_panel = nil;
        self.yu_quicklaunch_hiding = NO;
        self.yu_quicklaunch_hitView.yu_quicklaunch_blocksAllTouches = NO;
    }];
}

- (void)yu_quicklaunch_panelDidRequestDismiss:(YuQuickLaunchPanelController *)panel {
    [self yu_quicklaunch_hidePanel];
}

- (void)yu_quicklaunch_panelDidLaunchBundleID:(NSString *)bundleID {
    [YuQuickLaunchApps yu_quicklaunch_launchBundleID:bundleID];
}

#pragma mark - Notifications

- (void)yu_quicklaunch_preferencesChanged {
    [self yu_quicklaunch_reconfigure];
}

@end
