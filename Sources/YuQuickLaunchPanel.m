#import "YuQuickLaunchPanel.h"
#import "YuQuickLaunchApps.h"
#import "YuQuickLaunchConfig.h"
#import "YuQuickLaunchPrivate.h"

#import <QuartzCore/QuartzCore.h>

static NSString * const YuQuickLaunchPanelCellIdentifier = @"YuQuickLaunchAppCell";
static NSString * const YuQuickLaunchPanelHeaderIdentifier = @"YuQuickLaunchSectionHeader";
static const CGFloat YuQuickLaunchPanelCornerRadius = 34.0;

static NSCache *yu_quicklaunch_iconCache(void) {
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 120;
    });
    return cache;
}

#pragma mark - Cell

@interface YuQuickLaunchAppCell : UICollectionViewCell
@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
- (void)yu_quicklaunch_configureWithApp:(YuQuickLaunchApp *)app dark:(BOOL)dark;
@end

@implementation YuQuickLaunchAppCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _bubbleView = [[UIView alloc] init];
        _bubbleView.layer.cornerRadius = 12.0;
        _bubbleView.layer.cornerCurve = kCACornerCurveContinuous;
        _bubbleView.userInteractionEnabled = NO;
        [self.contentView addSubview:_bubbleView];

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.layer.cornerRadius = 8.0;
        _iconView.layer.cornerCurve = kCACornerCurveContinuous;
        _iconView.layer.masksToBounds = YES;
        [self.contentView addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.numberOfLines = 1;
        [self.contentView addSubview:_titleLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.bubbleView.frame = self.contentView.bounds;
    CGFloat height = CGRectGetHeight(self.contentView.bounds);
    CGFloat iconSide = 30.0;
    self.iconView.frame = CGRectMake(10.0, (height - iconSide) / 2.0, iconSide, iconSide);
    CGFloat textX = CGRectGetMaxX(self.iconView.frame) + 9.0;
    self.titleLabel.frame = CGRectMake(textX, 0, CGRectGetWidth(self.contentView.bounds) - textX - 8.0, height);
}

- (void)yu_quicklaunch_configureWithApp:(YuQuickLaunchApp *)app dark:(BOOL)dark {
    self.titleLabel.text = app.name;
    self.titleLabel.textColor = dark ? [UIColor whiteColor] : [UIColor blackColor];
    self.bubbleView.backgroundColor = dark
        ? [UIColor colorWithWhite:1.0 alpha:0.09]
        : [UIColor colorWithWhite:0.0 alpha:0.05];

    UIImage *icon = app.icon ?: [yu_quicklaunch_iconCache() objectForKey:app.bundleID];
    if (!icon) {
        CGFloat scale = [UIScreen mainScreen].scale;
        icon = [UIImage _applicationIconImageForBundleIdentifier:app.bundleID format:0 scale:scale];
        if (!icon) {
            icon = [UIImage _applicationIconImageForBundleIdentifier:app.bundleID format:2 scale:scale];
        }
        if (!icon) {
            icon = [UIImage systemImageNamed:@"app.fill"];
        }
        if (icon) {
            app.icon = icon;
            [yu_quicklaunch_iconCache() setObject:icon forKey:app.bundleID];
        }
    }
    self.iconView.image = icon;
}

@end

#pragma mark - Section header

@interface YuQuickLaunchSectionHeader : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation YuQuickLaunchSectionHeader

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        [self addSubview:_titleLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.titleLabel.frame = CGRectMake(14.0, 2.0, CGRectGetWidth(self.bounds) - 28.0, 18.0);
}

@end

#pragma mark - Panel

@interface YuQuickLaunchPanelController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UITextFieldDelegate>
@property (nonatomic, strong) UIControl *dimControl;
@property (nonatomic, strong) UIView *sheetView;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *grabberView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray *sections;
@property (nonatomic, assign) CGFloat keyboardHeight;
@property (nonatomic, assign) BOOL dark;
@property (nonatomic, assign) NSInteger columns;
@property (nonatomic, assign) BOOL closing;
@end

@implementation YuQuickLaunchPanelController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    [self yu_quicklaunch_loadConfiguration];

    _dimControl = [[UIControl alloc] initWithFrame:self.view.bounds];
    _dimControl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dimControl.backgroundColor = [UIColor colorWithWhite:0.0 alpha:1.0];
    _dimControl.alpha = 0.0;
    [_dimControl addTarget:self action:@selector(yu_quicklaunch_dimTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_dimControl];

    _sheetView = [[UIView alloc] initWithFrame:CGRectZero];
    _sheetView.layer.cornerRadius = YuQuickLaunchPanelCornerRadius;
    _sheetView.layer.cornerCurve = kCACornerCurveContinuous;
    _sheetView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    _sheetView.layer.masksToBounds = YES;
    _sheetView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_sheetView];

    UIBlurEffectStyle blurStyle = self.dark ? UIBlurEffectStyleSystemMaterialDark : UIBlurEffectStyleSystemMaterialLight;
    _blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:blurStyle]];
    _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_sheetView addSubview:_blurView];

    UIView *content = _blurView.contentView;
    _grabberView = [[UIView alloc] initWithFrame:CGRectZero];
    _grabberView.layer.cornerRadius = 2.5;
    _grabberView.backgroundColor = self.dark
        ? [UIColor colorWithWhite:1.0 alpha:0.28]
        : [UIColor colorWithWhite:0.0 alpha:0.20];
    [content addSubview:_grabberView];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.text = @"快捷启动";
    _titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBold];
    _titleLabel.textColor = self.dark ? [UIColor whiteColor] : [UIColor blackColor];
    [content addSubview:_titleLabel];

    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    _closeButton.tintColor = self.dark ? [UIColor whiteColor] : [UIColor blackColor];
    _closeButton.backgroundColor = self.dark
        ? [UIColor colorWithWhite:1.0 alpha:0.10]
        : [UIColor colorWithWhite:0.0 alpha:0.06];
    _closeButton.layer.cornerRadius = 16.0;
    [_closeButton addTarget:self action:@selector(yu_quicklaunch_dimTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:_closeButton];

    _searchField = [[UITextField alloc] initWithFrame:CGRectZero];
    _searchField.placeholder = @"搜索应用";
    _searchField.borderStyle = UITextBorderStyleNone;
    _searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _searchField.returnKeyType = UIReturnKeySearch;
    _searchField.autocorrectionType = UITextAutocorrectionTypeNo;
    _searchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _searchField.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    _searchField.textColor = self.dark ? [UIColor whiteColor] : [UIColor blackColor];
    _searchField.backgroundColor = self.dark
        ? [UIColor colorWithWhite:1.0 alpha:0.10]
        : [UIColor colorWithWhite:0.0 alpha:0.06];
    _searchField.layer.cornerRadius = 12.0;
    _searchField.delegate = self;
    _searchField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 38)];
    _searchField.leftViewMode = UITextFieldViewModeAlways;
    [_searchField addTarget:self action:@selector(yu_quicklaunch_searchChanged) forControlEvents:UIControlEventEditingChanged];
    [content addSubview:_searchField];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 8.0;
    layout.minimumLineSpacing = 8.0;
    layout.sectionInset = UIEdgeInsetsMake(6.0, 12.0, 12.0, 12.0);
    layout.headerReferenceSize = CGSizeMake(0, 26);
    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.backgroundColor = [UIColor clearColor];
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    _collectionView.alwaysBounceVertical = YES;
    _collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _collectionView.indicatorStyle = self.dark ? UIScrollViewIndicatorStyleWhite : UIScrollViewIndicatorStyleBlack;
    [_collectionView registerClass:[YuQuickLaunchAppCell class] forCellWithReuseIdentifier:YuQuickLaunchPanelCellIdentifier];
    [_collectionView registerClass:[YuQuickLaunchSectionHeader class]
        forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
               withReuseIdentifier:YuQuickLaunchPanelHeaderIdentifier];
    [content addSubview:_collectionView];

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _emptyLabel.text = @"没有找到应用";
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    _emptyLabel.textColor = self.dark
        ? [UIColor colorWithWhite:1.0 alpha:0.55]
        : [UIColor colorWithWhite:0.0 alpha:0.45];
    _emptyLabel.hidden = YES;
    [content addSubview:_emptyLabel];

    [self yu_quicklaunch_rebuildSections];
}

