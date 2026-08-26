#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <string.h>

extern void sys_icache_invalidate(void *start, size_t len);

// ==========================================
// GLOBALS & TOGGLES / SLIDERS STATE
// ==========================================
static BOOL isGodMode = YES;
static BOOL isInfMana = YES;
static BOOL isDumbAI = YES;
static BOOL isMonsterLv1 = YES;
static BOOL isDoubleAtk = YES;
static BOOL isSkipIntro = YES;

static float damageMultiplier = 3.5f;
static float attackSpeed = 3.0f;
static float moveSpeed = 3.0f;
static float timeScale = 3.0f;

// ==========================================
// MEMORY HELPER
// ==========================================
static uintptr_t unity_base = 0;

static uintptr_t get_unity_base() {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    if (count > 0) {
        return (uintptr_t)_dyld_get_image_header(0);
    }
    return 0;
}

static bool write_mem(uintptr_t addr, const void *data, size_t len) {
    if (!addr || !data || len == 0) return false;
    kern_return_t kr;
    mach_port_t task = mach_task_self();
    
    uintptr_t page = addr & ~(uintptr_t)(0xFFF);
    kr = vm_protect(task, (vm_address_t)page, 0x4000, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) {
        kr = vm_protect(task, (vm_address_t)page, 0x4000, false, VM_PROT_ALL);
    }
    if (kr != KERN_SUCCESS) return false;
    
    memcpy((void *)addr, data, len);
    
    vm_protect(task, (vm_address_t)page, 0x4000, false, VM_PROT_READ | VM_PROT_EXECUTE);
    sys_icache_invalidate((void *)addr, len);
    return true;
}

// ==========================================
// PATCH DEFINITIONS (v5.30.2 RVAs)
// ==========================================
static uint8_t patch_zero_double[] = {0x00,0x00,0x80,0xD2, 0x00,0x00,0x67,0x9E, 0xC0,0x03,0x5F,0xD6};
static uint8_t patch_1_0_double[]  = {0x00,0xE0,0xDF,0xD2, 0x00,0x00,0x67,0x9E, 0xC0,0x03,0x5F,0xD6};
static uint8_t patch_100_double[]  = {0x20,0x0B,0xE0,0xD2, 0x00,0x00,0x67,0x9E, 0xC0,0x03,0x5F,0xD6};
static uint8_t patch_2_0_double[]  = {0x00,0x00,0xE0,0xD2, 0x00,0x00,0x67,0x9E, 0xC0,0x03,0x5F,0xD6};
static uint8_t patch_int_1[]       = {0x20,0x00,0x80,0x52, 0xC0,0x03,0x5F,0xD6};
static uint8_t patch_ret[]         = {0xC0,0x03,0x5F,0xD6};

// Backup storage
static uint8_t orig_godmode[12];
static uint8_t orig_infmana[12];
static uint8_t orig_dblatkchance[12];
static uint8_t orig_dblatkdmg[12];
static uint8_t orig_monsterlv1[8];
static uint8_t orig_monsterlv2[8];
static uint8_t orig_monsterlv3[8];
static uint8_t orig_dumbai1[4];
static uint8_t orig_dumbai2[4];
static uint8_t orig_skipintro1[4];
static uint8_t orig_skipintro2[4];
static uint8_t orig_skipintro3[4];
static uint8_t orig_bonusdmg[12];
static uint8_t orig_atkspd[12];
static uint8_t orig_movspd[12];
static uint8_t orig_timescale[12];

static BOOL backupsDone = NO;

static void backup_original_bytes() {
    if (backupsDone || !unity_base) return;
    memcpy(orig_godmode,     (void*)(unity_base + 0x1948008), 12);
    memcpy(orig_infmana,     (void*)(unity_base + 0x1981734), 12);
    memcpy(orig_dblatkchance,(void*)(unity_base + 0x19818D8), 12);
    memcpy(orig_dblatkdmg,   (void*)(unity_base + 0x1981914), 12);
    memcpy(orig_monsterlv1,  (void*)(unity_base + 0x1EF4CB0), 8);
    memcpy(orig_monsterlv2,  (void*)(unity_base + 0x1EF4FA4), 8);
    memcpy(orig_monsterlv3,  (void*)(unity_base + 0x1EFB24C), 8);
    memcpy(orig_dumbai1,     (void*)(unity_base + 0x19D7CC8), 4);
    memcpy(orig_dumbai2,     (void*)(unity_base + 0x19DB660), 4);
    memcpy(orig_skipintro1,  (void*)(unity_base + 0x190BDA4), 4);
    memcpy(orig_skipintro2,  (void*)(unity_base + 0x190BFD4), 4);
    memcpy(orig_skipintro3,  (void*)(unity_base + 0x190B29C), 4);
    memcpy(orig_bonusdmg,    (void*)(unity_base + 0x19811DC), 12);
    memcpy(orig_atkspd,      (void*)(unity_base + 0x19816BC), 12);
    memcpy(orig_movspd,      (void*)(unity_base + 0x1981824), 12);
    memcpy(orig_timescale,   (void*)(unity_base + 0x19D7FAC), 12);
    backupsDone = YES;
}

