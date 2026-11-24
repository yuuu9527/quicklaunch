#import "YuQuickLaunchApps.h"
#import "YuQuickLaunchPrivate.h"
#import <objc/message.h>

static NSString * const YuQuickLaunchRecentsSuite = @"com.yu.quicklaunch.recents";
static NSString * const YuQuickLaunchRecentsKey = @"recents";
static const NSUInteger YuQuickLaunchRecentsLimit = 8;
static const NSTimeInterval YuQuickLaunchAppCacheLifetime = 60.0;

@implementation YuQuickLaunchApp
@end

static NSArray<YuQuickLaunchApp *> *gYuQuickLaunchAppCache;
static NSTimeInterval gYuQuickLaunchAppCacheTime;

static BOOL yu_quicklaunch_proxyFlag(LSApplicationProxy *proxy, SEL selector, BOOL fallback) {
    if (![proxy respondsToSelector:selector]) {
        return fallback;
    }
    BOOL (*send)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
    return send(proxy, selector);
}

static LSApplicationProxy *yu_quicklaunch_proxyForBundleID(NSString *bundleID) {
    if (bundleID.length == 0) {
        return nil;
    }
    LSApplicationWorkspace *workspace = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
    if ([workspace respondsToSelector:@selector(applicationForBundleIdentifier:)]) {
        id (*send)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
        return send(workspace, @selector(applicationForBundleIdentifier:), bundleID);
    }
    for (LSApplicationProxy *proxy in [workspace allApplications]) {
        if ([[proxy bundleIdentifier] isEqualToString:bundleID]) {
            return proxy;
        }
    }
    return nil;
}

@implementation YuQuickLaunchApps

+ (NSArray<YuQuickLaunchApp *> *)yu_quicklaunch_userApps {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (gYuQuickLaunchAppCache && now - gYuQuickLaunchAppCacheTime < YuQuickLaunchAppCacheLifetime) {
        return gYuQuickLaunchAppCache;
    }

    LSApplicationWorkspace *workspace = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
    NSArray *proxies = [workspace allApplications];
    NSMutableArray<YuQuickLaunchApp *> *apps = [NSMutableArray arrayWithCapacity:proxies.count];
    for (LSApplicationProxy *proxy in proxies) {
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        if (proxyClass && ![proxy isKindOfClass:proxyClass]) {
            continue;
        }
        NSString *bundleID = [proxy bundleIdentifier];
        if (bundleID.length == 0 || [bundleID hasPrefix:@"com.apple."]) {
            continue;
        }
        if (!yu_quicklaunch_proxyFlag(proxy, @selector(isInstalled), YES)) {
            continue;
        }
        if (yu_quicklaunch_proxyFlag(proxy, @selector(isSystemApplication), NO)) {
            continue;
        }
        if (yu_quicklaunch_proxyFlag(proxy, @selector(isHidden), NO)) {
            continue;
        }
        if (yu_quicklaunch_proxyFlag(proxy, @selector(isLaunchProhibited), NO)) {
            continue;
        }
        NSString *name = nil;
        if ([proxy respondsToSelector:@selector(localizedName)]) {
            name = [proxy localizedName];
        }
        if (name.length == 0) {
            name = bundleID;
        }
        YuQuickLaunchApp *app = [[YuQuickLaunchApp alloc] init];
        app.bundleID = bundleID;
        app.name = name;
        [apps addObject:app];
    }

    [apps sortUsingComparator:^NSComparisonResult(YuQuickLaunchApp *lhs, YuQuickLaunchApp *rhs) {
        return [lhs.name localizedCaseInsensitiveCompare:rhs.name];
    }];

    gYuQuickLaunchAppCache = [apps copy];
    gYuQuickLaunchAppCacheTime = now;
    return gYuQuickLaunchAppCache;
}

+ (NSArray<YuQuickLaunchApp *> *)yu_quicklaunch_appsForBundleIDs:(NSArray *)bundleIDs {
    NSMutableArray<YuQuickLaunchApp *> *apps = [NSMutableArray array];
    NSArray<YuQuickLaunchApp *> *known = [self yu_quicklaunch_userApps];
    for (id value in bundleIDs) {
        if (![value isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *bundleID = value;
        YuQuickLaunchApp *match = nil;
        for (YuQuickLaunchApp *app in known) {
            if ([app.bundleID isEqualToString:bundleID]) {
                match = app;
                break;
            }
        }
        if (!match) {
            LSApplicationProxy *proxy = yu_quicklaunch_proxyForBundleID(bundleID);
            NSString *name = [proxy localizedName];
            if (name.length == 0) {
                continue;
            }
            match = [[YuQuickLaunchApp alloc] init];
            match.bundleID = bundleID;
            match.name = name;
        }
        [apps addObject:match];
    }
    return apps;
}

+ (void)yu_quicklaunch_launchBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) {
        return;
    }
    LSApplicationWorkspace *workspace = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
    [workspace openApplicationWithBundleID:bundleID];
    [self yu_quicklaunch_recordRecentBundleID:bundleID];
}

+ (NSArray<NSString *> *)yu_quicklaunch_recentBundleIDs {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:YuQuickLaunchRecentsSuite];
    NSArray *stored = [defaults arrayForKey:YuQuickLaunchRecentsKey];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (id value in stored) {
        if ([value isKindOfClass:[NSString class]] && [result containsObject:value] == NO) {
            [result addObject:value];
        }
    }
    return result;
}

+ (void)yu_quicklaunch_recordRecentBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) {
        return;
    }
    NSMutableArray<NSString *> *recents = [[self yu_quicklaunch_recentBundleIDs] mutableCopy];
    [recents removeObject:bundleID];
    [recents insertObject:bundleID atIndex:0];
    while (recents.count > YuQuickLaunchRecentsLimit) {
        [recents removeLastObject];
    }
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:YuQuickLaunchRecentsSuite];
    [defaults setObject:recents forKey:YuQuickLaunchRecentsKey];
    [defaults synchronize];
}

@end
