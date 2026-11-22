// Mac「Extras → 照片」窗口：遊戲內存進相簿的照片（hle_sdk20.c album::SaveScreenshot 寫的 PNG）按時間倒序排成縮略圖網格；
// 單擊選中，雙擊用預覽打開，右鍵可在 Finder 中顯示、拷貝、移到廢紙簍。相簿目錄有變動（遊戲剛存了一張）就自動刷新。
// Mac "Extras -> Photos" window: the photos the game saved to its album (PNGs written by hle_sdk20.c album::SaveScreenshot) as a thumbnail grid, newest first;
// click selects, double-click opens in Preview, and the context menu shows in Finder, copies or moves to the Trash. It refreshes by itself when the album directory changes (the game just saved one).
#import <Cocoa/Cocoa.h>
#include <fcntl.h>
#include <unistd.h>
#include "dm.h"
#include "controls_mac.h"
#include "album_mac.h"

enum { A_TITLE, A_EMPTY, A_COUNT, A_OPEN, A_FINDER, A_COPY, A_TRASH, A_FOLDER, A_N };
static const char *const k_atext[A_N][3] = {
    [A_TITLE] = {"Photos", "照片", "Fotos"},
    [A_EMPTY] = {"No photos yet.\nSave a photo in the game (for example in the Photo Studio) and it will appear here.",
                 "還沒有照片。\n在遊戲裡存一張照片（例如在照相館），就會出現在這裡。",
                 "Todavía no hay fotos.\nGuarda una foto en el juego (por ejemplo en el estudio de fotos) y aparecerá aquí."},
    [A_COUNT] = {"%lu photos", "%lu 張照片", "%lu fotos"},
    [A_OPEN] = {"Open", "打開", "Abrir"},
    [A_FINDER] = {"Show in Finder", "在 Finder 中顯示", "Mostrar en Finder"},
    [A_COPY] = {"Copy", "拷貝", "Copiar"},
    [A_TRASH] = {"Move to Trash", "移到廢紙簍", "Mover a la papelera"},
    [A_FOLDER] = {"Open Folder", "打開資料夾", "Abrir carpeta"},
};
static NSString *AT(int k) { return @(k_atext[k][front_ui_lang()]); }

static NSURL *album_url(void) { const char *d = dm_album_dir(); return d && *d ? [NSURL fileURLWithPath:@(d) isDirectory:YES] : nil; }

@interface DMFlipped : NSView
@end
@implementation DMFlipped
- (BOOL)isFlipped { return YES; }   // 網格從上往下排 | the grid runs top to bottom
@end

// ---------- 一格縮略圖 | One thumbnail cell ----------
@interface DMPhotoCell : NSView
@property (strong) NSURL *url;
@property (strong) NSImage *thumb;
@property (strong) NSString *caption;
@property BOOL selected;
@end

@interface DMAlbum : NSObject <NSWindowDelegate>
- (void)show;
- (void)reload;
- (void)select:(DMPhotoCell *)c;
- (NSMenu *)menuFor:(DMPhotoCell *)c;
@end
static DMAlbum *g_album;

@implementation DMPhotoCell
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    (void)dirty; NSRect b = self.bounds;
    if (self.selected) { [NSColor.selectedContentBackgroundColor setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 2, 2) xRadius:8 yRadius:8] fill]; }
    NSRect img = NSMakeRect(10, 10, b.size.width - 20, (b.size.width - 20) * 9 / 16);
    if (self.thumb) {
        NSSize s = self.thumb.size; CGFloat k = MIN(img.size.width / s.width, img.size.height / s.height);
        NSRect r = NSMakeRect(NSMidX(img) - s.width * k / 2, NSMidY(img) - s.height * k / 2, s.width * k, s.height * k);
        [NSGraphicsContext saveGraphicsState];
        [[NSBezierPath bezierPathWithRoundedRect:r xRadius:4 yRadius:4] addClip];
        [self.thumb drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        [NSGraphicsContext restoreGraphicsState];
    }
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.alignment = NSTextAlignmentCenter;
    NSColor *fg = self.selected ? NSColor.alternateSelectedControlTextColor : NSColor.secondaryLabelColor;
    [self.caption drawInRect:NSMakeRect(4, NSMaxY(img) + 6, b.size.width - 8, 16)
              withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:11], NSForegroundColorAttributeName: fg, NSParagraphStyleAttributeName: ps}];
}
- (void)mouseDown:(NSEvent *)e {
    [g_album select:self];
    if (e.clickCount == 2) [NSWorkspace.sharedWorkspace openURL:self.url];
}
- (NSMenu *)menuForEvent:(NSEvent *)e { (void)e; [g_album select:self]; return [g_album menuFor:self]; }
@end