static void build_double_patch(uint8_t *buf, double val) {
    uint64_t bits;
    memcpy(&bits, &val, 8);
    uint16_t upper16 = (uint16_t)(bits >> 48);
    uint32_t movz = 0xD2E00000 | ((uint32_t)upper16 << 5);
    uint32_t fmov = 0x9E670000;
    uint32_t ret  = 0xD65F03C0;
    memcpy(buf + 0, &movz, 4);
    memcpy(buf + 4, &fmov, 4);
    memcpy(buf + 8, &ret, 4);
}

static void build_float_patch(uint8_t *buf, float val) {
    uint32_t bits;
    memcpy(&bits, &val, 4);
    uint16_t upper16 = (uint16_t)(bits >> 16);
    uint32_t movz = 0x52A00000 | ((uint32_t)upper16 << 5);
    uint32_t fmov = 0x1E270000;
    uint32_t ret  = 0xD65F03C0;
    memcpy(buf + 0, &movz, 4);
    memcpy(buf + 4, &fmov, 4);
    memcpy(buf + 8, &ret, 4);
}

static void apply_toggle(uintptr_t rva, uint8_t *patch, size_t sz, uint8_t *orig, BOOL enable) {
    if (!unity_base) return;
    uintptr_t addr = unity_base + rva;
    if (enable) {
        write_mem(addr, patch, sz);
    } else {
        write_mem(addr, orig, sz);
    }
}

static void apply_slider_double(uintptr_t rva, float val, uint8_t *orig) {
    if (!unity_base) return;
    uintptr_t addr = unity_base + rva;
    if (val > 1.01f) {
        uint8_t buf[12];
        build_double_patch(buf, (double)(val - 1.0f));
        write_mem(addr, buf, 12);
    } else {
        write_mem(addr, orig, 12);
    }
}

static void apply_slider_double_direct(uintptr_t rva, float val, uint8_t *orig) {
    if (!unity_base) return;
    uintptr_t addr = unity_base + rva;
    if (val > 1.01f) {
        uint8_t buf[12];
        build_double_patch(buf, (double)val);
        write_mem(addr, buf, 12);
    } else {
        write_mem(addr, orig, 12);
    }
}

static void apply_slider_float(uintptr_t rva, float val, uint8_t *orig) {
    if (!unity_base) return;
    uintptr_t addr = unity_base + rva;
    if (val > 1.01f) {
        uint8_t buf[12];
        build_float_patch(buf, val);
        write_mem(addr, buf, 12);
    } else {
        write_mem(addr, orig, 12);
    }
}

static void apply_all_patches() {
    if (!unity_base) {
        unity_base = get_unity_base();
    }
    if (!unity_base) return;
    if (!backupsDone) backup_original_bytes();
    
    // Toggles
    apply_toggle(0x1948008, patch_zero_double, 12, orig_godmode, isGodMode);
    apply_toggle(0x1981734, patch_1_0_double, 12, orig_infmana, isInfMana);
    apply_toggle(0x19818D8, patch_100_double, 12, orig_dblatkchance, isDoubleAtk);
    apply_toggle(0x1981914, patch_2_0_double, 12, orig_dblatkdmg, isDoubleAtk);
    
    apply_toggle(0x1EF4CB0, patch_int_1, 8, orig_monsterlv1, isMonsterLv1);
    apply_toggle(0x1EF4FA4, patch_int_1, 8, orig_monsterlv2, isMonsterLv1);
    apply_toggle(0x1EFB24C, patch_int_1, 8, orig_monsterlv3, isMonsterLv1);
    
    apply_toggle(0x19D7CC8, patch_ret, 4, orig_dumbai1, isDumbAI);
    apply_toggle(0x19DB660, patch_ret, 4, orig_dumbai2, isDumbAI);
    
    apply_toggle(0x190BDA4, patch_ret, 4, orig_skipintro1, isSkipIntro);
    apply_toggle(0x190BFD4, patch_ret, 4, orig_skipintro2, isSkipIntro);
    apply_toggle(0x190B29C, patch_ret, 4, orig_skipintro3, isSkipIntro);
    
    // Sliders
    apply_slider_double(0x19811DC, damageMultiplier, orig_bonusdmg);
    apply_slider_double_direct(0x19816BC, attackSpeed, orig_atkspd);
    apply_slider_double_direct(0x1981824, moveSpeed, orig_movspd);
    apply_slider_float(0x19D7FAC, timeScale, orig_timescale);
}

