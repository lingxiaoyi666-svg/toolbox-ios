#import "HGSettings.h"
#import "HGCore.h"
#import <objc/runtime.h>

#pragma mark - 规格表

static NSArray<NSDictionary *> *HGSpecs(void) {
    return @[
        @{@"header": @"广告清除", @"items": @[
              @{@"key": @"splash", @"name": @"开屏广告",
                @"desc": @"启动时跳过开屏广告，直接进首页",
                @"sym": @"play.slash.fill", @"color": [UIColor systemRedColor]},
              @{@"key": @"adview", @"name": @"信息流广告",
                @"desc": @"隐藏首页、视频页、评论区的广告卡片",
                @"sym": @"rectangle.slash.fill", @"color": [UIColor systemOrangeColor]},
              @{@"key": @"popup", @"name": @"推广弹窗",
                @"desc": @"拦截活动、推广类弹窗",
                @"sym": @"bell.slash.fill", @"color": [UIColor systemPinkColor]},
          ]},
        @{@"header": @"界面净化", @"items": @[
              @{@"key": @"hotsearch", @"name": @"热搜榜",
                @"desc": @"隐藏首页顶部热搜区块",
                @"sym": @"flame.fill", @"color": [UIColor systemYellowColor]},
              @{@"key": @"mytab", @"name": @"我的页推广",
                @"desc": @"隐藏会员购、游戏中心等入口",
                @"sym": @"person.crop.circle.badge.minus", @"color": [UIColor systemTealColor]},
              @{@"key": @"update", @"name": @"更新提示",
                @"desc": @"不弹版本更新与升级引导",
                @"sym": @"arrow.down.circle.fill", @"color": [UIColor systemBlueColor]},
              @{@"key": @"teenager", @"name": @"青少年模式弹窗",
                @"desc": @"不弹青少年模式引导",
                @"sym": @"figure.child", @"color": [UIColor systemGreenColor]},
          ]},
        @{@"header": @"实验功能", @"items": @[
              @{@"key": @"watermark", @"name": @"去水印下载",
                @"desc": @"下载视频时去掉水印",
                @"sym": @"arrow.down.to.line.compact", @"color": [UIColor systemIndigoColor]},
              @{@"key": @"danmaku", @"name": @"弹幕增强",
                @"desc": @"屏蔽词与显示参数调整",
                @"sym": @"text.bubble.fill", @"color": [UIColor systemPurpleColor]},
          ]},
    ];
}

#pragma mark - 开关行

@interface HGSwitchCell : UITableViewCell
@property (nonatomic, strong) UIView *iconWrap;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLb;
@property (nonatomic, strong) UILabel *descLb;
@property (nonatomic, strong) UISwitch *sw;
@end

@implementation HGSwitchCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _iconWrap = [UIView new];
    _iconWrap.translatesAutoresizingMaskIntoConstraints = NO;
    _iconWrap.layer.cornerRadius = 7;
    _iconWrap.layer.cornerCurve = kCACornerCurveContinuous;
    [self.contentView addSubview:_iconWrap];

    _iconView = [UIImageView new];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.tintColor = [UIColor whiteColor];
    [_iconWrap addSubview:_iconView];

    _titleLb = [UILabel new];
    _titleLb.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLb.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    _titleLb.textColor = [UIColor labelColor];
    [self.contentView addSubview:_titleLb];

    _descLb = [UILabel new];
    _descLb.translatesAutoresizingMaskIntoConstraints = NO;
    _descLb.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _descLb.textColor = [UIColor secondaryLabelColor];
    _descLb.numberOfLines = 2;
    [self.contentView addSubview:_descLb];

    _sw = [UISwitch new];
    _sw.translatesAutoresizingMaskIntoConstraints = NO;
    _sw.onTintColor = [UIColor systemPinkColor];
    [self.contentView addSubview:_sw];

    [NSLayoutConstraint activateConstraints:@[
        [_iconWrap.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_iconWrap.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_iconWrap.widthAnchor constraintEqualToConstant:30],
        [_iconWrap.heightAnchor constraintEqualToConstant:30],

        [_iconView.centerXAnchor constraintEqualToAnchor:_iconWrap.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:_iconWrap.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:17],
        [_iconView.heightAnchor constraintEqualToConstant:17],

        [_titleLb.leadingAnchor constraintEqualToAnchor:_iconWrap.trailingAnchor constant:12],
        [_titleLb.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [_titleLb.trailingAnchor constraintLessThanOrEqualToAnchor:_sw.leadingAnchor constant:-10],

        [_descLb.leadingAnchor constraintEqualToAnchor:_titleLb.leadingAnchor],
        [_descLb.topAnchor constraintEqualToAnchor:_titleLb.bottomAnchor constant:2],
        [_descLb.trailingAnchor constraintLessThanOrEqualToAnchor:_sw.leadingAnchor constant:-10],
        [_descLb.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],

        [_sw.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [_sw.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
    ]];

    return self;
}

- (void)configureWithItem:(NSDictionary *)item on:(BOOL)on {
    self.titleLb.text = item[@"name"];
    self.descLb.text = item[@"desc"];
    self.sw.on = on;

    self.iconWrap.backgroundColor = item[@"color"] ?: [UIColor systemGrayColor];

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIFontWeightSemibold];
    UIImage *img = [UIImage systemImageNamed:item[@"sym"] ?: @"circle.fill" withConfiguration:cfg];
    if (!img) img = [UIImage systemImageNamed:@"circle.fill" withConfiguration:cfg];
    self.iconView.image = img;
}

@end

#pragma mark - 设置页

@interface BiliPureSettingsVC ()
@property (nonatomic, strong) NSArray<NSDictionary *> *groups;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *flat;
@end

@implementation BiliPureSettingsVC

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _groups = HGSpecs();
        _flat = [NSMutableArray array];
        for (NSDictionary *g in _groups) {
            [_flat addObjectsFromArray:g[@"items"]];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"测试";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    if (!self.navigationController || self.navigationController.viewControllers.count <= 1) {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"完成"
                                             style:UIBarButtonItemStyleDone
                                            target:self
                                            action:@selector(hg_done)];
    }
}

