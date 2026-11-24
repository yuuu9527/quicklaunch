#pragma once

#import <UIKit/UIKit.h>

@interface YuQuickLaunchApp : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) UIImage *icon;
@end

@interface YuQuickLaunchApps : NSObject

/// Installed user applications, sorted by localized name. Cached for a short while.
+ (NSArray<YuQuickLaunchApp *> *)yu_quicklaunch_userApps;
/// Resolves bundle identifiers to app models, skipping ones that are gone.
+ (NSArray<YuQuickLaunchApp *> *)yu_quicklaunch_appsForBundleIDs:(NSArray *)bundleIDs;
/// Launches an app and records it in the recent list.
+ (void)yu_quicklaunch_launchBundleID:(NSString *)bundleID;
/// Recently launched bundle identifiers, most recent first.
+ (NSArray<NSString *> *)yu_quicklaunch_recentBundleIDs;
+ (void)yu_quicklaunch_recordRecentBundleID:(NSString *)bundleID;

@end
