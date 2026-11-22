// Mac 控制窗口（遊戲 → 輸入裝置… / ⌘,）：兩頁「鍵盤」「手柄」，中間畫一個手柄，四周每個 Switch 控制項一個按鈕，顯示現在對應的鍵。
//   點按鈕 → 按新的鍵（手柄頁按手柄上的鍵）就改好；Esc 取消，⌫ 解除。底下選輸入裝置（全部 / 只用手柄 / 只用鍵盤滑鼠），顯示接著的手柄，可恢復默認。
//   鍵盤改鍵寫進玩家的鍵位表（keymap.txt，只改 key: 行，滑鼠 / 觸控板的行原樣保留），手柄改鍵存 defaults 的 PadMap（front_mac.m）。
// Mac Controls window (Game → Input Devices… / ⌘,): two pages, Keyboard and Controller, with a drawn controller in the middle and one button per Switch control around it showing what it is bound to.
//   Click a button, then press the new key (on the Controller page, a controller button) and it is set; Esc cancels, ⌫ unbinds. At the bottom: the input devices (everything / controller only / keyboard and mouse only), the connected controllers, and restoring the defaults.
//   Keyboard remaps go into the player's keymap (keymap.txt; only key: lines change, mouse / trackpad lines stay as they are), controller remaps into PadMap in the defaults (front_mac.m).
#import <Cocoa/Cocoa.h>
#include "dm.h"
#include "controls_mac.h"

static NSString *S(const char *en, const char *zh, const char *es) { int l = front_ui_lang(); return @(l == 1 ? zh : l == 2 ? es : en); }

// ---- 控制項 | Controls ----
// target：鍵位表裡的 Switch 名字；sw：Switch 鍵位（DM_BTN_* 位序，手柄頁能改），-1 = 搖桿方向（只在鍵盤頁能改）
// target: the Switch name in the keymap; sw: the Switch button bit (DM_BTN_* bit order, remappable on the Controller page), -1 = a stick direction (remappable on the Keyboard page only)
typedef struct { const char *target; int sw; const char *en, *zh, *es; CGFloat cx, y; } ctl_def;
enum { BW = 100, BH = 24 };
static const ctl_def k_ctl[] = {
    {"StickLUp", -1, "Up", "上", "Arriba", 136, 500}, {"StickLLeft", -1, "Left", "左", "Izquierda", 76, 450}, {"StickLRight", -1, "Right", "右", "Derecha", 196, 450},
    {"StickLDown", -1, "Down", "下", "Abajo", 136, 400}, {"LS", 4, "Pressed", "按下", "Presionar", 136, 330},
    {"Up", 13, "Up", "上", "Arriba", 136, 228}, {"Left", 12, "Left", "左", "Izquierda", 76, 178}, {"Right", 14, "Right", "右", "Derecha", 196, 178},
    {"Down", 15, "Down", "下", "Abajo", 136, 128},
    {"L", 6, "L", "L", "L", 318, 530}, {"ZL", 8, "ZL", "ZL", "ZL", 318, 478}, {"Minus", 11, "Minus", "−", "Menos", 414, 530}, {"Plus", 10, "Plus", "+", "Más", 506, 530},
    {"R", 7, "R", "R", "R", 602, 530}, {"ZR", 9, "ZR", "ZR", "ZR", 602, 478},
    {"X", 2, "X", "X", "X", 784, 500}, {"Y", 3, "Y", "Y", "Y", 724, 450}, {"A", 0, "A", "A", "A", 844, 450}, {"B", 1, "B", "B", "B", 784, 400},
    {"StickRUp", -1, "Up", "上", "Arriba", 784, 314}, {"StickRLeft", -1, "Left", "左", "Izquierda", 724, 264}, {"StickRRight", -1, "Right", "右", "Derecha", 844, 264},
    {"StickRDown", -1, "Down", "下", "Abajo", 784, 214}, {"RS", 5, "Pressed", "按下", "Presionar", 784, 134},
};
enum { N_CTL = sizeof k_ctl / sizeof *k_ctl };

