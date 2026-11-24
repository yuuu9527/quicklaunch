#pragma once

#import <UIKit/UIKit.h>

// Only the private interfaces this tweak actually uses are declared here.

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *applicationIdentifier;
- (BOOL)isInstalled;
- (BOOL)isSystemApplication;
- (BOOL)isLaunchProhibited;
- (BOOL)isHidden;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allApplications;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

@interface UIImage (YuQuickLaunchIcons)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleID
                                              format:(int)format
                                               scale:(CGFloat)scale;
@end
