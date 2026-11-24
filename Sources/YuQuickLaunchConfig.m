#import "YuQuickLaunchConfig.h"
#import "YuQuickLaunchPreferences.h"

@interface YuQuickLaunchConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void yu_quicklaunch_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object, CFDictionaryRef info) {
    YuQuickLaunchConfig *config = (__bridge YuQuickLaunchConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config yu_quicklaunch_reload];
    });
}

@implementation YuQuickLaunchConfig

+ (instancetype)yu_quicklaunch_shared {
    static YuQuickLaunchConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.yu.quicklaunch.preferences", DISPATCH_QUEUE_SERIAL);
        [self yu_quicklaunch_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, yu_quicklaunch_preferencesDidChange,
            (__bridge CFStringRef)YuQuickLaunchPreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self yu_quicklaunch_reload]; });
    }
    return self;
}

- (void)yu_quicklaunch_reload {
    self.snapshot = yu_quicklaunch_readPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:YuQuickLaunchPreferencesChanged object:self];
    });
}

- (id)yu_quicklaunch_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    return self.snapshot[key] ?: defaultValue;
}

- (BOOL)yu_quicklaunch_isEnabled {
    id value = [self yu_quicklaunch_valueForKey:@"enabled" defaultValue:@(NO)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
