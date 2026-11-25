#import "TDApplicationListViewController.h"
#import "TDAlternateIconViewController.h"
#import "Decryption/TDDecryptionTask.h"
#import "Localize.h"
#import "TDAppStoreLink.h"

#import "Extensions/UIImage+Private.h"
#import "Extensions/LSBundleProxy+TrollDecrypt.h"
#import "TDFileManagerViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import "Extensions/LSApplicationProxy+AltList.h"
#import "Extensions/LSApplicationProxy+AppState.h"

static inline NSUInteger getEffectiveIconFormat(void) {
    return (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) ? 8 : 10;
}

@implementation TDApplicationListViewController {
    NSArray *_allAvailableApplications;
    NSArray *_filteredApplications;
    UISearchController *_searchController;

    UIImage *_placeholderIcon;
    NSMutableDictionary *_iconCache;
    UIAlertController *_progressAlert;

    // 上一次处理过的链接原文：同一条不重复解析
    NSString *_lastHandledLink;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _iconCache = [NSMutableDictionary new];
        _placeholderIcon = [UIImage _applicationIconImageForBundleIdentifier:@"com.apple.WebSheet" format:getEffectiveIconFormat() scale:[UIScreen mainScreen].scale];
        [[LSApplicationWorkspace defaultWorkspace] addObserver:self];

        [self loadAvailableApplications];
    }
    return self;
}

- (void)dealloc {
	[[LSApplicationWorkspace defaultWorkspace] removeObserver:self];
}

- (void)applicationsDidInstall:(NSArray <LSApplicationProxy *> *)apps {
	[self refresh];
}

- (void)applicationsDidUninstall:(NSArray <LSApplicationProxy *> *)apps {
	[self refresh];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self _configureToolbarItems];
    [self _configureSearchController];
}

- (void)_configureToolbarItems {
    UIBarButtonItem *manualBundleIdentifierButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"keyboard"] style:UIBarButtonItemStylePlain target:self action:@selector(_manualBundleIdentifierButtonTapped)];
    UIBarButtonItem *appStoreLinkButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"link"] style:UIBarButtonItemStylePlain target:self action:@selector(_appStoreLinkButtonTapped)];
    self.navigationItem.rightBarButtonItems = @[ manualBundleIdentifierButton, appStoreLinkButton ];

    if ([UIApplication sharedApplication].supportsAlternateIcons) {
        UIBarButtonItem *alternateIconButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"paintbrush.fill"] style:UIBarButtonItemStylePlain target:self action:@selector(_alternateIconButtonTapped)];
        self.navigationItem.leftBarButtonItem = alternateIconButton;
    }
}

- (void)_configureSearchController {
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.placeholder = [Localize localizedStringForKey:@"SEARCH_APPLICATIONS"];
    _searchController.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _searchController.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;

    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)_manualBundleIdentifierButtonTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[Localize localizedStringForKey:@"MANUAL_ENTRY_TITLE"] message:[Localize localizedStringForKey:@"MANUAL_ENTRY_SUBTITLE"] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"com.example.app";
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[Localize localizedStringForKey:@"CANCEL"] style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *decryptAction = [UIAlertAction actionWithTitle:[Localize localizedStringForKey:@"DECRYPT"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *bundleIdentifier = alert.textFields.firstObject.text;
        LSApplicationProxy *application = [LSApplicationProxy applicationProxyForIdentifier:bundleIdentifier];

        if (!application.bundleURL) {
            UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:[Localize localizedStringForKey:@"ERROR"] message:@"No application found with the specified bundle identifier." preferredStyle:UIAlertControllerStyleAlert];
            [errorAlert addAction:[UIAlertAction actionWithTitle:[Localize localizedStringForKey:@"OK"] style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:errorAlert animated:YES completion:nil];
            return;
        }

        [self _decryptApplicationProxy:application];
    }];
    [alert addAction:cancelAction];
    [alert addAction:decryptAction];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - App Store 链接

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self _checkClipboardForLink];
}

// 复制了 App Store 链接就自动接住；同一条链接不重复处理
- (void)_checkClipboardForLink {
    if (_progressAlert) {
        return;
    }
    NSString *clipboard = [UIPasteboard generalPasteboard].string;
    if (clipboard.length == 0) {
        return;
    }
    NSNumber *trackId = [TDAppStoreLink trackIdFromString:clipboard];
    if (!trackId) {
        return;
    }
    if (_lastHandledLink.length > 0 && [clipboard isEqualToString:_lastHandledLink]) {
        return;
    }
    _lastHandledLink = [clipboard copy];
    [self _lookupAndDecryptTrackId:trackId];
}

