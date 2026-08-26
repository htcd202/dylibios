#import <UIKit/UIKit.h>
#import <substrate.h>
#import <mach-o/dyld.h>

// ==========================================
// GLOBALS & TOGGLES / SLIDERS STATE
// ==========================================
static BOOL isGodMode = YES;
static BOOL isInfMana = YES;
static BOOL isDumbAI = YES;
static BOOL isMonsterLv1 = YES;
static BOOL isDoubleAtk = YES;
static BOOL isSkipIntro = YES;

static float damageMultiplier = 3.5f; // 1x to 20x
static float attackSpeed = 3.0f;      // 1x to 10x
static float moveSpeed = 3.0f;        // 1x to 10x
static float timeScale = 3.0f;        // 1x to 5x

// ==========================================
// MEMORY HELPER (Get ASLR Base)
// ==========================================
static uintptr_t get_unity_base() {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return (uintptr_t)_dyld_get_image_header(0);
}

// ==========================================
// HOOKS DEFINITIONS (v5.30.2 RVAs)
// ==========================================

// 1. Bonus Damage Rate (0x19811DC)
static double (*orig_get_BonusAttackPowerRate)(void *self);
static double hook_get_BonusAttackPowerRate(void *self) {
    if (damageMultiplier > 1.0f) {
        return (double)(damageMultiplier - 1.0f);
    }
    return orig_get_BonusAttackPowerRate ? orig_get_BonusAttackPowerRate(self) : 0.0;
}

// 2. God Mode (ObjectBase.SetDamage at 0x1948008)
static double (*orig_SetDamage)(void *self, void *attacker, double damage, void *extra, bool flag);
static double hook_SetDamage(void *self, void *attacker, double damage, void *extra, bool flag) {
    if (isGodMode) {
        return 0.0;
    }
    return orig_SetDamage ? orig_SetDamage(self, attacker, damage, extra, flag) : damage;
}

// 3. Infinite Mana (0x1981734)
static double (*orig_get_ConsumeManaReduction)(void *self);
static double hook_get_ConsumeManaReduction(void *self) {
    if (isInfMana) {
        return 1.0; // 100% mana reduction
    }
    return orig_get_ConsumeManaReduction ? orig_get_ConsumeManaReduction(self) : 0.0;
}

// 4. Attack Speed Rate (0x19816BC)
static double (*orig_get_BonusAttackSpeedRate)(void *self);
static double hook_get_BonusAttackSpeedRate(void *self) {
    if (attackSpeed > 1.0f) {
        return (double)attackSpeed;
    }
    return orig_get_BonusAttackSpeedRate ? orig_get_BonusAttackSpeedRate(self) : 0.0;
}

// 5. Move Speed Rate (0x1981824)
static double (*orig_get_BonusMovementSpeedRate)(void *self);
static double hook_get_BonusMovementSpeedRate(void *self) {
    if (moveSpeed > 1.0f) {
        return (double)moveSpeed;
    }
    return orig_get_BonusMovementSpeedRate ? orig_get_BonusMovementSpeedRate(self) : 0.0;
}

// 6. Player Time Scale (0x19D7FAC)
static float (*orig_get_playerTimeScale)(void *self);
static float hook_get_playerTimeScale(void *self) {
    if (timeScale > 1.0f) {
        return timeScale;
    }
    return orig_get_playerTimeScale ? orig_get_playerTimeScale(self) : 1.0f;
}

// 7. Double Attack 100% (0x19818D8) & Damage x2 (0x1981914)
static double (*orig_get_doubleAtkChance)(void *self);
static double hook_get_doubleAtkChance(void *self) {
    if (isDoubleAtk) return 100.0;
    return orig_get_doubleAtkChance ? orig_get_doubleAtkChance(self) : 0.0;
}

static double (*orig_get_doubleAtkPowerRate)(void *self);
static double hook_get_doubleAtkPowerRate(void *self) {
    if (isDoubleAtk) return 2.0;
    return orig_get_doubleAtkPowerRate ? orig_get_doubleAtkPowerRate(self) : 0.0;
}

// 8. Monster Level 1 (0x1EF4CB0 & 0x1EFB24C)
static int (*orig_get_MonsterLevel)(void *self);
static int hook_get_MonsterLevel(void *self) {
    if (isMonsterLv1) return 1;
    return orig_get_MonsterLevel ? orig_get_MonsterLevel(self) : 1;
}

// 9. Dumb AI (0x19D7CC8 & 0x19DB660)
static void (*orig_StartAI)(void *self);
static void hook_StartAI(void *self) {
    if (isDumbAI) return; // Do not start AI
    if (orig_StartAI) orig_StartAI(self);
}