// ---------- 窗口 | Window ----------
@implementation DMAlbum {
    NSWindow *_win; NSScrollView *_scroll; NSView *_grid; NSTextField *_empty, *_count;
    NSArray<NSURL *> *_urls; NSMutableArray<DMPhotoCell *> *_cells; DMPhotoCell *_sel;
    dispatch_source_t _watch; int _fd;
}
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _fd = -1; _cells = [NSMutableArray new];
    _win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 600)
                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                         backing:NSBackingStoreBuffered defer:NO];
    _win.title = AT(A_TITLE); _win.releasedWhenClosed = NO; _win.delegate = self; _win.minSize = NSMakeSize(420, 320);
    [_win setFrameAutosaveName:@"DMAlbum"];
    NSView *cv = _win.contentView;
    _scroll = [NSScrollView new]; _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.hasVerticalScroller = YES; _scroll.drawsBackground = NO; _scroll.automaticallyAdjustsContentInsets = NO;
    _grid = [[DMFlipped alloc] initWithFrame:NSZeroRect]; _scroll.documentView = _grid;
    _empty = [NSTextField wrappingLabelWithString:AT(A_EMPTY)]; _empty.alignment = NSTextAlignmentCenter; _empty.textColor = NSColor.secondaryLabelColor;
    _empty.translatesAutoresizingMaskIntoConstraints = NO;
    _count = [NSTextField labelWithString:@""]; _count.textColor = NSColor.secondaryLabelColor; _count.translatesAutoresizingMaskIntoConstraints = NO;
    NSButton *folder = [NSButton buttonWithTitle:AT(A_FOLDER) target:self action:@selector(openFolder:)]; folder.translatesAutoresizingMaskIntoConstraints = NO;
    NSBox *line = [NSBox new]; line.boxType = NSBoxSeparator; line.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *v in @[_scroll, _empty, _count, folder, line]) [cv addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [_scroll.topAnchor constraintEqualToAnchor:cv.topAnchor], [_scroll.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor], [_scroll.bottomAnchor constraintEqualToAnchor:line.topAnchor],
        [line.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor], [line.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor],
        [line.bottomAnchor constraintEqualToAnchor:folder.topAnchor constant:-10],
        [folder.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-16], [folder.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-12],
        [_count.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16], [_count.centerYAnchor constraintEqualToAnchor:folder.centerYAnchor],
        [_empty.centerXAnchor constraintEqualToAnchor:_scroll.centerXAnchor], [_empty.centerYAnchor constraintEqualToAnchor:_scroll.centerYAnchor],
        [_empty.widthAnchor constraintLessThanOrEqualToConstant:420],
    ]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(layoutGrid) name:NSViewFrameDidChangeNotification object:_scroll.contentView];
    _scroll.contentView.postsFrameChangedNotifications = YES;
    return self;
}
- (void)show {
    [self reload]; [self watch];
    if (!_win.visible) [_win center];
    [_win makeKeyAndOrderFront:nil];
}
- (void)windowWillClose:(NSNotification *)n { (void)n; [self unwatch]; }

// 相簿目錄變動 → 刷新（遊戲在玩，窗口開著時新存的照片立刻出現） | album directory changed -> reload (photos saved while the window is open show up right away)
- (void)watch {
    if (_watch) return;
    NSURL *u = album_url(); if (!u) return;
    [NSFileManager.defaultManager createDirectoryAtURL:u withIntermediateDirectories:YES attributes:nil error:nil];
    _fd = open(u.fileSystemRepresentation, O_EVTONLY); if (_fd < 0) return;
    _watch = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)_fd, DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME, dispatch_get_main_queue());
    __weak DMAlbum *w = self;
    // PNG 寫完前目錄就變了：稍等再讀 | the directory changes before the PNG is fully written: wait a moment before reading
    dispatch_source_set_event_handler(_watch, ^{ dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [w reload]; }); });
    int fd = _fd; dispatch_source_set_cancel_handler(_watch, ^{ close(fd); });
    dispatch_resume(_watch);
}
- (void)unwatch { if (_watch) { dispatch_source_cancel(_watch); _watch = nil; _fd = -1; } }