- (void)_appStoreLinkButtonTapped {
    NSString *clipboard = [UIPasteboard generalPasteboard].string ?: @"";
    NSNumber *clipboardTrackId = [TDAppStoreLink trackIdFromString:clipboard];
    if (clipboardTrackId && ![_lastHandledLink isEqualToString:clipboard]) {
        _lastHandledLink = [clipboard copy];
        [self _lookupAndDecryptTrackId:clipboardTrackId];
        return;
    }

    NSString *message = _lastHandledLink.length > 0
        ? @"剪贴板里还是上次那条链接。换一个 App 就复制新链接，也可以直接输入数字 ID。"
        : @"粘贴 apps.apple.com 的应用链接，或者直接输入数字 ID。";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"App Store 链接"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"https://apps.apple.com/cn/app/id123456789";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"砸壳" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text ?: @"";
        NSNumber *trackId = [TDAppStoreLink trackIdFromString:text];
        if (!trackId) {
            [weakSelf _presentSimpleAlert:@"解析失败" message:@"没找到 /id 后面的数字"];
            return;
        }
        if (weakSelf) { weakSelf->_lastHandledLink = [text copy]; }
        [weakSelf _lookupAndDecryptTrackId:trackId];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)_lookupAndDecryptTrackId:(NSNumber *)trackId {
    __weak typeof(self) weakSelf = self;
    [TDAppStoreLink lookupTrackId:trackId completion:^(NSDictionary *info, NSError *error) {
        if (!info) {
            [weakSelf _presentSimpleAlert:@"查询失败"
                                  message:(error.localizedDescription ?: @"App Store 没返回这个 ID 的信息")];
            return;
        }
        LSApplicationProxy *application =
            [weakSelf _installedApplicationForBundleIdentifier:info[@"bundleId"]];
        if (!application) {
            [weakSelf _askToInstall:info];
            return;
        }
        [weakSelf _decryptApplicationProxy:application];
    }];
}

- (LSApplicationProxy *)_installedApplicationForBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) {
        return nil;
    }
    for (LSApplicationProxy *proxy in _allAvailableApplications) {
        if ([[proxy atl_bundleIdentifier] caseInsensitiveCompare:bundleIdentifier] == NSOrderedSame) {
            return proxy;
        }
    }
    // 列表可能是旧的，直接查一次并顺手刷新
    LSApplicationProxy *application = [LSApplicationProxy applicationProxyForIdentifier:bundleIdentifier];
    if (application.bundleURL) {
        [self loadAvailableApplications];
        [self.tableView reloadData];
        return application;
    }
    return nil;
}

- (void)_askToInstall:(NSDictionary *)info {
    NSString *message = [NSString stringWithFormat:
        @"%@\n%@ · %@\n\n设备上没装这个 App，没东西可砸。去 App Store 装好，回来重新复制一次链接就行。",
        info[@"bundleId"], info[@"trackName"], info[@"version"]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"还没安装"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"去 App Store" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [TDAppStoreLink openTrackId:info[@"trackId"]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    [weakSelf presentViewController:alert animated:YES completion:nil];
}

- (void)_presentSimpleAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)_alternateIconButtonTapped {
    // present modally
    TDAlternateIconViewController *iconVC = [[TDAlternateIconViewController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:iconVC];
    [self presentViewController:navController animated:YES completion:nil];
}


- (void)refresh {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self loadAvailableApplications];
        
        [self.tableView reloadData];
    });
}

- (void)loadAvailableApplications {
    NSMutableArray *apps = [NSMutableArray array];

    NSArray <LSApplicationProxy *> *allInstalledApps = [[LSApplicationWorkspace defaultWorkspace] atl_allInstalledApplications];
    [allInstalledApps enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(LSApplicationProxy *proxy, NSUInteger idx, BOOL *stop) {
        _LSApplicationState *state = proxy.appState;
        
        bool shouldSkip = (![proxy atl_isUserApplication] ||
            ![proxy atl_bundleIdentifier] ||
            ![proxy atl_nameToDisplay] ||
            ![proxy atl_shortVersionString] ||
            ![proxy bundleURL] ||
            !state.isInstalled ||
            state.isPlaceholder);

        if (shouldSkip) return;

        [apps addObject:proxy];
    }];

    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"atl_nameToDisplay" ascending:YES];
    _allAvailableApplications = [apps sortedArrayUsingDescriptors:@[sortDescriptor]];

    [self _applySearchFilter];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_filteredApplications count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DecryptionAppCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DecryptionAppCell"];

    LSApplicationProxy *application = _filteredApplications[indexPath.row];

    cell.textLabel.text = [application atl_nameToDisplay];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", [application atl_shortVersionString], [application atl_bundleIdentifier]];
    
    if ([_iconCache objectForKey:[application atl_bundleIdentifier]]) {
        cell.imageView.image = [_iconCache objectForKey:[application atl_bundleIdentifier]];
        return cell;
    }

    cell.imageView.image = _placeholderIcon;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:[application atl_bundleIdentifier] format:getEffectiveIconFormat() scale:[UIScreen mainScreen].scale];
        if (icon) {
            [_iconCache setObject:icon forKey:[application atl_bundleIdentifier]];
            dispatch_async(dispatch_get_main_queue(), ^{
                UITableViewCell *updateCell = [tableView cellForRowAtIndexPath:indexPath];
                if (updateCell) {
                    updateCell.imageView.image = icon;
                    [updateCell setNeedsLayout];
                }
            });
        }
    });

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 80.0f;
}

