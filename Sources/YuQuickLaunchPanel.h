#pragma once

#import <UIKit/UIKit.h>

@class YuQuickLaunchPanelController;

@protocol YuQuickLaunchPanelControllerDelegate <NSObject>
- (void)yu_quicklaunch_panelDidRequestDismiss:(YuQuickLaunchPanelController *)panel;
- (void)yu_quicklaunch_panelDidLaunchBundleID:(NSString *)bundleID;
@end

@interface YuQuickLaunchPanelController : UIViewController

@property (nonatomic, weak) id<YuQuickLaunchPanelControllerDelegate> delegate;

- (void)yu_quicklaunch_prepareForPresentation;
- (void)yu_quicklaunch_animateInWithCompletion:(void (^)(void))completion;
- (void)yu_quicklaunch_animateOutWithCompletion:(void (^)(void))completion;

@end