- (void)reload {
    NSURL *u = album_url();
    NSArray<NSURL *> *all = u ? [NSFileManager.defaultManager contentsOfDirectoryAtURL:u includingPropertiesForKeys:@[NSURLCreationDateKey]
                                                                               options:NSDirectoryEnumerationSkipsHiddenFiles error:nil] : @[];
    NSMutableArray<NSURL *> *png = [NSMutableArray new];
    for (NSURL *f in all) if ([f.pathExtension.lowercaseString isEqualToString:@"png"]) [png addObject:f];
    [png sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) { return [b.lastPathComponent compare:a.lastPathComponent]; }];   // 文件名帶時間戳：倒序 = 最新在前 | file names carry a timestamp: descending = newest first
    if ([png isEqualToArray:_urls ?: @[]] && _urls) return;
    NSURL *keep = _sel.url; _sel = nil; _urls = png;
    for (DMPhotoCell *c in _cells) [c removeFromSuperview];
    [_cells removeAllObjects];
    NSDateFormatter *df = [NSDateFormatter new]; df.dateStyle = NSDateFormatterMediumStyle; df.timeStyle = NSDateFormatterShortStyle;
    for (NSURL *f in png) {
        DMPhotoCell *c = [[DMPhotoCell alloc] initWithFrame:NSZeroRect]; c.url = f;
        NSDate *d = nil; [f getResourceValue:&d forKey:NSURLCreationDateKey error:nil]; c.caption = d ? [df stringFromDate:d] : f.lastPathComponent;
        [_cells addObject:c]; [_grid addSubview:c];
        if ([f isEqual:keep]) [self select:c];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{   // 縮略圖在後台解碼 | thumbnails are decoded in the background
            NSImage *full = [[NSImage alloc] initWithContentsOfURL:f]; if (!full) return;
            NSSize s = full.size; CGFloat k = MIN(1.0, 480.0 / MAX(1.0, s.width));
            NSImage *t = [NSImage imageWithSize:NSMakeSize(s.width * k, s.height * k) flipped:NO drawingHandler:^BOOL(NSRect r) { [full drawInRect:r]; return YES; }];
            dispatch_async(dispatch_get_main_queue(), ^{ c.thumb = t; c.needsDisplay = YES; });
        });
    }
    _empty.hidden = png.count > 0;
    _count.stringValue = png.count ? [NSString stringWithFormat:AT(A_COUNT), (unsigned long)png.count] : @"";
    [self layoutGrid];
}
- (void)layoutGrid {
    CGFloat W = _scroll.contentView.bounds.size.width, pad = 12, minw = 220;
    int cols = MAX(1, (int)((W - pad) / (minw + pad)));
    CGFloat cw = floor((W - pad * (cols + 1)) / cols), ch = (cw - 20) * 9 / 16 + 42;
    NSUInteger n = _cells.count, rows = (n + cols - 1) / cols;
    for (NSUInteger i = 0; i < n; i++) _cells[i].frame = NSMakeRect(pad + (i % cols) * (cw + pad), pad + (i / cols) * (ch + pad), cw, ch);
    [_grid setFrameSize:NSMakeSize(W, MAX(_scroll.contentView.bounds.size.height, pad + rows * (ch + pad)))];
}
- (void)select:(DMPhotoCell *)c {
    if (_sel == c) return;
    _sel.selected = NO; _sel.needsDisplay = YES; _sel = c; c.selected = YES; c.needsDisplay = YES;
}
- (NSMenu *)menuFor:(DMPhotoCell *)c {
    NSMenu *m = [NSMenu new];
    [m addItemWithTitle:AT(A_OPEN) action:@selector(openSel:) keyEquivalent:@""].target = self;
    [m addItemWithTitle:AT(A_FINDER) action:@selector(revealSel:) keyEquivalent:@""].target = self;
    [m addItemWithTitle:AT(A_COPY) action:@selector(copySel:) keyEquivalent:@""].target = self;
    [m addItem:NSMenuItem.separatorItem];
    [m addItemWithTitle:AT(A_TRASH) action:@selector(trashSel:) keyEquivalent:@""].target = self;
    (void)c; return m;
}
- (void)openSel:(id)s { (void)s; if (_sel) [NSWorkspace.sharedWorkspace openURL:_sel.url]; }
- (void)revealSel:(id)s { (void)s; if (_sel) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[_sel.url]]; }
- (void)copySel:(id)s {
    (void)s; if (!_sel) return;
    NSImage *im = [[NSImage alloc] initWithContentsOfURL:_sel.url];
    [NSPasteboard.generalPasteboard clearContents]; [NSPasteboard.generalPasteboard writeObjects:im ? @[_sel.url, im] : @[_sel.url]];
}
- (void)trashSel:(id)s { (void)s; if (_sel) { [NSFileManager.defaultManager trashItemAtURL:_sel.url resultingItemURL:nil error:nil]; [self reload]; } }
- (void)openFolder:(id)s {
    (void)s; NSURL *u = album_url(); if (!u) return;
    [NSFileManager.defaultManager createDirectoryAtURL:u withIntermediateDirectories:YES attributes:nil error:nil];
    [NSWorkspace.sharedWorkspace openURL:u];
}
@end

void album_open(void) { if (!g_album) g_album = [DMAlbum new]; [g_album show]; }
void album_show_folder(void) { if (!g_album) g_album = [DMAlbum new]; [g_album openFolder:nil]; }
const char *album_title(int which) { return k_atext[which ? A_FOLDER : A_TITLE][front_ui_lang()]; }