// ---- 鍵盤：鍵位表 | Keyboard: the keymap ----
// 「來源 目標」行 → 有序表；# 起是注釋 | "source target" lines → an ordered list; # starts a comment
static NSArray<NSArray<NSString *> *> *map_parse(NSString *text) {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *l = line; NSRange h = [l rangeOfString:@"#"]; if (h.location != NSNotFound) l = [l substringToIndex:h.location];
        NSArray *w = [[l componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        if (w.count == 2) [rows addObject:w];
    }
    return rows;
}
static NSString *user_text(void) { const char *p = front_keymap_path(); return p ? [NSString stringWithContentsOfFile:@(p) encoding:NSUTF8StringEncoding error:nil] ?: @"" : @""; }
static BOOL is_key(NSString *src) { return [src.lowercaseString hasPrefix:@"key:"]; }
// key: 來源 → 目標（小寫鍵名為鍵）：默認表，可再疊上玩家的表 | key: source → target (keyed by the lower-cased name): the default table, optionally with the player's table on top
static NSMutableDictionary<NSString *, NSString *> *key_map(BOOL with_user) {
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (NSArray *r in map_parse(@(front_keymap_defaults()))) if (is_key(r[0])) m[[r[0] lowercaseString]] = r[1];
    if (with_user) for (NSArray *r in map_parse(user_text())) if (is_key(r[0])) { if ([r[1] isEqualToString:@"-"]) [m removeObjectForKey:[r[0] lowercaseString]]; else m[[r[0] lowercaseString]] = r[1]; }
    return m;
}
// 寫回玩家的表：非 key: 的行（含注釋）原樣保留，key: 行只寫和默認不同的（沒了的寫「-」） | write the player's table back: non-key: lines (comments included) stay as they are, and key: lines are written only where they differ from the default ("-" for removed ones)
static void key_map_write(NSDictionary<NSString *, NSString *> *m) {
    const char *p = front_keymap_path(); if (!p) return;
    NSMutableString *out = [NSMutableString string];
    for (NSString *line in [user_text() componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *t = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (t.length && !is_key(t)) [out appendFormat:@"%@\n", line];
    }
    NSDictionary *def = key_map(NO); NSMutableSet *all = [NSMutableSet setWithArray:def.allKeys]; [all addObjectsFromArray:m.allKeys];
    for (NSString *k in [all.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *v = m[k]; if (v ? [v caseInsensitiveCompare:def[k] ?: @""] == NSOrderedSame : !def[k]) continue;
        // 鍵名寫回原來的大小寫（從鍵名表找） | write the key name back in its original case (looked up in the key-name table)
        NSString *name = [k substringFromIndex:4];
        for (int c = 0; c < 128; c++) if (front_keyname(c) && [@(front_keyname(c)) caseInsensitiveCompare:name] == NSOrderedSame) { name = @(front_keyname(c)); break; }
        [out appendFormat:@"key:%@ %@\n", name, v ?: @"-"];
    }
    [NSFileManager.defaultManager createDirectoryAtPath:[@(p) stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    if (![out writeToFile:@(p) atomically:YES encoding:NSUTF8StringEncoding error:nil]) LOG("【紅】控制窗口：寫不進鍵位表 %s", p);
    front_keymap_apply();
}
static NSString *key_label(const char *name) {   // 鍵名 → 給人看的字 | key name → what to show
    static const char *const nice[][2] = {{"Left", "←"}, {"Right", "→"}, {"Up", "↑"}, {"Down", "↓"}, {"Return", "⏎"}, {"Tab", "⇥ Tab"}, {"Space", "␣"},
        {"Semicolon", ";"}, {"Quote", "'"}, {"Comma", ","}, {"Period", "."}, {"Slash", "/"}, {"Backslash", "\\"}, {"LeftBracket", "["}, {"RightBracket", "]"},
        {"Minus", "-"}, {"Equal", "="}, {"Grave", "`"}, {"Delete", "⌫"}, {"Escape", "Esc"}};
    for (unsigned i = 0; i < sizeof nice / sizeof *nice; i++) if (!strcasecmp(name, nice[i][0])) return @(nice[i][1]);
    return @(name);
}

// ---- 手柄：實體鍵的名字 | Controller: physical button names ----
static NSString *phys_label(int p) {
    switch (p) {
        case P_SOUTH: return S("A (bottom)", "A（下）", "A (abajo)"); case P_EAST: return S("B (right)", "B（右）", "B (derecha)");
        case P_WEST: return S("X (left)", "X（左）", "X (izquierda)"); case P_NORTH: return S("Y (top)", "Y（上）", "Y (arriba)");
        case P_LB: return @"LB"; case P_RB: return @"RB"; case P_LT: return @"LT"; case P_RT: return @"RT";
        case P_START: return @"Start"; case P_BACK: return @"Back"; case P_LS: return @"L3"; case P_RS: return @"R3";
        case P_UP: return S("D-pad ↑", "十字鍵 ↑", "Cruceta ↑"); case P_DOWN: return S("D-pad ↓", "十字鍵 ↓", "Cruceta ↓");
        case P_LEFT: return S("D-pad ←", "十字鍵 ←", "Cruceta ←"); case P_RIGHT: return S("D-pad →", "十字鍵 →", "Cruceta →");
    }
    return @"—";
}

// ---- 手柄圖 | Controller drawing ----
@interface DMPadArt : NSView
@property int highlight;   // 正在錄的控制項（k_ctl 序號），-1 = 沒有 | the control being captured (index into k_ctl), -1 = none
@end
@implementation DMPadArt
- (BOOL)isFlipped { return NO; }
static void disc(NSPoint c, CGFloat r, NSColor *fill, NSString *txt, CGFloat fs) {
    [fill setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - r, c.y - r, 2 * r, 2 * r)] fill];
    if (!txt) return;
    NSDictionary *a = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:fs], NSForegroundColorAttributeName: NSColor.whiteColor};
    NSSize z = [txt sizeWithAttributes:a]; [txt drawAtPoint:NSMakePoint(c.x - z.width / 2, c.y - z.height / 2) withAttributes:a];
}
- (BOOL)lit:(const char *)target { return self.highlight >= 0 && !strcmp(k_ctl[self.highlight].target, target); }
- (BOOL)litStick:(char)side { if (self.highlight < 0) return NO; const char *t = k_ctl[self.highlight].target;
    return (!strncmp(t, "Stick", 5) && t[5] == side) || (side == 'L' && !strcmp(t, "LS")) || (side == 'R' && !strcmp(t, "RS")); }
- (void)drawRect:(NSRect)dirty {
    (void)dirty; NSRect b = self.bounds; CGFloat ox = (b.size.width - 380) / 2, oy = (b.size.height - 320) / 2;
    NSAffineTransform *t = [NSAffineTransform transform]; [t translateXBy:ox yBy:oy]; [t concat];
    NSColor *body = [NSColor colorWithWhite:0.86 alpha:1], *dark = [NSColor colorWithWhite:0.22 alpha:1], *hl = NSColor.controlAccentColor;
    // 肩鍵 | shoulders
    [([self lit:"ZL"] ? hl : [NSColor colorWithWhite:0.55 alpha:1]) setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(62, 254, 80, 26) xRadius:12 yRadius:12] fill];
    [([self lit:"ZR"] ? hl : [NSColor colorWithWhite:0.55 alpha:1]) setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(238, 254, 80, 26) xRadius:12 yRadius:12] fill];
    [([self lit:"L"] ? hl : [NSColor colorWithWhite:0.7 alpha:1]) setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(58, 228, 92, 30) xRadius:10 yRadius:10] fill];
    [([self lit:"R"] ? hl : [NSColor colorWithWhite:0.7 alpha:1]) setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(230, 228, 92, 30) xRadius:10 yRadius:10] fill];
    // 機身與兩個握把 | body and the two grips
    [body setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(40, 110, 300, 128) xRadius:56 yRadius:56] fill];
    for (int side = 0; side < 2; side++) {
        NSAffineTransform *g = [NSAffineTransform transform]; [g translateXBy:side ? 290 : 90 yBy:110]; [g rotateByDegrees:side ? 22 : -22];
        NSBezierPath *grip = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(-42, -95, 84, 140) xRadius:42 yRadius:42]; [grip transformUsingAffineTransform:g]; [grip fill];
    }
    // 搖桿 | sticks
    disc(NSMakePoint(110, 192), 30, [self litStick:'L'] ? hl : [NSColor colorWithWhite:0.6 alpha:1], nil, 0); disc(NSMakePoint(110, 192), 22, dark, @"L", 13);
    disc(NSMakePoint(236, 136), 30, [self litStick:'R'] ? hl : [NSColor colorWithWhite:0.6 alpha:1], nil, 0); disc(NSMakePoint(236, 136), 22, dark, @"R", 13);
    // 十字鍵 | D-pad
    NSPoint d = NSMakePoint(150, 136); static const struct { const char *t; int dx, dy; } arms[] = {{"Up", 0, 1}, {"Down", 0, -1}, {"Left", -1, 0}, {"Right", 1, 0}};
    [dark setFill]; [[NSBezierPath bezierPathWithRect:NSMakeRect(d.x - 9, d.y - 9, 18, 18)] fill];
    for (int i = 0; i < 4; i++) { [([self lit:arms[i].t] ? hl : dark) setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(d.x - 9 + arms[i].dx * 17, d.y - 9 + arms[i].dy * 17, 18, 18) xRadius:3 yRadius:3] fill]; }
    // 面鍵（任天堂位置：右 A、下 B、上 X、左 Y） | face buttons (Nintendo positions: right A, bottom B, top X, left Y)
    NSPoint f = NSMakePoint(278, 192); static const struct { const char *t; int dx, dy; } face[] = {{"A", 1, 0}, {"B", 0, -1}, {"X", 0, 1}, {"Y", -1, 0}};
    for (int i = 0; i < 4; i++) disc(NSMakePoint(f.x + face[i].dx * 25, f.y + face[i].dy * 25), 13, [self lit:face[i].t] ? hl : dark, @(face[i].t), 12);
    // − / + / HOME
    disc(NSMakePoint(162, 214), 9, [self lit:"Minus"] ? hl : dark, @"−", 12); disc(NSMakePoint(218, 214), 9, [self lit:"Plus"] ? hl : dark, @"+", 12);
    disc(NSMakePoint(190, 188), 8, [NSColor colorWithWhite:0.45 alpha:1], nil, 0);
    // 肩鍵字 | shoulder labels
    NSDictionary *a = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:11], NSForegroundColorAttributeName: dark};
    [@"ZL" drawAtPoint:NSMakePoint(94, 262) withAttributes:a]; [@"ZR" drawAtPoint:NSMakePoint(270, 262) withAttributes:a];
    [@"L" drawAtPoint:NSMakePoint(100, 240) withAttributes:a]; [@"R" drawAtPoint:NSMakePoint(272, 240) withAttributes:a];
}
@end