// TDDecryptionTask
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    LSApplicationProxy *application = _filteredApplications[indexPath.row];

    NSString *title = [Localize localizedStringForKey:@"DECRYPT"];
    NSString *subtitle = [NSString stringWithFormat:[Localize localizedStringForKey:@"DECRYPTION_PROMPT"], [application atl_nameToDisplay]];
    // UIAlertController *alert = [UIAlertController alertControllerWithTitle:[Localize localizedStringForKey:@"DECRYPT"] message:[NSString stringWithFormat:@"Do you want to decrypt %@?", [application atl_nameToDisplay]] preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:subtitle preferredStyle:UIAlertControllerStyleActionSheet];


    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[Localize localizedStringForKey:@"CANCEL"] style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:cancelAction];

    UIAlertAction *decryptBinaryOnlyAction = [UIAlertAction actionWithTitle:[Localize localizedStringForKey:@"MAIN_BINARY_ONLY"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        TDDecryptionTaskOptions options = TDDecryptionTaskOptionsMake(true);
        [self _decryptApplicationProxy:application options:options];
    }];
    [alert addAction:decryptBinaryOnlyAction];

    UIAlertAction *decryptAction = [UIAlertAction actionWithTitle:[Localize localizedStringForKey:@"FULL_IPA"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self _decryptApplicationProxy:application];
    }];
    [alert addAction:decryptAction];

    // iPad popover fix - @NightwindDev
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.view;
        popover.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }

    [self presentViewController:alert animated:YES completion:nil];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)_decryptApplicationProxy:(LSApplicationProxy *)application {
    [self _decryptApplicationProxy:application options:TDDecryptionTaskDefaultOptions()];
}

- (void)_decryptApplicationProxy:(LSApplicationProxy *)application options:(TDDecryptionTaskOptions)options {
    NSLog(@"Starting decryption for %@", [application atl_bundleIdentifier]);
    TDDecryptionTask *decryptionTask = [[TDDecryptionTask alloc] initWithApplicationProxy:application];
    decryptionTask.progressHandler = ^(NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_progressAlert) {
                self->_progressAlert.message = message;
                return;
            }

            self->_progressAlert =
                [UIAlertController alertControllerWithTitle:[Localize localizedStringForKey:@"DECRYPTING"]
                                                    message:message
                                            preferredStyle:UIAlertControllerStyleAlert];
            [self presentViewController:self->_progressAlert animated:YES completion:nil];
        });
    };


    [decryptionTask executeWithCompletionHandler:^(BOOL success, NSURL *outputURL, NSError *error) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (_progressAlert) {
                [_progressAlert dismissViewControllerAnimated:YES completion:^{
                    _progressAlert = nil;
                }];
            }

            UIAlertController *resultAlert;
            if (success) {
                resultAlert = [UIAlertController alertControllerWithTitle:[Localize localizedStringForKey:@"SUCCESS"] message:[Localize localizedStringForKey:@"DECRYPTION_COMPLETED"] preferredStyle:UIAlertControllerStyleAlert];
                
                if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"filza://"]]) {
                    [resultAlert addAction:[UIAlertAction actionWithTitle:[Localize localizedStringForKey:@"SHOW_IN_FILZA"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                        NSURL *url = [[NSURL URLWithString:@"filza://view"] URLByAppendingPathComponent:[outputURL path]];
                        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                    }]];
                }

                if (outputURL) {
                    [resultAlert addAction:[UIAlertAction actionWithTitle:[Localize localizedStringForKey:@"SHARE"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                        UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[outputURL] applicationActivities:nil];
                        activityViewController.popoverPresentationController.sourceView = self.view;
                        activityViewController.popoverPresentationController.sourceRect = self.view.bounds;
                        [self presentViewController:activityViewController animated:YES completion:nil];
                    }]];
                }
            } else {
                resultAlert = [UIAlertController alertControllerWithTitle:[Localize localizedStringForKey:@"ERROR"] message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            }
            
            NSString *closeTitle = success ? [Localize localizedStringForKey:@"DISMISS"] : [Localize localizedStringForKey:@"OK"];
            [resultAlert addAction:[UIAlertAction actionWithTitle:closeTitle style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:resultAlert animated:YES completion:nil];
        });
    } options:options];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    NSString *q = sc.searchBar.text ?: @"";
    q = [q stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    static NSString *last = nil;
    if (last && [last isEqualToString:q]) return;   // no-op if same query
    last = [q copy];

    [self _applySearchFilter];
    [self.tableView reloadData];
}

- (void)_applySearchFilter {
    NSString *query = _searchController.searchBar.text ?: @"";
    query = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (query.length == 0) {
        _filteredApplications = _allAvailableApplications ?: @[];
        return;
    }

    _filteredApplications = [_allAvailableApplications filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(LSApplicationProxy *application, NSDictionary *bindings) {
        NSString *name = [[application atl_nameToDisplay] lowercaseString];
        NSString *bundleID = [[application atl_bundleIdentifier] lowercaseString];
        NSString *lowercaseQuery = [query lowercaseString];

        return ([name containsString:lowercaseQuery] || [bundleID containsString:lowercaseQuery]);
    }]];
}

@end