- (void)yu_quicklaunch_loadConfiguration {
    YuQuickLaunchConfig *config = [YuQuickLaunchConfig yu_quicklaunch_shared];
    NSInteger appearance = [[config yu_quicklaunch_valueForKey:@"appearance" defaultValue:@(2)] integerValue];
    if (appearance == 0) {
        self.dark = NO;
    } else if (appearance == 1) {
        self.dark = YES;
    } else {
        self.dark = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    }
    NSInteger columns = [[config yu_quicklaunch_valueForKey:@"columns" defaultValue:@(2)] integerValue];
    self.columns = MAX(2, MIN(columns, 4));
}

- (void)yu_quicklaunch_applyTheme {
    UIBlurEffectStyle blurStyle = self.dark ? UIBlurEffectStyleSystemMaterialDark : UIBlurEffectStyleSystemMaterialLight;
    self.blurView.effect = [UIBlurEffect effectWithStyle:blurStyle];
    UIColor *labelColor = self.dark ? [UIColor whiteColor] : [UIColor blackColor];
    self.titleLabel.textColor = labelColor;
    self.closeButton.tintColor = labelColor;
    self.searchField.textColor = labelColor;
    self.searchField.backgroundColor = self.dark
        ? [UIColor colorWithWhite:1.0 alpha:0.10]
        : [UIColor colorWithWhite:0.0 alpha:0.06];
    self.closeButton.backgroundColor = self.dark
        ? [UIColor colorWithWhite:1.0 alpha:0.10]
        : [UIColor colorWithWhite:0.0 alpha:0.06];
    self.grabberView.backgroundColor = self.dark
        ? [UIColor colorWithWhite:1.0 alpha:0.28]
        : [UIColor colorWithWhite:0.0 alpha:0.20];
    self.collectionView.indicatorStyle = self.dark ? UIScrollViewIndicatorStyleWhite : UIScrollViewIndicatorStyleBlack;
    self.emptyLabel.textColor = self.dark
        ? [UIColor colorWithWhite:1.0 alpha:0.55]
        : [UIColor colorWithWhite:0.0 alpha:0.45];
}

