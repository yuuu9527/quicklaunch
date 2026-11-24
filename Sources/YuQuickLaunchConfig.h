#pragma once

#import <Foundation/Foundation.h>

@interface YuQuickLaunchConfig : NSObject
+ (instancetype)yu_quicklaunch_shared;
- (BOOL)yu_quicklaunch_isEnabled;
- (id)yu_quicklaunch_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (void)yu_quicklaunch_reload;
@end