- (void)hg_done {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.groups.count + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section >= (NSInteger)self.groups.count) return 1;
    return [self.groups[section][@"items"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section >= (NSInteger)self.groups.count) return nil;
    return self.groups[section][@"header"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != (NSInteger)self.groups.count) return nil;
    return @"BiliPure · bilibili 9.21.0\n日志：/var/mobile/Library/Preferences/com.hg.bilipure.log";
}

- (NSInteger)hg_indexOfSection:(NSInteger)section row:(NSInteger)row {
    NSInteger base = 0;
    for (NSInteger i = 0; i < section && i < (NSInteger)self.groups.count; i++) {
        base += [self.groups[i][@"items"] count];
    }
    return base + row;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section >= (NSInteger)self.groups.count) {
        UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                    reuseIdentifier:@"about"];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        c.textLabel.text = @"BiliPure";
        c.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        c.detailTextLabel.text = @"注入式净化插件 · 点任意一行可切换";
        c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        c.detailTextLabel.font = [UIFont systemFontOfSize:12];
        return c;
    }

    HGSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"hgswitch"];
    if (!cell) {
        cell = [[HGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"hgswitch"];
    }

    NSDictionary *item = self.groups[indexPath.section][@"items"][indexPath.row];
    [cell configureWithItem:item on:HGOn(item[@"key"])];

    cell.sw.tag = [self hg_indexOfSection:indexPath.section row:indexPath.row];
    [cell.sw removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [cell.sw addTarget:self action:@selector(hg_switchChanged:) forControlEvents:UIControlEventValueChanged];

    return cell;
}

- (void)hg_switchChanged:(UISwitch *)sw {
    if (sw.tag < 0 || sw.tag >= (NSInteger)self.flat.count) return;
    NSDictionary *item = self.flat[sw.tag];
    HGSetOn(item[@"key"], sw.on);
    HGLog(@"开关 %@ -> %@", item[@"key"], sw.on ? @"开" : @"关");
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section >= (NSInteger)self.groups.count) return;

    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (![cell isKindOfClass:[HGSwitchCell class]]) return;

    HGSwitchCell *sc = (HGSwitchCell *)cell;
    [sc.sw setOn:!sc.sw.on animated:YES];
    [self hg_switchChanged:sc.sw];
}

@end

#pragma mark - 注入到 B 站设置页的点击方法

void hg_openBiliPureSettings(id self, SEL _cmd) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            BiliPureSettingsVC *vc = [[BiliPureSettingsVC alloc] init];
            vc.hidesBottomBarWhenPushed = YES;
            UIViewController *host = (UIViewController *)self;
            UINavigationController *nav = host.navigationController;
            if (nav) {
                [nav pushViewController:vc animated:YES];
            } else {
                UINavigationController *wrapper =
                    [[UINavigationController alloc] initWithRootViewController:vc];
                [host presentViewController:wrapper animated:YES completion:nil];
            }
        } @catch (NSException *e) {
            HGLog(@"打开设置页失败: %@", e.reason);
        }
    });
}
