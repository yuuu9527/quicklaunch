#pragma once

#import <UIKit/UIKit.h>

@interface YuQuickLaunchOverlay : NSObject

+ (instancetype)yu_quicklaunch_shared;
/// Installs the trigger window if the tweak is enabled, otherwise removes it.
- (void)yu_quicklaunch_install;
- (void)yu_quicklaunch_uninstall;
/// Re-reads the preferences and updates the trigger without tearing the window down.
- (void)yu_quicklaunch_reconfigure;

@end