// 10. Skip Camera & Boss Intro (0x190BDA4 & 0x190BFD4)
static void (*orig_TurnOnPath)(void *self, void *cam, void *param);
static void hook_TurnOnPath(void *self, void *cam, void *param) {
    if (isSkipIntro) return;
    if (orig_TurnOnPath) orig_TurnOnPath(self, cam, param);
}

// ==========================================
// FLOATING MOD MENU UI (Objective-C UIKit)
// ==========================================
@interface ModMenuUI : NSObject
+ (void)setupMenu;
@end

@implementation ModMenuUI

static UIButton *floatingBtn = nil;
static UIView *menuView = nil;
static UIScrollView *scrollView = nil;

+ (void)setupMenu {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) {
            NSArray *windows = [UIApplication sharedApplication].windows;
            if (windows.count > 0) keyWindow = windows[0];
        }
        if (!keyWindow) return;

        // Floating Icon Button
        floatingBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingBtn.frame = CGRectMake(20, 100, 55, 55);
        floatingBtn.layer.cornerRadius = 27.5;
        floatingBtn.clipsToBounds = YES;
        floatingBtn.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.25 alpha:0.9];
        floatingBtn.layer.borderColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0].CGColor;
        floatingBtn.layer.borderWidth = 2.0;
        [floatingBtn setTitle:@"⚔️" forState:UIControlStateNormal];
        floatingBtn.titleLabel.font = [UIFont systemFontOfSize:28];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [floatingBtn addGestureRecognizer:pan];
        [floatingBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:floatingBtn];

        // Main Menu Window
        menuView = [[UIView alloc] initWithFrame:CGRectMake(50, 80, 310, 440)];
        menuView.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:0.95];
        menuView.layer.cornerRadius = 16;
        menuView.layer.borderColor = [UIColor colorWithRed:0.2 green:0.7 blue:1.0 alpha:0.8].CGColor;
        menuView.layer.borderWidth = 1.5;
        menuView.clipsToBounds = YES;
        menuView.hidden = YES;

        // Header Title
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 310, 30)];
        titleLabel.text = @"⚔️ KRITIKA v5.30.2 MOD MENU";
        titleLabel.textColor = [UIColor cyanColor];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [menuView addSubview:titleLabel];

        // Scroll View
        scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 45, 290, 345)];
        scrollView.contentSize = CGSizeMake(290, 520);
        scrollView.showsVerticalScrollIndicator = YES;
        [menuView addSubview:scrollView];

        CGFloat y = 10;

        // Toggles
        [self addToggle:@"🛡️ Bất Tử (God Mode)" state:isGodMode tag:1 y:&y];
        [self addToggle:@"🧪 Vô Hạn Mana (Inf Mana)" state:isInfMana tag:2 y:&y];
        [self addToggle:@"🤖 Quái Đứng Yên (Dumb AI)" state:isDumbAI tag:3 y:&y];
        [self addToggle:@"👾 Ép Quái Level 1" state:isMonsterLv1 tag:4 y:&y];
        [self addToggle:@"⚔️ Đòn Đánh Kép 100%" state:isDoubleAtk tag:5 y:&y];
        [self addToggle:@"🚫 Bỏ Cắt Cảnh Boss/Cam" state:isSkipIntro tag:6 y:&y];

        // Sliders
        [self addSlider:@"💥 Sát Thương (Damage)" min:1.0 max:20.0 val:damageMultiplier tag:101 y:&y fmt:@"%.1fx"];
        [self addSlider:@"🗡️ Tốc Độ Đánh (Atk Speed)" min:1.0 max:10.0 val:attackSpeed tag:102 y:&y fmt:@"%.1fx"];
        [self addSlider:@"🏃 Tốc Độ Chạy (Move Speed)" min:1.0 max:10.0 val:moveSpeed tag:103 y:&y fmt:@"%.1fx"];
        [self addSlider:@"⏳ Tua Nhanh Map (Time Scale)" min:1.0 max:5.0 val:timeScale tag:104 y:&y fmt:@"%.1fx"];

        // Close Button
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(20, 395, 270, 35);
        closeBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.9 alpha:0.9];
        closeBtn.layer.cornerRadius = 8;
        [closeBtn setTitle:@"Đóng Menu" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:closeBtn];

        [keyWindow addSubview:menuView];
    });
}

+ (void)addToggle:(NSString *)title state:(BOOL)state tag:(NSInteger)tag y:(CGFloat *)y {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(5, *y, 200, 30)];
    lbl.text = title;
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:13];
    [scrollView addSubview:lbl];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(220, *y, 50, 30)];
    sw.on = state;
    sw.tag = tag;
    sw.onTintColor = [UIColor cyanColor];
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [scrollView addSubview:sw];

    *y += 40;
}