- (void)yu_quicklaunch_prepareForPresentation {
    [self yu_quicklaunch_loadConfiguration];
    [self yu_quicklaunch_applyTheme];
    [self yu_quicklaunch_rebuildSections];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yu_quicklaunch_keyboardWillChange:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yu_quicklaunch_keyboardWillChange:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)yu_quicklaunch_keyboardWillChange:(NSNotification *)note {
    BOOL showing = [note.name isEqualToString:UIKeyboardWillShowNotification];
    CGFloat height = 0.0;
    if (showing) {
        CGRect frame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
        height = CGRectGetHeight(frame);
    }
    NSTimeInterval duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    self.keyboardHeight = height;
    [UIView animateWithDuration:duration > 0 ? duration : 0.25 animations:^{
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGRect bounds = self.view.bounds;
    self.dimControl.frame = bounds;

    CGFloat availableHeight = bounds.size.height - self.keyboardHeight;
    CGFloat sheetHeight = CGRectGetHeight(bounds) * 0.66;
    if (self.keyboardHeight > 0) {
        sheetHeight = availableHeight - 24.0;
    }
    sheetHeight = MIN(sheetHeight, CGRectGetHeight(bounds) - 60.0);
    sheetHeight = MAX(sheetHeight, 280.0);

    CGRect sheetFrame = CGRectMake(6.0, availableHeight - sheetHeight, CGRectGetWidth(bounds) - 12.0, sheetHeight);
    if (self.closing) {
        sheetFrame = self.sheetView.frame;
    }
    self.sheetView.frame = sheetFrame;

    CGFloat width = CGRectGetWidth(sheetFrame);
    self.grabberView.frame = CGRectMake((width - 36.0) / 2.0, 8.0, 36.0, 5.0);
    self.titleLabel.frame = CGRectMake(18.0, 20.0, width - 90.0, 26.0);
    self.closeButton.frame = CGRectMake(width - 46.0, 16.0, 32.0, 32.0);
    self.searchField.frame = CGRectMake(14.0, 58.0, width - 28.0, 38.0);
    self.collectionView.frame = CGRectMake(0, 104.0, width, MAX(64.0, sheetHeight - 110.0));
    self.emptyLabel.frame = self.collectionView.frame;
}

#pragma mark - Data

- (void)yu_quicklaunch_rebuildSections {
    YuQuickLaunchConfig *config = [YuQuickLaunchConfig yu_quicklaunch_shared];
    BOOL showRecents = [[config yu_quicklaunch_valueForKey:@"showRecents" defaultValue:@(YES)] boolValue];
    NSArray *pinnedIDs = [config yu_quicklaunch_valueForKey:@"pinnedApplications" defaultValue:@[]];
    if (![pinnedIDs isKindOfClass:[NSArray class]]) {
        pinnedIDs = @[];
    }

    NSArray<YuQuickLaunchApp *> *allApps = [YuQuickLaunchApps yu_quicklaunch_userApps];
    NSString *query = [self.searchField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *sections = [NSMutableArray array];

    if (query.length > 0) {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(YuQuickLaunchApp *app, NSDictionary *bindings) {
            return [app.name localizedCaseInsensitiveContainsString:query]
                || [app.bundleID localizedCaseInsensitiveContainsString:query];
        }];
        NSArray *matches = [allApps filteredArrayUsingPredicate:predicate];
        if (matches.count > 0) {
            [sections addObject:@{@"title": @"搜索结果", @"apps": matches}];
        }
    } else {
        if (showRecents) {
            NSArray<YuQuickLaunchApp *> *recents = [YuQuickLaunchApps yu_quicklaunch_appsForBundleIDs:[YuQuickLaunchApps yu_quicklaunch_recentBundleIDs]];
            if (recents.count > 0) {
                [sections addObject:@{@"title": @"最近使用", @"apps": recents}];
            }
        }
        NSArray<YuQuickLaunchApp *> *pinned = [YuQuickLaunchApps yu_quicklaunch_appsForBundleIDs:pinnedIDs];
        if (pinned.count > 0) {
            [sections addObject:@{@"title": @"已固定", @"apps": pinned}];
        }
        if (allApps.count > 0) {
            [sections addObject:@{@"title": @"全部应用", @"apps": allApps}];
        }
    }

    self.sections = sections;
    self.emptyLabel.hidden = sections.count > 0;
    [self.collectionView reloadData];
}

#pragma mark - UICollectionView

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self.sections[section][@"apps"] count];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    YuQuickLaunchAppCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:YuQuickLaunchPanelCellIdentifier
                                                                         forIndexPath:indexPath];
    YuQuickLaunchApp *app = self.sections[indexPath.section][@"apps"][indexPath.item];
    [cell yu_quicklaunch_configureWithApp:app dark:self.dark];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    YuQuickLaunchSectionHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
        withReuseIdentifier:YuQuickLaunchPanelHeaderIdentifier forIndexPath:indexPath];
    header.titleLabel.text = self.sections[indexPath.section][@"title"];
    header.titleLabel.textColor = self.dark
        ? [UIColor colorWithWhite:1.0 alpha:0.55]
        : [UIColor colorWithWhite:0.0 alpha:0.50];
    return header;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = CGRectGetWidth(collectionView.bounds);
    UIEdgeInsets inset = ((UICollectionViewFlowLayout *)collectionViewLayout).sectionInset;
    CGFloat spacing = 8.0;
    NSInteger columns = MAX(2, self.columns);
    CGFloat itemWidth = (width - inset.left - inset.right - spacing * (columns - 1)) / columns;
    return CGSizeMake(floor(itemWidth), 50.0);
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                    layout:(UICollectionViewLayout *)collectionViewLayout
referenceSizeForHeaderInSection:(NSInteger)section {
    return CGSizeMake(CGRectGetWidth(collectionView.bounds), 26.0);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    YuQuickLaunchApp *app = self.sections[indexPath.section][@"apps"][indexPath.item];
    [self.delegate yu_quicklaunch_panelDidLaunchBundleID:app.bundleID];
    [self.delegate yu_quicklaunch_panelDidRequestDismiss:self];
}