// ---- 窗口 | Window ----
@interface DMControls : NSObject <NSWindowDelegate>
@end
static DMControls *g_ctl;
@implementation DMControls {
    NSWindow *_win; NSSegmentedControl *_tabs; DMPadArt *_art; NSButton *_btn[N_CTL]; NSTextField *_lab[N_CTL];
    NSPopUpButton *_mode; NSTextField *_status, *_hint; NSTimer *_timer; id _monitor;
    int _capture; uint32_t _lastPhys;
}
- (BOOL)padPage { return _tabs.selectedSegment == 1; }
static NSTextField *text_at(NSView *v, NSString *s, NSRect r, CGFloat size, NSTextAlignment al) {
    NSTextField *t = [NSTextField labelWithString:s]; t.frame = r; t.alignment = al; t.font = [NSFont systemFontOfSize:size]; [v addSubview:t]; return t;
}
static void box_at(NSView *v, NSString *title, NSRect r) { NSBox *b = [[NSBox alloc] initWithFrame:r]; b.title = title; [v addSubview:b]; }
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _capture = -1;
    _win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 920, 640) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    _win.title = S("Controls", "操作設定", "Controles"); _win.releasedWhenClosed = NO; _win.delegate = self;
    NSView *v = _win.contentView;
    _tabs = [NSSegmentedControl segmentedControlWithLabels:@[S("Keyboard", "鍵盤", "Teclado"), S("Controller", "手把", "Mando")] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(tabChanged:)];
    _tabs.frame = NSMakeRect(310, 592, 300, 28); _tabs.selectedSegment = front_input_mode() == 1 ? 1 : 0; [v addSubview:_tabs];
    box_at(v, S("Left Stick", "左搖桿", "Palanca izquierda"), NSMakeRect(16, 300, 240, 272));
    box_at(v, S("D-Pad", "十字鍵", "Cruceta"), NSMakeRect(16, 84, 240, 208));
    box_at(v, S("Face Buttons", "按鈕", "Botones frontales"), NSMakeRect(664, 386, 240, 186));
    box_at(v, S("Right Stick", "右搖桿", "Palanca derecha"), NSMakeRect(664, 84, 240, 294));
    _art = [[DMPadArt alloc] initWithFrame:NSMakeRect(270, 90, 380, 370)]; _art.highlight = -1; [v addSubview:_art];
    for (int i = 0; i < N_CTL; i++) {
        const ctl_def *c = &k_ctl[i]; int top = c->y >= 470;   // 上排（肩鍵、− / +）的按鈕窄一點 | the top row (shoulders, − / +) uses narrower buttons
        CGFloat w = top ? 88 : BW;
        _lab[i] = text_at(v, S(c->en, c->zh, c->es), NSMakeRect(c->cx - w / 2, c->y + BH + 2, w, 16), 11, NSTextAlignmentCenter);
        _btn[i] = [NSButton buttonWithTitle:@"" target:self action:@selector(bindClicked:)];
        _btn[i].frame = NSMakeRect(c->cx - w / 2, c->y, w, BH); _btn[i].tag = i; _btn[i].bezelStyle = NSBezelStyleRounded; _btn[i].controlSize = NSControlSizeSmall;
        _btn[i].font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize]; [v addSubview:_btn[i]];
    }
    _hint = text_at(v, @"", NSMakeRect(16, 54, 888, 18), 11, NSTextAlignmentCenter); _hint.textColor = NSColor.secondaryLabelColor;
    text_at(v, S("Input devices:", "輸入裝置：", "Dispositivos de entrada:"), NSMakeRect(16, 20, 150, 18), 12, NSTextAlignmentLeft);
    _mode = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(166, 14, 250, 28) pullsDown:NO];
    [_mode addItemsWithTitles:@[S("Keyboard, mouse and controller", "鍵盤、滑鼠和手把", "Teclado, ratón y mando"), S("Controller only", "只用手把", "Solo mando"), S("Keyboard and mouse only", "只用鍵盤和滑鼠", "Solo teclado y ratón")]];
    [_mode selectItemAtIndex:front_input_mode()]; _mode.target = self; _mode.action = @selector(modeChanged:); [v addSubview:_mode];
    _status = text_at(v, @"", NSMakeRect(426, 20, 190, 18), 12, NSTextAlignmentLeft); _status.lineBreakMode = NSLineBreakByTruncatingTail;
    NSButton *reset = [NSButton buttonWithTitle:S("Restore Defaults", "恢復默認", "Restaurar predeterminados") target:self action:@selector(restore:)];
    reset.frame = NSMakeRect(620, 14, 210, 28); [v addSubview:reset];
    NSButton *done = [NSButton buttonWithTitle:S("Done", "完成", "Listo") target:_win action:@selector(performClose:)];
    done.frame = NSMakeRect(834, 14, 72, 28); done.keyEquivalent = @"\r"; [v addSubview:done];
    __weak DMControls *ws = self;
    _monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) { DMControls *s = ws; return s && e.window == s->_win ? [s key:e] : e; }];
    _timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *tm) { (void)tm; [ws refreshStatus]; }];
    [self refresh];
    return self;
}
- (void)refreshStatus {
    NSArray *n = front_pad_names();
    _status.stringValue = n.count ? [S("Controller: ", "手把：", "Mando: ") stringByAppendingString:[n componentsJoinedByString:@", "]] : S("No controller connected", "沒有接上手把", "Ningún mando conectado");
}
- (void)refresh {   // 按當前頁重寫每個按鈕的字 | retitle every button for the current page
    BOOL pad = self.padPage; NSDictionary *km = pad ? nil : key_map(YES); int map[16]; front_padmap_get(map, NULL);
    for (int i = 0; i < N_CTL; i++) {
        const ctl_def *c = &k_ctl[i]; NSString *t;
        if (i == _capture) t = pad ? S("Press a button…", "按手把上的鍵…", "Pulsa un botón…") : S("Press a key…", "按一個鍵…", "Pulsa una tecla…");
        else if (pad) t = c->sw < 0 ? S("Stick", "搖桿", "Palanca") : map[c->sw] >= 0 ? phys_label(map[c->sw]) : @"—";
        else {
            t = @"—";   // 按鍵碼順序找第一個映射到這個控制項的鍵，結果固定 | find the first key (in key-code order) bound to this control, so the result is stable
            for (int k = 0; k < 128; k++) { const char *nm = front_keyname(k); NSString *dst = nm ? km[[@"key:" stringByAppendingString:@(nm)].lowercaseString] : nil;
                if (dst && [dst caseInsensitiveCompare:@(c->target)] == NSOrderedSame) { t = key_label(nm); break; } }
        }
        _btn[i].title = t; _btn[i].enabled = !(pad && c->sw < 0);
        _btn[i].contentTintColor = i == _capture ? NSColor.controlAccentColor : nil;
    }
    _art.highlight = _capture; _art.needsDisplay = YES;
    _hint.stringValue = pad ? S("Click a button, then press the controller button you want for it. Esc cancels, ⌫ unbinds. Sticks are fixed.",
                                "點一個按鈕，再按手把上想用的鍵。Esc 取消，⌫ 解除。搖桿不能改。",
                                "Haz clic en un botón y pulsa en el mando el botón que quieras. Esc cancela, ⌫ lo deja sin asignar. Las palancas son fijas.")
                            : S("Click a button, then press the key you want for it. Esc cancels, ⌫ unbinds.",
                                "點一個按鈕，再按想用的鍵。Esc 取消，⌫ 解除。",
                                "Haz clic en un botón y pulsa la tecla que quieras. Esc cancela, ⌫ lo deja sin asignar.");
    [self refreshStatus];
}
- (void)tabChanged:(id)sender { (void)sender; _capture = -1; [self refresh]; }
- (void)modeChanged:(id)sender { (void)sender; front_input_mode_set((int)_mode.indexOfSelectedItem); }
- (void)bindClicked:(NSButton *)b { _capture = _capture == (int)b.tag ? -1 : (int)b.tag; [self refresh]; }
- (void)assignKey:(const char *)name {   // name NULL = 解除 | name NULL = unbind
    NSMutableDictionary *m = key_map(YES); NSString *target = @(k_ctl[_capture].target);
    for (NSString *k in m.allKeys) if ([m[k] caseInsensitiveCompare:target] == NSOrderedSame) [m removeObjectForKey:k];
    if (name) m[[@"key:" stringByAppendingString:@(name)].lowercaseString] = target;   // 這個鍵原來的用途被換掉 | whatever the key did before is replaced
    key_map_write(m);
}
- (void)assignPad:(int)phys {   // phys < 0 = 解除；別的 Switch 鍵正用著這個實體鍵就和它互換 | phys < 0 = unbind; if another Switch button uses this physical button, the two swap
    int map[16], sw = k_ctl[_capture].sw; front_padmap_get(map, NULL);
    if (phys >= 0) for (int s = 0; s < 16; s++) if (s != sw && map[s] == phys) map[s] = map[sw];
    map[sw] = phys; front_padmap_set(map);
}
- (NSEvent *)key:(NSEvent *)e {
    if (_capture < 0 || (e.modifierFlags & NSEventModifierFlagCommand)) return e;
    if (e.keyCode == 53) { _capture = -1; [self refresh]; return nil; }   // Esc：取消 | Esc: cancel
    if (e.keyCode == 51) { if (self.padPage) [self assignPad:-1]; else [self assignKey:NULL]; _capture = -1; [self refresh]; return nil; }   // ⌫：解除 | ⌫: unbind
    if (self.padPage) { NSBeep(); return nil; }
    const char *name = front_keyname(e.keyCode); if (!name) { NSBeep(); return nil; }
    [self assignKey:name]; _capture = -1; [self refresh]; return nil;
}
- (void)padPhys:(uint32_t)phys {
    uint32_t pressed = phys & ~_lastPhys; _lastPhys = phys;
    if (_capture < 0 || !self.padPage || !pressed || !_win.isKeyWindow) return;
    [self assignPad:__builtin_ctz(pressed)]; _capture = -1; [self refresh];
}
- (void)restore:(id)sender {
    (void)sender; _capture = -1;
    if (self.padPage) front_padmap_set(NULL); else key_map_write(key_map(NO));
    [self refresh];
}
- (void)show {
    [_mode selectItemAtIndex:front_input_mode()]; [self refresh];
    NSWindow *main = NSApp.mainWindow; if (_win.visible) {}   // 已經開著就只帶到前面 | already open: just bring it to the front
    else if (main && main != _win) { NSRect f = main.frame, w = _win.frame; [_win setFrameOrigin:NSMakePoint(NSMidX(f) - w.size.width / 2, NSMidY(f) - w.size.height / 2)]; }
    else [_win center];
    [_win makeKeyAndOrderFront:nil];
}
- (void)windowWillClose:(NSNotification *)n { (void)n; _capture = -1; }
@end

void controls_open(void) { if (!g_ctl) g_ctl = [DMControls new]; [g_ctl show]; }
void controls_pad_phys(uint32_t phys) { [g_ctl padPhys:phys]; }