+ (void)addSlider:(NSString *)title min:(float)min max:(float)max val:(float)val tag:(NSInteger)tag y:(CGFloat *)y fmt:(NSString *)fmt {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(5, *y, 200, 20)];
    lbl.text = title;
    lbl.textColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0];
    lbl.font = [UIFont boldSystemFontOfSize:12];
    [scrollView addSubview:lbl];

    UILabel *valLbl = [[UILabel alloc] initWithFrame:CGRectMake(210, *y, 70, 20)];
    valLbl.tag = tag + 1000;
    valLbl.text = [NSString stringWithFormat:fmt, val];
    valLbl.textColor = [UIColor yellowColor];
    valLbl.textAlignment = NSTextAlignmentRight;
    valLbl.font = [UIFont boldSystemFontOfSize:12];
    [scrollView addSubview:valLbl];

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(5, *y + 22, 275, 25)];
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = val;
    slider.tag = tag;
    slider.minimumTrackTintColor = [UIColor cyanColor];
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [scrollView addSubview:slider];

    *y += 55;
}

+ (void)switchChanged:(UISwitch *)sw {
    switch (sw.tag) {
        case 1: isGodMode = sw.on; break;
        case 2: isInfMana = sw.on; break;
        case 3: isDumbAI = sw.on; break;
        case 4: isMonsterLv1 = sw.on; break;
        case 5: isDoubleAtk = sw.on; break;
        case 6: isSkipIntro = sw.on; break;
    }
}

+ (void)sliderChanged:(UISlider *)slider {
    UILabel *valLbl = (UILabel *)[scrollView viewWithTag:slider.tag + 1000];
    if (valLbl) {
        valLbl.text = [NSString stringWithFormat:@"%.1fx", slider.value];
    }
    switch (slider.tag) {
        case 101: damageMultiplier = slider.value; break;
        case 102: attackSpeed = slider.value; break;
        case 103: moveSpeed = slider.value; break;
        case 104: timeScale = slider.value; break;
    }
}

+ (void)toggleMenu {
    menuView.hidden = !menuView.hidden;
}

+ (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    CGPoint translation = [pan translationInView:keyWindow];
    floatingBtn.center = CGPointMake(floatingBtn.center.x + translation.x, floatingBtn.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:keyWindow];
}

@end

// ==========================================
// TWEAK INITIALIZATION & HOOK REGISTRATION
// ==========================================
%ctor {
    uintptr_t base = get_unity_base();
    
    // Register Hooks
    MSHookFunction((void *)(base + 0x19811DC), (void *)hook_get_BonusAttackPowerRate, (void **)&orig_get_BonusAttackPowerRate);
    MSHookFunction((void *)(base + 0x1948008), (void *)hook_SetDamage, (void **)&orig_SetDamage);
    MSHookFunction((void *)(base + 0x1981734), (void *)hook_get_ConsumeManaReduction, (void **)&orig_get_ConsumeManaReduction);
    MSHookFunction((void *)(base + 0x19816BC), (void *)hook_get_BonusAttackSpeedRate, (void **)&orig_get_BonusAttackSpeedRate);
    MSHookFunction((void *)(base + 0x1981824), (void *)hook_get_BonusMovementSpeedRate, (void **)&orig_get_BonusMovementSpeedRate);
    MSHookFunction((void *)(base + 0x19D7FAC), (void *)hook_get_playerTimeScale, (void **)&orig_get_playerTimeScale);
    MSHookFunction((void *)(base + 0x19818D8), (void *)hook_get_doubleAtkChance, (void **)&orig_get_doubleAtkChance);
    MSHookFunction((void *)(base + 0x1981914), (void *)hook_get_doubleAtkPowerRate, (void **)&orig_get_doubleAtkPowerRate);
    MSHookFunction((void *)(base + 0x1EF4CB0), (void *)hook_get_MonsterLevel, (void **)&orig_get_MonsterLevel);
    MSHookFunction((void *)(base + 0x1EFB24C), (void *)hook_get_MonsterLevel, NULL);
    MSHookFunction((void *)(base + 0x19D7CC8), (void *)hook_StartAI, (void **)&orig_StartAI);
    MSHookFunction((void *)(base + 0x19DB660), (void *)hook_StartAI, NULL);
    MSHookFunction((void *)(base + 0x190BDA4), (void *)hook_TurnOnPath, (void **)&orig_TurnOnPath);
    MSHookFunction((void *)(base + 0x190BFD4), (void *)hook_TurnOnPath, NULL);

    // Launch UI
    [ModMenuUI setupMenu];
}