#pragma mark - Search

- (void)yu_quicklaunch_searchChanged {
    [self yu_quicklaunch_rebuildSections];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Actions

- (void)yu_quicklaunch_dimTapped {
    if (self.closing) {
        return;
    }
    [self.searchField resignFirstResponder];
    [self.delegate yu_quicklaunch_panelDidRequestDismiss:self];
}

#pragma mark - Animation

- (void)yu_quicklaunch_animateInWithCompletion:(void (^)(void))completion {
    [self.view layoutIfNeeded];
    CGRect frame = self.sheetView.frame;
    self.sheetView.transform = CGAffineTransformMakeTranslation(0, CGRectGetHeight(frame) + 40.0);
    self.dimControl.alpha = 0.0;

    [UIView animateWithDuration:0.42
                          delay:0.0
         usingSpringWithDamping:0.86
          initialSpringVelocity:0.4
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.sheetView.transform = CGAffineTransformIdentity;
        self.dimControl.alpha = 0.32;
    } completion:^(BOOL finished) {
        if (completion) {
            completion();
        }
    }];
}

- (void)yu_quicklaunch_animateOutWithCompletion:(void (^)(void))completion {
    self.closing = YES;
    CGRect frame = self.sheetView.frame;
    [UIView animateWithDuration:0.24
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.sheetView.transform = CGAffineTransformMakeTranslation(0, CGRectGetHeight(frame) + 40.0);
        self.dimControl.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.sheetView.transform = CGAffineTransformIdentity;
        if (completion) {
            completion();
        }
    }];
}

@end