// ==========================================
// MOD MENU UI IMPLEMENTATION
// ==========================================
@interface ModMenuUI : NSObject
+ (void)setupMenuWithParent:(UIView *)parentView;
+ (void)toggleMenu;
@end

static UIButton *floatingBtn = nil;
static UIView *menuView = nil;
static UIScrollView *scrollView = nil;
static BOOL isMenuAttached = NO;

@implementation ModMenuUI

+ (void)setupMenuWithParent:(UIView *)parentView {
    if (!parentView) return;
    if (isMenuAttached && floatingBtn && floatingBtn.superview) {
        [parentView bringSubviewToFront:floatingBtn];
        if (menuView) [parentView bringSubviewToFront:menuView];
        return;
    }
    isMenuAttached = YES;

    // Apply memory patches
    unity_base = get_unity_base();
    backup_original_bytes();
    apply_all_patches();

    CGRect screenBounds = parentView.bounds;
    CGFloat screenW = screenBounds.size.width;
    CGFloat screenH = screenBounds.size.height;

    // 1. Floating Button (Draggable)
    if (!floatingBtn) {
        floatingBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingBtn.frame = CGRectMake(30, 80, 56, 56);
        floatingBtn.layer.cornerRadius = 28.0;
        floatingBtn.clipsToBounds = YES;
        floatingBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.12 blue:0.22 alpha:0.94];
        floatingBtn.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:1.0].CGColor;
        floatingBtn.layer.borderWidth = 2.5;
        [floatingBtn setTitle:@"⚔️" forState:UIControlStateNormal];
        floatingBtn.titleLabel.font = [UIFont systemFontOfSize:28];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [floatingBtn addGestureRecognizer:pan];
        [floatingBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    }
    [parentView addSubview:floatingBtn];
    [parentView bringSubviewToFront:floatingBtn];

    // 2. Main Menu Window
    if (!menuView) {
        CGFloat menuW = MIN(320, screenW - 40);
        CGFloat menuH = MIN(460, screenH - 80);
        
        menuView = [[UIView alloc] initWithFrame:CGRectMake((screenW - menuW)/2, (screenH - menuH)/2, menuW, menuH)];
        menuView.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.14 alpha:0.96];
        menuView.layer.cornerRadius = 16;
        menuView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:0.9].CGColor;
        menuView.layer.borderWidth = 2.0;
        menuView.clipsToBounds = YES;
        menuView.hidden = YES;

        // Header Title
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 12, menuW, 26)];
        titleLabel.text = @"⚔️ KRITIKA MOD MENU v5.30.2";
        titleLabel.textColor = [UIColor cyanColor];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [menuView addSubview:titleLabel];

        // Scroll View
        scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 45, menuW - 20, menuH - 95)];
        scrollView.showsVerticalScrollIndicator = YES;
        [menuView addSubview:scrollView];

        CGFloat y = 10;

        // Toggles
        [self addToggle:@"🛡️ Bất Tử (God Mode)" state:isGodMode tag:1 y:&y w:menuW-40];
        [self addToggle:@"🧪 Vô Hạn Mana" state:isInfMana tag:2 y:&y w:menuW-40];
        [self addToggle:@"🤖 Quái Đứng Yên (Dumb AI)" state:isDumbAI tag:3 y:&y w:menuW-40];
        [self addToggle:@"👾 Ép Quái Level 1" state:isMonsterLv1 tag:4 y:&y w:menuW-40];
        [self addToggle:@"⚔️ Đòn Đánh Kép 100%" state:isDoubleAtk tag:5 y:&y w:menuW-40];
        [self addToggle:@"🚫 Bỏ Cắt Cảnh Boss/Cam" state:isSkipIntro tag:6 y:&y w:menuW-40];

        // Sliders
        [self addSlider:@"💥 Sát Thương (Damage)" min:1.0 max:20.0 val:damageMultiplier tag:101 y:&y w:menuW-40];
        [self addSlider:@"🗡️ Tốc Độ Đánh" min:1.0 max:10.0 val:attackSpeed tag:102 y:&y w:menuW-40];
        [self addSlider:@"🏃 Tốc Độ Chạy" min:1.0 max:10.0 val:moveSpeed tag:103 y:&y w:menuW-40];
        [self addSlider:@"⏳ Tua Nhanh Map" min:1.0 max:5.0 val:timeScale tag:104 y:&y w:menuW-40];

        scrollView.contentSize = CGSizeMake(menuW - 40, y + 15);

        // Close Button
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(20, menuH - 44, menuW - 40, 36);
        closeBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.55 blue:0.85 alpha:0.95];
        closeBtn.layer.cornerRadius = 8;
        [closeBtn setTitle:@"Đóng Menu" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:closeBtn];
    }
    [parentView addSubview:menuView];
    [parentView bringSubviewToFront:menuView];
}

