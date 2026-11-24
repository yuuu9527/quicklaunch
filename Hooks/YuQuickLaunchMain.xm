#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "YuQuickLaunchApps.h"
#import "YuQuickLaunchConfig.h"
#import "YuQuickLaunchOverlay.h"
#import "YuQuickLaunchPrivate.h"

// SpringBoard opens home screen apps through this method, so recording here keeps
// the panel's recent list in sync with normal usage. Installed lazily because the
// private framework may not be loaded when the tweak's constructor runs.
%group YuQuickLaunchRecents

%hook LSApplicationWorkspace

- (BOOL)openApplicationWithBundleID:(NSString *)bundleID {
    BOOL result = %orig;
    if (result && [bundleID isKindOfClass:[NSString class]]) {
        [YuQuickLaunchApps yu_quicklaunch_recordRecentBundleID:bundleID];
    }
    return result;
}

%end

%end

static BOOL gYuQuickLaunchRecentsHooked = NO;

static void yu_quicklaunch_installRecentsHook(void) {
    if (gYuQuickLaunchRecentsHooked) {
        return;
    }
    if (objc_getClass("LSApplicationWorkspace")) {
        %init(YuQuickLaunchRecents);
        gYuQuickLaunchRecentsHooked = YES;
    }
}

static void yu_quicklaunch_start(void) {
    yu_quicklaunch_installRecentsHook();
    [[YuQuickLaunchOverlay yu_quicklaunch_shared] yu_quicklaunch_install];
}

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        yu_quicklaunch_start();
    });
}

%end

%ctor {
    // The file declares an explicit group, so the default group needs manual init.
    %init;
    @autoreleasepool {
        // Warm the configuration snapshot; the overlay installs once SpringBoard is up.
        [YuQuickLaunchConfig yu_quicklaunch_shared];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            yu_quicklaunch_start();
        });
    }
}