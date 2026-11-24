#import "YuQuickLaunchAppPickerController.h"
#import "YuQuickLaunchPreferences.h"
#import "../Headers/YuQuickLaunchPrivate.h"

#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

static NSString * const YuQuickLaunchPinnedKey = @"pinnedApplications";

@interface YuQuickLaunchAppPickerController ()
@property (nonatomic, strong) NSMutableArray<NSString *> *yu_quicklaunch_pinned;
@property (nonatomic, strong) NSArray *yu_quicklaunch_apps;
@end

@implementation YuQuickLaunchAppPickerController

#pragma mark - Data

- (Class)yu_quicklaunch_workspaceClass {
    Class cls = NSClassFromString(@"LSApplicationWorkspace");
    if (cls) {
        return cls;
    }
    const char *paths[] = {
        "/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
        "/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices",
        "/System/Library/Frameworks/CoreServices.framework/CoreServices",
    };
    for (size_t index = 0; index < sizeof(paths) / sizeof(paths[0]) && !cls; index++) {
        void *handle = dlopen(paths[index], RTLD_LAZY);
        (void)handle;
        cls = NSClassFromString(@"LSApplicationWorkspace");
    }
    return cls;
}

- (UIImage *)yu_quicklaunch_iconForBundleID:(NSString *)bundleID {
    CGFloat scale = [UIScreen mainScreen].scale;
    UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:scale];
    if (!icon) {
        icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:2 scale:scale];
    }
    return icon;
}

- (void)yu_quicklaunch_loadApps {
    NSArray *stored = yu_quicklaunch_readPreferences()[YuQuickLaunchPinnedKey];
    self.yu_quicklaunch_pinned = [NSMutableArray array];
    if ([stored isKindOfClass:[NSArray class]]) {
        for (id value in stored) {
            if ([value isKindOfClass:[NSString class]]) {
                [self.yu_quicklaunch_pinned addObject:value];
            }
        }
    }

    Class workspaceClass = [self yu_quicklaunch_workspaceClass];
    NSMutableArray *apps = [NSMutableArray array];
    if (workspaceClass) {
        id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
        NSArray *proxies = [workspace performSelector:@selector(allApplications)];
        for (LSApplicationProxy *proxy in proxies) {
            Class proxyClass = NSClassFromString(@"LSApplicationProxy");
            if (proxyClass && ![proxy isKindOfClass:proxyClass]) {
                continue;
            }
            NSString *bundleID = [proxy bundleIdentifier];
            if (bundleID.length == 0 || [bundleID hasPrefix:@"com.apple."]) {
                continue;
            }
            if ([proxy respondsToSelector:@selector(isInstalled)] && ![proxy isInstalled]) {
                continue;
            }
            if ([proxy respondsToSelector:@selector(isSystemApplication)] && [proxy isSystemApplication]) {
                continue;
            }
            NSString *name = [proxy respondsToSelector:@selector(localizedName)] ? [proxy localizedName] : nil;
            if (name.length == 0) {
                name = bundleID;
            }
            [apps addObject:@{@"bundleID": bundleID, @"name": name}];
        }
    }
    [apps sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        return [lhs[@"name"] localizedCaseInsensitiveCompare:rhs[@"name"]];
    }];
    self.yu_quicklaunch_apps = apps;
}

#pragma mark - Specifiers

- (NSArray *)specifiers {
    if (!_specifiers) {
        [self yu_quicklaunch_loadApps];
        NSMutableArray *items = [NSMutableArray array];

        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"已固定应用"];
        [group setProperty:@"点按应用即可固定到触发面板顶部的“已固定”分组，再次点按取消。"
                    forKey:@"footerText"];
        [items addObject:group];

        if (self.yu_quicklaunch_apps.count == 0) {
            PSSpecifier *empty = [PSSpecifier groupSpecifierWithName:nil];
            [empty setProperty:@"未能读取已安装应用列表。" forKey:@"footerText"];
            [items addObject:empty];
        }

        for (NSDictionary *app in self.yu_quicklaunch_apps) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:app[@"name"]
                                                               target:self
                                                                  set:nil
                                                                  get:nil
                                                               detail:nil
                                                                 cell:PSButtonCell
                                                                 edit:nil];
            [spec setProperty:@(NSTextAlignmentLeft) forKey:@"alignment"];
            [spec setProperty:app[@"bundleID"] forKey:@"yu_quicklaunch_bundleID"];
            [spec setButtonAction:@selector(yu_quicklaunch_toggleApp:)];
            [items addObject:spec];
        }

        PSSpecifier *clearGroup = [PSSpecifier groupSpecifierWithName:nil];
        [items addObject:clearGroup];
        PSSpecifier *clear = [PSSpecifier preferenceSpecifierNamed:@"清除全部固定"
                                                            target:self
                                                               set:nil
                                                               get:nil
                                                            detail:nil
                                                              cell:PSButtonCell
                                                              edit:nil];
        [clear setButtonAction:@selector(yu_quicklaunch_clearPinned)];
        [items addObject:clear];

        _specifiers = items;
    }
    return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = [self specifierAtIndex:[self indexForIndexPath:indexPath]];
    NSString *bundleID = [spec propertyForKey:@"yu_quicklaunch_bundleID"];
    if (bundleID.length > 0) {
        cell.accessoryType = [self.yu_quicklaunch_pinned containsObject:bundleID]
            ? UITableViewCellAccessoryCheckmark
            : UITableViewCellAccessoryNone;
        UIImage *icon = [self yu_quicklaunch_iconForBundleID:bundleID];
        if (icon) {
            cell.imageView.image = icon;
        }
    }
    return cell;
}

#pragma mark - Actions

- (void)yu_quicklaunch_toggleApp:(PSSpecifier *)specifier {
    NSString *bundleID = [specifier propertyForKey:@"yu_quicklaunch_bundleID"];
    if (bundleID.length == 0) {
        return;
    }
    if ([self.yu_quicklaunch_pinned containsObject:bundleID]) {
        [self.yu_quicklaunch_pinned removeObject:bundleID];
    } else {
        [self.yu_quicklaunch_pinned addObject:bundleID];
    }
    [self yu_quicklaunch_savePinned];
    [self reloadSpecifier:specifier animated:YES];
}

- (void)yu_quicklaunch_clearPinned {
    [self.yu_quicklaunch_pinned removeAllObjects];
    [self yu_quicklaunch_savePinned];
    [self reloadSpecifiers];
}

- (void)yu_quicklaunch_savePinned {
    NSError *error = nil;
    if (!yu_quicklaunch_writePreference(YuQuickLaunchPinnedKey, [self.yu_quicklaunch_pinned copy], &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存"
            message:error.localizedDescription ?: @"请检查配置文件路径和写入权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end