+ (void)addToggle:(NSString *)title state:(BOOL)state tag:(NSInteger)tag y:(CGFloat *)y w:(CGFloat)w {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(5, *y, w - 60, 30)];
    lbl.text = title;
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:13];
    [scrollView addSubview:lbl];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(w - 55, *y, 50, 30)];
    sw.on = state;
    sw.tag = tag;
    sw.onTintColor = [UIColor cyanColor];
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [scrollView addSubview:sw];

    *y += 40;
}

+ (void)addSlider:(NSString *)title min:(float)min max:(float)max val:(float)val tag:(NSInteger)tag y:(CGFloat *)y w:(CGFloat)w {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(5, *y, w - 70, 20)];
    lbl.text = title;
    lbl.textColor = [UIColor colorWithRed:0.4 green:0.85 blue:1.0 alpha:1.0];
    lbl.font = [UIFont boldSystemFontOfSize:12];
    [scrollView addSubview:lbl];

    UILabel *valLbl = [[UILabel alloc] initWithFrame:CGRectMake(w - 65, *y, 60, 20)];
    valLbl.tag = tag + 1000;
    valLbl.text = [NSString stringWithFormat:@"%.1fx", val];
    valLbl.textColor = [UIColor yellowColor];
    valLbl.textAlignment = NSTextAlignmentRight;
    valLbl.font = [UIFont boldSystemFontOfSize:12];
    [scrollView addSubview:valLbl];

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(5, *y + 22, w - 10, 25)];
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
    apply_all_patches();
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
    apply_all_patches();
}

+ (void)toggleMenu {
    if (!menuView) return;
    menuView.hidden = !menuView.hidden;
    if (menuView.superview) {
        [menuView.superview bringSubviewToFront:menuView];
    }
}

+ (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *superview = floatingBtn.superview;
    if (!superview) return;
    CGPoint translation = [pan translationInView:superview];
    floatingBtn.center = CGPointMake(floatingBtn.center.x + translation.x, floatingBtn.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:superview];
}

@end

// ==========================================
// SWIZZLE VIEWCONTROLLER (GUARANTEED INJECTION)
// ==========================================
static void (*orig_UIViewController_viewDidAppear)(id self, SEL _cmd, BOOL animated);

static void swizzle_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_UIViewController_viewDidAppear) {
        orig_UIViewController_viewDidAppear(self, _cmd, animated);
    }
    
    // Attach menu directly to the active visible ViewController view!
    if (self.view) {
        [ModMenuUI setupMenuWithParent:self.view];
    }
}

// ==========================================
// CONSTRUCTOR & METHOD SWIZZLING
// ==========================================
__attribute__((constructor))
static void init_mod_menu() {
    // 1. Swizzle UIViewController viewDidAppear
    Class vcClass = [UIViewController class];
    SEL sel = @selector(viewDidAppear:);
    Method m = class_getInstanceMethod(vcClass, sel);
    if (m) {
        orig_UIViewController_viewDidAppear = (void (*)(id, SEL, BOOL))method_getImplementation(m);
        method_setImplementation(m, (IMP)swizzle_viewDidAppear);
    }

    // 2. Continuous Polling Timer (attach to keyWindow / rootVC view)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
            UIWindow *kw = [UIApplication sharedApplication].keyWindow;
            if (!kw && [UIApplication sharedApplication].windows.count > 0) {
                kw = [UIApplication sharedApplication].windows.firstObject;
            }
            if (kw && kw.rootViewController && kw.rootViewController.view) {
                [ModMenuUI setupMenuWithParent:kw.rootViewController.view];
            }
        }];
    });
}
