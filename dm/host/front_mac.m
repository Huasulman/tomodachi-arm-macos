// Mac 前端：DM_WINDOW=1 時開窗口（CAMetalLayer，供圖形後端出圖）+ 鍵盤 → 映射層（dm_bind.h）→ dm_input；客體改在大棧線程上跑，主線程歸 AppKit。
// 不開 DM_WINDOW：客體直接在當前線程跑，行為與無前端時相同（無窗口測試用這個）。
// 默認鍵位（任天堂佈局）：WASD 左搖桿、P / L ; ' 右搖桿（上 / 左 下 右）、方向鍵十字鍵、J=A K=B U=X I=Y、Q=L E=R、Z=ZL C=ZR、F=按左搖桿 G=按右搖桿、回車=+ Tab=−。
// 鼠標與觸控板（默認）：在畫面上點一下鎖定鼠標（光標藏起、不再移動），之後移動鼠標 = 左搖桿（推遊戲裡的小手 / 指針）、左鍵 A、右鍵 B、中鍵 X；按 ⌘（或沒映射時的 Esc）、
//   窗口失焦、彈輸入框都會放開。沒鎖定時鼠標只歸系統（標題欄、拖窗口），這樣遊戲裡的小手就是唯一的指針，不會和系統光標錯開。
//   雙指滾動（或滾輪）= 右搖桿（轉鏡頭）、雙指旋轉 = 右搖桿左右、雙指捏合 = ZL / 張開 = ZR、三指左右滑 = L / R。左鍵改成 Pointer 就是在鼠標處觸屏（拖動跟著走，不鎖定），給吃觸屏的遊戲用。
//   左鍵的默認由遊戲檔案定（game.tsv mouse_left，缺省 A）：朋友收集默認 Pointer。
// 改鍵：DM_KEYMAP=<文件>（缺省 $DM_ROOT/keymap.txt），每行「來源 <Switch 控制項>」，逐條覆蓋默認表；來源 key:<鍵名>（見 k_keyname，按美式鍵盤的鍵位，不隨輸入法變）、
//   mouse:Left / Right / Other / Move、trackpad:Scroll / Rotate、pinch:In / Out、swipe:Left / Right / Up / Down。表文件改過後，窗口回到前台時自動重讀。
// 窗口與菜單（Mac 原生）：標題欄三個按鈕都能用（關 = 退出前確認、縮到最小 = 掛起、綠鈕 = 全屏）；全屏或窗口比例不是畫面比例（缺省 16:9；DM_ASPECT / 設定 GameAspect 可改，見 dm_aspect.h）時畫面按比例居中、兩邊補黑；
//   菜單有 關於 / 編輯按鍵 / 隱藏 / 退出，編輯（輸入框裡拷貝粘貼用），遊戲（暫停、截圖、存檔文件夾、遊戲語言），顯示方式（三檔窗口大小、全屏），窗口，輔助說明（操作方式、日誌）。
//   界面文字按系統首選語言出英文或繁體中文（k_text；任何一種中文都用繁體）。
// Mac front end: with DM_WINDOW=1 open a window (CAMetalLayer, for the graphics backend to present frames) + keyboard → mapping layer (dm_bind.h) → dm_input; the guest runs on a large-stack thread instead and the main thread belongs to AppKit.
// Without DM_WINDOW: the guest runs directly on the current thread, behaving the same as with no front end (windowless tests use this).
// Default keys (Nintendo layout): WASD left stick, P / L ; ' right stick (up / left down right), arrow keys D-pad, J=A K=B U=X I=Y, Q=L E=R, Z=ZL C=ZR, F=press left stick G=press right stick, Return=+ Tab=−.
// Mouse and trackpad (defaults): a click on the picture captures the mouse (the cursor is hidden and stops moving), after which moving the mouse = left stick (moves the game's hand / pointer), left button A, right button B, middle X; pressing ⌘ (or Esc when it is unmapped),
//   the window losing focus or a text box appearing releases it. While not captured the mouse belongs to the system only (title bar, dragging the window), so the game's hand is the only pointer and cannot drift away from the system cursor.
//   Two-finger scroll (or the wheel) = right stick (turns the camera), two-finger rotate = right stick left / right, pinch in = ZL / out = ZR, three-finger swipe left / right = L / R. Mapping the left button to Pointer instead touches the screen where the mouse is (following drags, no capture), for games that take touch.
//   The left button's default comes from the game profile (game.tsv mouse_left, A by default): Tomodachi Life defaults to Pointer.
// Remapping: DM_KEYMAP=<file> (default $DM_ROOT/keymap.txt), one line per source "source <Switch control>", overriding the default table entry by entry; sources key:<key name> (see k_keyname, by US keyboard position, independent of the input method),
//   mouse:Left / Right / Other / Move, trackpad:Scroll / Rotate, pinch:In / Out, swipe:Left / Right / Up / Down. After the file changes it is reread automatically when the window comes back to the front.
// Window and menus (native Mac): all three title bar buttons work (close = confirm before quitting, minimize = suspend, green = full screen); in full screen or at a window shape other than the picture's (16:9 by default; DM_ASPECT / the GameAspect setting can change it, see dm_aspect.h) the picture is centred at its own aspect with black bars;
//   the menus hold About / Edit Controls / Hide / Quit, Edit (copy and paste in the text box), Game (pause, screenshot, save folder, game language), View (three window sizes, full screen), Window, Help (controls, log).
//   Interface text follows the system's preferred language: English or Traditional Chinese (k_text; any Chinese gets Traditional).
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <GameController/GameController.h>
#import <IOUSBHost/IOUSBHost.h>
#include <os/lock.h>
#include "dm.h"
#include "dm_input.h"
#include "dm_padmap.h"
#include "dm_bind.h"
#include "dm_uiscreen.h"
#include "dm_aspect.h"
#include "controls_mac.h"
#include "album_mac.h"
void mtl_set_ui_rect_fn(void (*fn)(double *y, double *h));
static void ui_rect_frac(double *fy, double *fh) { int x, y, w, h, rw = 0, rh = 0; dm_ui_rect(&x, &y, &w, &h); if (dm_screen_real(&rw, &rh) && rh > 0) { *fy = (double)y / rh; *fh = (double)h / rh; } }   // 同 front_ios.m：界面矩形的縱向位置與高（佔畫面高的比例） | Same as front_ios.m: vertical position and height of the UI rectangle (as fractions of the frame height)
__attribute__((constructor)) static void ui_shift_reg(void) { mtl_set_ui_rect_fn(ui_rect_frac); }   // 不開窗口的跑法（截圖 / 閘門）也要生效，所以不放在建圖層那裡 | Must also take effect when running without a window (screenshots / gate checks), so it is not placed where the layer is created
#include "front.h"
#include "hle.h"
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
void dm_gfx_shot_at(long k, const char *path);   // nvn_mtl.m：k 次上屏後把遊戲畫面（原分辨率）存成 PNG | nvn_mtl.m: after k presents, save the game picture (native resolution) as PNG

static CAMetalLayer *g_layer;
static NSWindow *g_win;
static NSView *g_view;            // 內容視圖：黑底，遊戲圖層按畫面形狀居中掛在上面 | content view: black, the game layer sits centred on it at the picture's shape
static int g_captured, g_paused;  // 鼠標已鎖定 / 已暫停（只在主線程讀寫） | mouse captured / paused (main thread only)

void *front_metal_layer(void) { return (__bridge void *)g_layer; }
// 畫面寬高比（dm_aspect.h）：環境變量 DM_ASPECT 優先，其次本 App 的設定 GameAspect（defaults write 寫）；「screen」= 主顯示器的形狀。
// 啓動時定一次（任意線程先問到都行：CGDisplayBounds 不要求主線程），之後窗口形狀、畫面位置、給遊戲的輸出分辨率都按它
// Picture aspect ratio (dm_aspect.h): the environment variable DM_ASPECT first, then this app's setting GameAspect (written with defaults write); "screen" = the main display's shape.
// Decided once at launch (whichever thread asks first: CGDisplayBounds does not need the main thread); the window shape, the picture placement and the output resolution given to the game all follow it from then on
static double game_aspect(void) {
    static double a; static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *e = getenv("DM_ASPECT"); NSString *pref = e ? nil : [NSUserDefaults.standardUserDefaults stringForKey:@"GameAspect"];
        CGRect sb = CGDisplayBounds(CGMainDisplayID());
        a = dm_aspect_parse(e ? e : pref.UTF8String, sb.size.height > 0 ? sb.size.width / sb.size.height : 0);
        if (e || pref) LOG("前端：畫面寬高比「%s」→ %.4f", e ? e : pref.UTF8String, a);
    });
    return a;
}
// 遊戲檔案的 16:9 尺寸按畫面寬高比改形狀（寬的同高放寬、高的同寬加高；DM_ASPECT 沒給 = 原值，行為不變）；DM_GAME_RES=寬x高（主機模式，掌機按 720/900 同比）只供與 iOS 寬屏對拍
// The game profile's 16:9 sizes reshaped for the picture aspect ratio (wider ones widen at the same height, taller ones grow taller at the same width; no DM_ASPECT = the original values, behaviour unchanged); DM_GAME_RES=<width>x<height> (docked mode; handheld scaled by 720/900) is only for side-by-side comparison with iOS widescreen
uint64_t front_game_res(int docked) {
    unsigned w, h; const char *e = getenv("DM_GAME_RES");
    if (e && sscanf(e, "%ux%u", &w, &h) == 2) return docked ? (uint64_t)h << 32 | w : (uint64_t)(h * 4 / 5) << 32 | (w * 4 / 5 + 3) / 4 * 4;
    return dm_aspect_game_res(docked, game_aspect());
}
static NSSize picture_size(void) { uint64_t r = front_game_res(1); return NSMakeSize((uint32_t)r, (uint32_t)(r >> 32)); }   // 遊戲輸出的形狀（寬、高） | the shape of the game's output (width, height)

// ---------- 界面文字（英文 / 繁體中文 / 西班牙文，按系統首選語言） | Interface text (English / Traditional Chinese / Spanish, by the system's preferred language) ----------
enum { T_ABOUT, T_EDIT_CONTROLS, T_HIDE, T_HIDE_OTHERS, T_SHOW_ALL, T_QUIT, T_EDIT, T_UNDO, T_REDO, T_CUT, T_COPY, T_PASTE, T_SELECT_ALL,
       T_GAME, T_PAUSE, T_RESUME, T_SHOT, T_SAVES, T_VIEW, T_FULL, T_WINDOW, T_MIN, T_ZOOM, T_FRONT, T_HELP, T_CONTROLS, T_LOG,
       T_HINT_CLICK, T_HINT_CMD, T_PAUSED, T_QUIT_Q, T_QUIT_INFO, T_QUIT_OK, T_OK, T_CANCEL, T_INPUT, T_SHOT_SAVED,
       T_SAVE_FAIL, T_SAVE_SPACE, T_SAVE_OTHER, T_CONTROLS_MOUSE, T_CONTROLS_TAP, T_CONTROLS_BODY, T_LANG, T_LANG_SYS, T_LANG_NEXT, T_FPS, T_FPS_NEXT, T_FPS_SLOW, T_UPSCALE,
       T_DEVICES, T_DIAG, T_DIAG_DONE, T_EXTRAS, T_HANDHELD, T_SHOWFPS, T_N };
static const char *const k_text[T_N][3] = {
    [T_ABOUT] = {"About %@", "關於「%@」", "Acerca de %@"},
    [T_EDIT_CONTROLS] = {"Edit Controls…", "編輯按鍵…", "Controles…"},
    [T_HIDE] = {"Hide %@", "隱藏「%@」", "Ocultar %@"},
    [T_HIDE_OTHERS] = {"Hide Others", "隱藏其他", "Ocultar otros"},
    [T_SHOW_ALL] = {"Show All", "顯示全部", "Mostrar todo"},
    [T_QUIT] = {"Quit %@", "結束「%@」", "Salir de %@"},
    [T_EDIT] = {"Edit", "編輯", "Edición"}, [T_UNDO] = {"Undo", "還原", "Deshacer"}, [T_REDO] = {"Redo", "重做", "Rehacer"},
    [T_CUT] = {"Cut", "剪下", "Cortar"}, [T_COPY] = {"Copy", "拷貝", "Copiar"}, [T_PASTE] = {"Paste", "貼上", "Pegar"}, [T_SELECT_ALL] = {"Select All", "全選", "Seleccionar todo"},
    [T_GAME] = {"Game", "遊戲", "Juego"}, [T_PAUSE] = {"Pause", "暫停", "Pausa"}, [T_RESUME] = {"Resume", "繼續", "Continuar"},
    [T_SHOT] = {"Take Screenshot", "截圖", "Hacer captura"}, [T_SAVES] = {"Show Saves in Finder", "在 Finder 中顯示存檔", "Mostrar partidas en Finder"},
    [T_VIEW] = {"View", "顯示方式", "Visualización"}, [T_FULL] = {"Enter Full Screen", "進入全螢幕", "Pantalla completa"},
    [T_WINDOW] = {"Window", "視窗", "Ventana"}, [T_MIN] = {"Minimize", "縮到最小", "Minimizar"}, [T_ZOOM] = {"Zoom", "縮放", "Zoom"},
    [T_FRONT] = {"Bring All to Front", "將全部視窗移至最前", "Traer todo al frente"},
    [T_HELP] = {"Help", "輔助說明", "Ayuda"}, [T_CONTROLS] = {"Controls", "操作方式", "Cómo se juega"}, [T_LOG] = {"Show Log in Finder", "在 Finder 中顯示記錄檔", "Mostrar registro en Finder"},
    [T_HINT_CLICK] = {"Click the game to control it with the mouse", "點一下畫面即可用滑鼠操作", "Haz clic en el juego para controlarlo con el ratón"},
    [T_HINT_CMD] = {"Press ⌘ to release the mouse", "按 ⌘ 鍵放開滑鼠", "Pulsa ⌘ para soltar el ratón"},
    [T_PAUSED] = {"Paused", "已暫停", "En pausa"},
    [T_QUIT_Q] = {"Quit %@?", "要結束「%@」嗎？", "¿Salir de %@?"},
    [T_QUIT_INFO] = {"Progress since your last save will be lost.", "上次存檔之後的進度會遺失。", "Se perderá el progreso desde la última vez que guardaste."},
    [T_QUIT_OK] = {"Quit", "結束", "Salir"}, [T_OK] = {"OK", "確定", "Aceptar"}, [T_CANCEL] = {"Cancel", "取消", "Cancelar"},
    [T_INPUT] = {"Enter Text", "輸入文字", "Escribir texto"},
    [T_SHOT_SAVED] = {"Screenshot saved to %@", "截圖已存到「%@」", "Captura guardada en %@"},
    [T_SAVE_FAIL] = {"Progress wasn't saved", "進度沒有存到", "No se guardó el progreso"},
    [T_SAVE_SPACE] = {"Your Mac is out of storage space. Free up some space and the game will write it the next time it saves.", "Mac 的儲存空間不足。清出一些空間後，遊戲下次存檔時會再寫入。", "Tu Mac no tiene espacio suficiente. Libera espacio y el juego lo guardará la próxima vez."},
    [T_SAVE_OTHER] = {"The save file couldn't be written (error %d). The game will try again the next time it saves.", "存檔寫不進去（錯誤 %d）。遊戲下次存檔時會再試。", "No se pudo escribir la partida (error %d). El juego lo volverá a intentar la próxima vez que guarde."},
    [T_LANG] = {"Game Language", "遊戲語言", "Idioma del juego"}, [T_LANG_SYS] = {"Same as Mac", "跟隨 Mac", "Igual que el Mac"},
    [T_LANG_NEXT] = {"The game switches to %@ the next time you open it.", "下次開啟遊戲時會換成%@。", "El juego cambiará a %@ la próxima vez que lo abras."},
    [T_FPS] = {"Frame Rate", "幀率", "Fotogramas por segundo"}, [T_FPS_NEXT] = {"The game switches to %d FPS the next time you open it.", "下次開啟遊戲時會改成 %d FPS。", "El juego pasará a %d FPS la próxima vez que lo abras."},
    [T_FPS_SLOW] = {"Busy 3D scenes may run below 60 FPS.", "比較複雜的 3D 場景可能跑不滿 60 FPS。", "Las escenas 3D más cargadas pueden ir por debajo de 60 FPS."},
    [T_UPSCALE] = {"MetalFX Upscaling", "MetalFX 放大", "Escalado MetalFX"},
    [T_DEVICES] = {"Input Devices…", "輸入裝置…", "Dispositivos de entrada…"},
    [T_DIAG] = {"Capture Graphics Diagnostics", "抓圖形診斷", "Capturar diagnóstico gráfico"},
    [T_DIAG_DONE] = {"Graphics diagnostics saved", "圖形診斷已存好", "Diagnóstico gráfico guardado"},
    [T_EXTRAS] = {"Extras", "額外", "Extras"},
    [T_SHOWFPS] = {"Show FPS Counter", "顯示幀率", "Mostrar contador de FPS"},
    [T_HANDHELD] = {"Handheld Mode (720p, smoother)", "掌機模式（720p，較流暢）", "Modo portátil (720p, más fluido)"},
    // 操作方式的滑鼠那行按左鍵現在的映射選（Pointer = 點哪觸屏哪，否則鎖定推小手），後面接共用的 T_CONTROLS_BODY
    // The mouse line of Controls is picked by the left button's current mapping (Pointer = touch where clicked, otherwise capture and push the hand), followed by the shared T_CONTROLS_BODY
    [T_CONTROLS_MOUSE] = {"Mouse: click the game, then move the mouse to move the hand. Left button A, right button B. Press ⌘ to release the mouse.\n",
        "滑鼠：先點一下畫面，移動滑鼠就是移動遊戲裡的小手；左鍵 A、右鍵 B。按 ⌘ 鍵放開滑鼠。\n", "Ratón: haz clic en el juego y mueve el ratón para mover la mano. Botón izquierdo A, derecho B. Pulsa ⌘ para soltar el ratón.\n"},
    [T_CONTROLS_TAP] = {"Mouse: click anywhere to tap the screen there. Right button B.\n", "滑鼠：點畫面上的哪裡，就像用手指點那裡；右鍵 B。\n", "Ratón: haz clic donde quieras tocar la pantalla. Botón derecho B.\n"},
    [T_CONTROLS_BODY] = {"Trackpad: two-finger swipe turns the camera. Pinch in for ZL, out for ZR. Three-finger swipe left or right for L / R.\n"
        "Keyboard: W A S D move, P L ; ' turn the camera, J K U I are A B X Y, Q E are L R, Z C are ZL ZR, arrow keys are the D-pad, Return is +, Tab is −.\n"
        "Change any of these with Edit Controls….",
        "觸控板：雙指滑動轉鏡頭，捏合 ZL、張開 ZR，三指左右滑 L / R。\n"
        "鍵盤：W A S D 移動，P L ; ' 轉鏡頭，J K U I 是 A B X Y，Q E 是 L R，Z C 是 ZL ZR，方向鍵是十字鍵，Return 是 +，Tab 是 −。\n"
        "這些都能在「編輯按鍵…」裡改。", "Trackpad: desliza con dos dedos para girar la cámara. Pellizca para ZL, separa para ZR. Desliza con tres dedos a izquierda o derecha para L / R.\n"
        "Teclado: W A S D mueven, P L Ñ ´ giran la cámara, J K U I son A B X Y, Q E son L R, Z C son ZL ZR, las flechas son la cruceta, Retorno es +, Tab es −.\n"
        "Puedes cambiar los controles del teclado y del mando en Juego → Dispositivos de entrada…"},
};
static int ui_lang(void) {   // 0 英文、1 繁體中文（系統首選任何一種中文都用繁體）、2 西班牙文 | 0 English, 1 Traditional Chinese (any Chinese as the system's preferred language gets Traditional), 2 Spanish
    static int l = -1; if (l >= 0) return l;
    NSString *p = NSLocale.preferredLanguages.firstObject ?: @"en";
    return l = [p hasPrefix:@"zh"] || [p hasPrefix:@"yue"] ? 1 : [p hasPrefix:@"es"] ? 2 : 0;
}
int front_ui_lang(void) { return ui_lang(); }
static NSString *T(int id) { return @(k_text[id][ui_lang()]); }
static NSString *app_name(void) {
    NSString *n = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"];   // 取在地化的值（InfoPlist.strings 裡的完整名稱） | the localized value (the full name in InfoPlist.strings)
    return n.length ? n : @DM_GAME_NAME;   // 不在 App 裡跑（終端直接起 dmhost）時用遊戲檔案的 name | outside an app (dmhost started from a terminal) use the game profile's name
}
static NSString *app_short(void) {   // 選單項用的短名（CFBundleName，冒號前那段） | the short name for menu items (CFBundleName, the part before the colon)
    NSString *n = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"];
    return n.length ? n : app_name();
}

// Mac 虛擬鍵碼 → 鍵名（美式鍵位；修飾鍵不發按下 / 抬起事件，不列） | Mac virtual key code → key name (US positions; modifier keys send no down / up events and are not listed)
static const char *const k_keyname[128] = {
    [0] = "A", [1] = "S", [2] = "D", [3] = "F", [4] = "H", [5] = "G", [6] = "Z", [7] = "X", [8] = "C", [9] = "V", [11] = "B", [12] = "Q", [13] = "W", [14] = "E",
    [15] = "R", [16] = "Y", [17] = "T", [18] = "1", [19] = "2", [20] = "3", [21] = "4", [22] = "6", [23] = "5", [24] = "Equal", [25] = "9", [26] = "7", [27] = "Minus",
    [28] = "8", [29] = "0", [30] = "RightBracket", [31] = "O", [32] = "U", [33] = "LeftBracket", [34] = "I", [35] = "P", [36] = "Return", [37] = "L", [38] = "J",
    [39] = "Quote", [40] = "K", [41] = "Semicolon", [42] = "Backslash", [43] = "Comma", [44] = "Slash", [45] = "N", [46] = "M", [47] = "Period", [48] = "Tab",
    [49] = "Space", [50] = "Grave", [51] = "Delete", [53] = "Escape", [123] = "Left", [124] = "Right", [125] = "Down", [126] = "Up",
};
enum { KC_ESCAPE = 53 };
static const char k_default_map[] =
    "key:W StickLUp\nkey:A StickLLeft\nkey:S StickLDown\nkey:D StickLRight\n"
    "key:P StickRUp\nkey:L StickRLeft\nkey:Semicolon StickRDown\nkey:Quote StickRRight\n"
    "key:Up Up\nkey:Left Left\nkey:Down Down\nkey:Right Right\n"
    "key:J A\nkey:K B\nkey:U X\nkey:I Y\nkey:Q L\nkey:E R\nkey:Z ZL\nkey:C ZR\n"
    "key:F LS\nkey:G RS\nkey:Return Plus\nkey:Tab Minus\n"
    "mouse:Left " DM_GAME_MOUSE_LEFT "\nmouse:Right B\nmouse:Other X\nmouse:Move StickL\n"   // 左鍵默認按遊戲檔案（game.tsv mouse_left：A 或 Pointer） | the left button's default comes from the game profile (game.tsv mouse_left: A or Pointer)
    "trackpad:Scroll StickR\ntrackpad:Rotate StickR\npinch:In ZL\npinch:Out ZR\nswipe:Left L\nswipe:Right R\n";
static int g_keyrow[128];   // 鍵碼 → 映射表條目號（讀表後查一次） | key code → table entry (looked up once after loading)
// 鼠標 / 觸控板來源的條目號 | table entries of the mouse / trackpad sources
enum { MB_LEFT, MB_RIGHT, MB_OTHER, MB_N };
enum { AN_MOVE, AN_SCROLL, AN_ROTATE, AN_N };                     // 連續量：累積後由 60 Hz 定時器換成搖桿推量 | continuous inputs: accumulated, turned into stick tilt by a 60 Hz timer
enum { PU_PINCH_IN, PU_PINCH_OUT, PU_SWIPE_L, PU_SWIPE_R, PU_SWIPE_U, PU_SWIPE_D, PU_N };   // 脈衝：按一下，停手 0.12 s 後放開 | pulses: pressed, released 0.12 s after the gesture stops
static int g_mbrow[MB_N], g_anrow[AN_N], g_purow[PU_N];
static float g_an_acc[AN_N][2], g_an_val[AN_N][2];
static double g_pu_until[PU_N];
// 每格（1/60 s）累積多少算推滿：鼠標約 17 點、滾動約 25 點、旋轉約 4 度 | how much accumulation per tick (1/60 s) is full tilt: mouse about 17 points, scroll about 25 points, rotation about 4 degrees
static const float k_an_gain[AN_N] = {0.06f, 0.04f, 0.25f};
static char g_keymap_path[1024]; static struct timespec g_keymap_mtime;   // 表文件與讀入時的修改時間（回到前台時比對，改過就重讀） | the table file and its modification time when read (compared on returning to the front; reread if changed)
static void keymap_load(void) {
    const char *p = getenv("DM_KEYMAP"), *root = getenv("DM_ROOT");
    if (p) snprintf(g_keymap_path, sizeof g_keymap_path, "%s", p); else if (root) snprintf(g_keymap_path, sizeof g_keymap_path, "%s/keymap.txt", root);
    struct stat st; g_keymap_mtime = g_keymap_path[0] && !stat(g_keymap_path, &st) ? st.st_mtimespec : (struct timespec){0};
    dm_bind_load(k_default_map, g_keymap_path[0] ? g_keymap_path : NULL);
    for (int c = 0; c < 128; c++) { char src[48]; g_keyrow[c] = k_keyname[c] ? (snprintf(src, sizeof src, "key:%s", k_keyname[c]), dm_bind_find(src)) : -1; }
    static const char *const mb[MB_N] = {"mouse:Left", "mouse:Right", "mouse:Other"}, *const an[AN_N] = {"mouse:Move", "trackpad:Scroll", "trackpad:Rotate"},
        *const pu[PU_N] = {"pinch:In", "pinch:Out", "swipe:Left", "swipe:Right", "swipe:Up", "swipe:Down"};
    for (int i = 0; i < MB_N; i++) g_mbrow[i] = dm_bind_find(mb[i]);
    for (int i = 0; i < AN_N; i++) g_anrow[i] = dm_bind_find(an[i]);
    for (int i = 0; i < PU_N; i++) g_purow[i] = dm_bind_find(pu[i]);
}
static int keymap_changed(void) {
    struct stat st; if (!g_keymap_path[0] || stat(g_keymap_path, &st)) return 0;
    return st.st_mtimespec.tv_sec != g_keymap_mtime.tv_sec || st.st_mtimespec.tv_nsec != g_keymap_mtime.tv_nsec;
}
static void an_add(int k, float x, float y) { if (g_anrow[k] >= 0) { g_an_acc[k][0] += x; g_an_acc[k][1] += y; } }
static void pulse(int k) {
    if (g_purow[k] < 0) return;
    if (!g_pu_until[k]) { dm_bind_press(g_purow[k], 1); dm_bind_publish(dm_input_set); }
    g_pu_until[k] = CACurrentMediaTime() + 0.12;
}
// 60 Hz：連續量換成搖桿推量（向本格目標靠一半，停手後約 0.1 s 回中）、到時放開脈衝
// 60 Hz: turn continuous inputs into stick tilt (half way toward this tick's target; back to center about 0.1 s after the hand stops) and release expired pulses
static void input_tick(void) {
    int changed = 0; double now = CACurrentMediaTime();
    for (int k = 0; k < AN_N; k++) {
        if (g_anrow[k] < 0) continue;
        for (int a = 0; a < 2; a++) {
            float t = g_an_acc[k][a] * k_an_gain[k]; t = t > 1 ? 1 : t < -1 ? -1 : t;
            float v = g_an_val[k][a] * 0.5f + t * 0.5f; if (fabsf(v) < 0.02f) v = 0;
            if (v != g_an_val[k][a]) { g_an_val[k][a] = v; changed = 1; }
            g_an_acc[k][a] = 0;
        }
        if (changed) dm_bind_analog(g_anrow[k], g_an_val[k][0], g_an_val[k][1]);
    }
    for (int k = 0; k < PU_N; k++) if (g_pu_until[k] && now >= g_pu_until[k]) { g_pu_until[k] = 0; dm_bind_press(g_purow[k], 0); changed = 1; }
    if (changed) dm_bind_publish(dm_input_set);
}
// 輸入裝置（遊戲 → 輸入裝置）：0 鍵盤滑鼠和手把都收、1 只收手把、2 只收鍵盤滑鼠；記在 defaults 的 InputMode，切換立即生效
// Input devices (Game → Input Devices): 0 keyboard, mouse and controller, 1 controller only, 2 keyboard and mouse only; kept as InputMode in the defaults, switching applies at once
static int input_mode(void) { int m = (int)[NSUserDefaults.standardUserDefaults integerForKey:@"InputMode"]; return m >= 0 && m <= 2 ? m : 0; }
static int kbd_on(void) { return input_mode() != 1; }
static int pad_on(void) { return input_mode() != 2; }
static void input_release_all(void) {
    dm_bind_reset(); memset(g_an_acc, 0, sizeof g_an_acc); memset(g_an_val, 0, sizeof g_an_val); memset(g_pu_until, 0, sizeof g_pu_until);
    dm_bind_publish(dm_input_set); dm_touch_set(NULL, 0);
    dm_pad_set(0, 0, 0, 0, 0);   // 失焦後系統不再送手柄事件，按著的鍵不會收到「鬆開」 | once focus is lost the system stops sending controller events, so a held button would never see its release
}

// ---------- 實體手柄（GameController）| Physical controllers (GameController) ----------
// 走 dm_pad_set，與鍵盤 / 鼠標（dm_input_set）按位或，不經鍵位表。面鍵按鍵帽上的字母對應（dm_padmap.h：Xbox / PS 下方鍵 = A，任天堂手柄照 Switch 原樣）。
//   多個手柄同時接上時合併成一個；只在窗口在前台時收到事件（系統的缺省）。
// Goes through dm_pad_set, ORed with keyboard / mouse (dm_input_set), bypassing the keymap. Face buttons map by the letter on the glyph (dm_padmap.h: on Xbox / PS the bottom button = A, Nintendo controllers as on the Switch).
//   Several connected controllers merge into one; events arrive only while the window is in front (the system default).
static int32_t pad_axis(float v) { return (int32_t)lrintf(fmaxf(-1.f, fminf(1.f, v)) * DM_STICK_MAX); }

// XInput 手柄（Xbox 360 USB 協議：接口類 255 / 子類 93 / 協議 1）：macOS 沒有這類的驅動，GameController 看不到（如 GameSir 等的 2.4G 接收器）。
//   用戶態 IOUSBHost 直接開接口、從中斷端點讀 20 字節的報告：[2] 十字鍵 上下左右、Start、Back、L3、R3，[3] LB、RB、Guide、-、A、B、X、Y，[4] [5] LT RT，[6..13] 四軸 int16（上為正）。
//   鍵帽是 Xbox 佈局，面鍵按 dm_padmap 的 Xbox 對應。報告在完成回調（自己的隊列）裡解析，存進 g_xin，再回主線程由 pads_read 合併。
// XInput controllers (Xbox 360 USB protocol: interface class 255 / subclass 93 / protocol 1): macOS has no driver for this class, so GameController cannot see them (for example GameSir's 2.4G receivers).
//   The interface is opened from user space with IOUSBHost and 20-byte reports are read from the interrupt endpoint: [2] D-pad up down left right, Start, Back, L3, R3, [3] LB, RB, Guide, -, A, B, X, Y, [4] [5] LT RT, [6..13] four int16 axes (up positive).
//   The glyphs are the Xbox layout, so the face buttons use dm_padmap's Xbox mapping. Reports are parsed in the completion handler (on its own queue), stored in g_xin, and merged by pads_read back on the main thread.
#define XIN_MAX 4
static struct { IOUSBHostInterface *itf; IOUSBHostPipe *pipe; NSMutableData *buf; NSString *name; uint32_t phys; int32_t ax[4]; } g_xin[XIN_MAX];
static os_unfair_lock g_xin_lock = OS_UNFAIR_LOCK_INIT;
static dispatch_queue_t g_xin_q;
static void pads_read(void);
static void xin_parse(int i, const uint8_t *r, NSUInteger n) {
    if (n < 14 || r[0] != 0 || r[1] < 14) return;   // 只認輸入報告（類型 0） | input reports (type 0) only
    uint8_t b0 = r[2], b1 = r[3]; uint32_t m = 0;
    static const struct { int byte, bit, to; } k[] = {
        {0, 0, P_UP}, {0, 1, P_DOWN}, {0, 2, P_LEFT}, {0, 3, P_RIGHT}, {0, 4, P_START}, {0, 5, P_BACK}, {0, 6, P_LS}, {0, 7, P_RS},
        {1, 0, P_LB}, {1, 1, P_RB}, {1, 4, P_SOUTH}, {1, 5, P_EAST}, {1, 6, P_WEST}, {1, 7, P_NORTH}};
    for (unsigned j = 0; j < sizeof k / sizeof *k; j++) if (((k[j].byte ? b1 : b0) >> k[j].bit) & 1) m |= 1u << k[j].to;
    if (r[4] > 64) m |= 1u << P_LT;   // 扳機是模擬量，過四分之一算按下 | the triggers are analogue; past a quarter counts as pressed
    if (r[5] > 64) m |= 1u << P_RT;
    int32_t ax[4];
    for (int a = 0; a < 4; a++) { int v = (int16_t)(r[6 + 2 * a] | r[7 + 2 * a] << 8); ax[a] = abs(v) < 4000 ? 0 : v < -DM_STICK_MAX ? -DM_STICK_MAX : v; }   // 小死區，-32768 夾到 -32767 | small dead zone, -32768 clamped to -32767
    os_unfair_lock_lock(&g_xin_lock); g_xin[i].phys = m; memcpy(g_xin[i].ax, ax, sizeof ax); os_unfair_lock_unlock(&g_xin_lock);
    dispatch_async(dispatch_get_main_queue(), ^{ pads_read(); });
}
static void xin_drop(int i) {   // 拔掉或讀失敗：關接口、清狀態（在 g_xin_q 上） | unplugged or a read failed: close the interface and clear the state (on g_xin_q)
    if (!g_xin[i].itf) return;
    LOG("前端：XInput 手柄 %s 已斷開", g_xin[i].name.UTF8String);
    [g_xin[i].itf destroy];
    os_unfair_lock_lock(&g_xin_lock); g_xin[i].itf = nil; g_xin[i].pipe = nil; g_xin[i].buf = nil; g_xin[i].name = nil; g_xin[i].phys = 0; memset(g_xin[i].ax, 0, sizeof g_xin[i].ax); os_unfair_lock_unlock(&g_xin_lock);
    dispatch_async(dispatch_get_main_queue(), ^{ pads_read(); });
}
static void xin_next(int i) {   // 掛下一個讀請求；中斷端點不支持超時，給 0 | queue the next read; interrupt endpoints do not support timeouts, so 0
    IOUSBHostPipe *p = g_xin[i].pipe; NSMutableData *b = g_xin[i].buf; NSError *e = nil;
    if (!p || ![p enqueueIORequestWithData:b completionTimeout:0 error:&e completionHandler:^(IOReturn st, NSUInteger n) {
            if (st != kIOReturnSuccess) { xin_drop(i); return; }
            xin_parse(i, b.bytes, n); xin_next(i);
        }]) xin_drop(i);
}
static void xin_open(io_service_t svc) {   // 在 g_xin_q 上 | on g_xin_q
    int i = 0; while (i < XIN_MAX && g_xin[i].itf) i++;
    if (i == XIN_MAX) return;
    NSError *e = nil;
    IOUSBHostInterface *itf = [[IOUSBHostInterface alloc] initWithIOService:svc options:0 queue:g_xin_q error:&e interestHandler:^(IOUSBHostObject *o, uint32_t type, void *arg) {
        (void)arg; if (type == kIOMessageServiceIsTerminated) for (int j = 0; j < XIN_MAX; j++) if (g_xin[j].itf == o) xin_drop(j); }];
    if (!itf) { LOG("【紅】前端：XInput 接口打不開：%s", e.localizedDescription.UTF8String); return; }
    const IOUSBInterfaceDescriptor *d = itf.interfaceDescriptor; const IOUSBEndpointDescriptor *ep = NULL; IOUSBHostPipe *pipe = nil;
    while (!pipe && (ep = IOUSBGetNextEndpointDescriptor(itf.configurationDescriptor, d, (const IOUSBDescriptorHeader *)ep)))
        if ((ep->bEndpointAddress & 0x80) && (ep->bmAttributes & 3) == 3) pipe = [itf copyPipeWithAddress:ep->bEndpointAddress error:&e];
    if (!pipe) { LOG("【紅】前端：XInput 接口沒有中斷輸入端點"); [itf destroy]; return; }
    NSString *name = CFBridgingRelease(IORegistryEntrySearchCFProperty(svc, kIOServicePlane, CFSTR("USB Product Name"), kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents)) ?: @"XInput";
    g_xin[i].itf = itf; g_xin[i].pipe = pipe; g_xin[i].buf = [NSMutableData dataWithLength:32]; g_xin[i].name = name;
    LOG("前端：XInput 手柄 %s", name.UTF8String);
    xin_next(i);
}
static void xin_matched(void *ref, io_iterator_t it) {
    (void)ref; io_service_t s;
    while ((s = IOIteratorNext(it))) { xin_open(s); IOObjectRelease(s); }
}
static void xin_watch(void) {
    g_xin_q = dispatch_queue_create("dm.xinput", DISPATCH_QUEUE_SERIAL);
    IONotificationPortRef port = IONotificationPortCreate(kIOMainPortDefault); IONotificationPortSetDispatchQueue(port, g_xin_q);
    // 按接口類 / 子類 / 協議比對（IOPropertyMatch；直接寫在頂層的 bInterface* 鍵比不上） | match on interface class / subclass / protocol (IOPropertyMatch; bInterface* keys at the top level do not match)
    NSDictionary *match = @{@kIOProviderClassKey: @"IOUSBHostInterface", @kIOPropertyMatchKey: @{@"bInterfaceClass": @255, @"bInterfaceSubClass": @93, @"bInterfaceProtocol": @1}};
    io_iterator_t it;
    if (IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, (CFDictionaryRef)CFBridgingRetain(match), xin_matched, NULL, &it) == KERN_SUCCESS)
        dispatch_async(g_xin_q, ^{ xin_matched(NULL, it); });   // 已經接著的先開一遍，同時武裝通知 | open the ones already connected, which also arms the notification
}
NSArray<NSString *> *front_pad_names(void);
static NSArray<NSString *> *xin_names(void) {
    NSMutableArray<NSString *> *a = [NSMutableArray array];
    os_unfair_lock_lock(&g_xin_lock); for (int i = 0; i < XIN_MAX; i++) if (g_xin[i].itf) [a addObject:g_xin[i].name]; os_unfair_lock_unlock(&g_xin_lock);
    return a;
}

// 手柄鍵位：實體鍵（P_*，按位置）→ Switch 鍵。玩家在「控制」窗口改過就用 defaults 的 PadMap（16 個數：每個 Switch 鍵對應的實體鍵，-1 = 不映射），
//   沒改過就按手柄類型：Xbox / PS 下方鍵 = A，任天堂手柄照 Switch 原樣（dm_padmap.h）
// Controller mapping: physical buttons (P_*, by position) → Switch buttons. Once the player changes it in the Controls window, PadMap in the defaults is used (16 numbers: the physical button for each Switch button, -1 = unmapped);
//   otherwise it follows the controller type: on Xbox / PS the bottom button = A, Nintendo controllers as on the Switch (dm_padmap.h)
static int g_padmap[16], g_padmap_custom;
static const int k_pad_xbox[16] = {P_SOUTH, P_EAST, P_WEST, P_NORTH, P_LS, P_RS, P_LB, P_RB, P_LT, P_RT, P_START, P_BACK, P_LEFT, P_UP, P_RIGHT, P_DOWN};
static const int k_pad_nintendo[16] = {P_EAST, P_SOUTH, P_NORTH, P_WEST, P_LS, P_RS, P_LB, P_RB, P_LT, P_RT, P_START, P_BACK, P_LEFT, P_UP, P_RIGHT, P_DOWN};
static void padmap_load(void) {
    NSArray *a = [NSUserDefaults.standardUserDefaults arrayForKey:@"PadMap"];
    g_padmap_custom = a.count == 16;
    for (int s = 0; s < 16; s++) g_padmap[s] = g_padmap_custom ? [a[s] intValue] : k_pad_xbox[s];
}
static uint64_t pad_map(uint32_t phys, int kind) {
    const int *t = g_padmap_custom ? g_padmap : kind == DM_PADKIND_NINTENDO ? k_pad_nintendo : k_pad_xbox; uint64_t m = 0;
    for (int s = 0; s < 16; s++) if (t[s] >= 0 && t[s] < P_N && (phys >> t[s] & 1)) m |= 1ull << s;
    return m;
}
void front_padmap_get(int map[16], int *custom) { memcpy(map, g_padmap, sizeof g_padmap); if (custom) *custom = g_padmap_custom; }
void front_padmap_set(const int *map) {
    if (map) { NSMutableArray *a = [NSMutableArray array]; for (int s = 0; s < 16; s++) [a addObject:@(map[s])]; [NSUserDefaults.standardUserDefaults setObject:a forKey:@"PadMap"]; }
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:@"PadMap"];
    padmap_load(); pads_read();
}
static void pads_read(void) {
    uint64_t m = 0; uint32_t raw = 0; int32_t ax[4] = {0};
    os_unfair_lock_lock(&g_xin_lock);
    for (int i = 0; i < XIN_MAX; i++) if (g_xin[i].itf) {
        m |= pad_map(g_xin[i].phys, DM_PADKIND_XBOX); raw |= g_xin[i].phys;
        for (int a = 0; a < 4; a++) if (abs(g_xin[i].ax[a]) > abs(ax[a])) ax[a] = g_xin[i].ax[a];
    }
    os_unfair_lock_unlock(&g_xin_lock);
    for (GCController *c in GCController.controllers) {
        GCExtendedGamepad *g = c.extendedGamepad; if (!g) continue;
        int kind = dm_padmap_kind(c.productCategory.UTF8String, c.vendorName.UTF8String);
        uint32_t phys = 0;   // GameController 的面鍵按位置：buttonA 下、buttonB 右、buttonX 左、buttonY 上 | GameController face buttons are positional: buttonA bottom, buttonB right, buttonX left, buttonY top
        #define K(btn, p) if ((btn) && (btn).isPressed) phys |= 1u << p
        K(g.buttonA, P_SOUTH); K(g.buttonB, P_EAST); K(g.buttonX, P_WEST); K(g.buttonY, P_NORTH);
        K(g.leftShoulder, P_LB); K(g.rightShoulder, P_RB); K(g.leftTrigger, P_LT); K(g.rightTrigger, P_RT);
        K(g.buttonMenu, P_START); K(g.buttonOptions, P_BACK); K(g.leftThumbstickButton, P_LS); K(g.rightThumbstickButton, P_RS);
        K(g.dpad.left, P_LEFT); K(g.dpad.up, P_UP); K(g.dpad.right, P_RIGHT); K(g.dpad.down, P_DOWN);
        #undef K
        m |= pad_map(phys, kind); raw |= phys;
        float v[4] = {g.leftThumbstick.xAxis.value, g.leftThumbstick.yAxis.value, g.rightThumbstick.xAxis.value, g.rightThumbstick.yAxis.value};
        for (int i = 0; i < 4; i++) if (fabsf(v[i]) > fabsf(ax[i] / (float)DM_STICK_MAX)) ax[i] = pad_axis(v[i]);   // 多個手柄：取推得最遠的 | several controllers: the furthest tilt wins
    }
    static uint32_t last_raw; if (raw != last_raw) { last_raw = raw; controls_pad_phys(raw); }   // 控制窗口錄鍵用（不管遊戲窗口在不在前台） | for button capture in the Controls window (whether or not the game window is in front)
    if (!pad_on() || !g_win.isKeyWindow) { m = 0; memset(ax, 0, sizeof ax); }   // XInput 在後台也照樣送報告；只在窗口在前台時算 | XInput reports keep coming in the background; count them only while the window is in front
    dm_pad_set(m, ax[0], ax[1], ax[2], ax[3]);   // 上為正，與 GameController 相同 | up is positive, as in GameController
}
static void pads_changed(void) {
    for (GCController *c in GCController.controllers) {
        if (!c.extendedGamepad) continue;
        c.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *g, GCControllerElement *el) { (void)g; (void)el; pads_read(); };
        LOG("前端：手柄 %s（%s）", c.vendorName.UTF8String ?: "?", c.productCategory.UTF8String ?: "?");
    }
    pads_read();
}
static void pads_watch(void) {
    for (NSNotificationName n in @[GCControllerDidConnectNotification, GCControllerDidDisconnectNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:n object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *x) { (void)x; pads_changed(); }];
    padmap_load(); pads_changed(); xin_watch();
}
// ---- 給控制窗口（controls_mac.m）的接口 | Interface for the Controls window (controls_mac.m) ----
NSArray<NSString *> *front_pad_names(void) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (GCController *c in GCController.controllers) if (c.extendedGamepad) [names addObject:c.vendorName ?: c.productCategory ?: @"?"];
    [names addObjectsFromArray:xin_names()];
    return names;
}
int front_input_mode(void) { return input_mode(); }
void front_input_mode_set(int m) {
    if (m) [NSUserDefaults.standardUserDefaults setInteger:m forKey:@"InputMode"]; else [NSUserDefaults.standardUserDefaults removeObjectForKey:@"InputMode"];
    input_release_all(); pads_read();   // 先全部鬆開，再按新設定重讀手把 | release everything, then reread the controllers under the new setting
}
const char *front_keymap_path(void) { return g_keymap_path[0] ? g_keymap_path : NULL; }
const char *front_keymap_defaults(void) { return k_default_map; }
const char *front_keyname(int code) { return code >= 0 && code < 128 ? k_keyname[code] : NULL; }
void front_keymap_apply(void) { input_release_all(); keymap_load(); LOG("前端：控制窗口改了鍵位，已重讀 %s", g_keymap_path); }
static void on_key(NSEvent *e, int down) {
    unsigned short c = e.keyCode; if (c >= 128 || g_keyrow[c] < 0) return;
    dm_bind_press(g_keyrow[c], down); dm_bind_publish(dm_input_set);
}

// ---------- 畫面位置、提示、鎖定鼠標、暫停 | Picture placement, hints, mouse capture, pause ----------
// 遊戲畫面在內容視圖裡的位置：按畫面形狀（缺省 16:9）等比居中（窗口限了比例，全屏時兩邊或上下補黑） | where the game picture sits in the content view: centred at the picture's shape (16:9 by default) (the window keeps the ratio; full screen adds black bars)
static NSRect game_rect(void) {
    NSRect b = g_view.bounds; CGFloat w = b.size.width, h = b.size.height; NSSize p = picture_size();
    if (w * p.height > h * p.width) { CGFloat nw = h * p.width / p.height; return NSMakeRect(floor((w - nw) / 2), 0, nw, h); }
    CGFloat nh = w * p.height / p.width; return NSMakeRect(0, floor((h - nh) / 2), w, nh);
}
static void layer_layout(void) {
    NSRect r = game_rect(); CGFloat s = g_win.backingScaleFactor;
    static int logs; if (logs++ < 40) LOG("前端：畫面 %.0fx%.0f 點（內容視圖 %.0fx%.0f，倍率 %.0f）%s", r.size.width, r.size.height, g_view.bounds.size.width, g_view.bounds.size.height, s,
                                        g_win.styleMask & NSWindowStyleMaskFullScreen ? " 全螢幕" : "");
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    g_layer.frame = r; g_layer.contentsScale = s;
    g_layer.drawableSize = CGSizeMake(fmax(1, round(r.size.width * s)), fmax(1, round(r.size.height * s)));
    [CATransaction commit];
}
static int capture_wanted(void) { return g_anrow[AN_MOVE] >= 0 && !dm_bind_is_pointer(g_mbrow[MB_LEFT]); }
static NSString *g_flash; static double g_flash_until;   // 臨時提示（截圖存好了等），到時換回常規提示 | a temporary hint (screenshot saved etc.), replaced by the regular hint when it expires
static void hint_update(void) {
    if (g_flash && CACurrentMediaTime() < g_flash_until) { g_win.subtitle = g_flash; return; }
    g_flash = nil;
    g_win.subtitle = g_paused ? T(T_PAUSED) : g_captured ? T(T_HINT_CMD) : capture_wanted() ? T(T_HINT_CLICK) : @"";
}
// 幀率計數：遊戲畫面左上角的小標籤，每 0.5 秒按實際出圖次數（mtl_present_count）算一次 FPS 與平均幀時間；開關記進 defaults 的 ShowFPS
// FPS counter: a small label in the top-left corner of the game picture, recomputed every 0.5 s from the actual present count (mtl_present_count) as FPS and average frame time; the switch is stored as ShowFPS in the defaults
uint64_t mtl_present_count(void);
static CATextLayer *g_fps_layer; static NSTimer *g_fps_timer;
static int fpsc_pref(void) { return [NSUserDefaults.standardUserDefaults boolForKey:@"ShowFPS"]; }
static void fps_show(int on) {
    if (!on) { [g_fps_timer invalidate]; g_fps_timer = nil; [g_fps_layer removeFromSuperlayer]; g_fps_layer = nil; return; }
    if (g_fps_layer || !g_view.layer) return;
    CATextLayer *t = [CATextLayer layer];
    t.font = (__bridge CFTypeRef)[NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightSemibold]; t.fontSize = 13;
    t.foregroundColor = NSColor.whiteColor.CGColor; t.backgroundColor = [NSColor colorWithWhite:0 alpha:0.55].CGColor;
    t.cornerRadius = 5; t.alignmentMode = kCAAlignmentCenter; t.contentsScale = g_win.backingScaleFactor; t.zPosition = 10; t.string = @"— FPS";
    [g_view.layer addSublayer:t]; g_fps_layer = t;
    __block uint64_t n0 = mtl_present_count(); __block double t0 = CACurrentMediaTime();
    void (^place)(void) = ^{ CGRect b = g_view.layer.bounds; [CATransaction begin]; [CATransaction setDisableActions:YES];
        g_fps_layer.frame = CGRectMake(8, b.size.height - 8 - 22, 132, 22); g_fps_layer.contentsScale = g_win.backingScaleFactor; [CATransaction commit]; };
    place();
    g_fps_timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *tm) { (void)tm;
        uint64_t n = mtl_present_count(); double now = CACurrentMediaTime(), fps = (now > t0) ? (double)(n - n0) / (now - t0) : 0; n0 = n; t0 = now;
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        g_fps_layer.string = fps > 0.5 ? [NSString stringWithFormat:@"%.0f FPS · %.1f ms", fps, 1000.0 / fps] : @"0 FPS";
        [CATransaction commit]; place(); }];
}
static void flash(NSString *s) {
    g_flash = s; g_flash_until = CACurrentMediaTime() + 3; hint_update();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ hint_update(); });
}
// 鎖定：光標藏起並與鼠標脫鈎（不再移動，事件照樣帶位移），遊戲裡的小手成為唯一的指針 | capture: hide the cursor and detach it from the mouse (it stops moving, events still carry deltas), so the game's hand is the only pointer
static void capture_set(int on) {
    if (on == g_captured) return;
    g_captured = on;
    CGAssociateMouseAndMouseCursorPosition(on ? false : true);
    if (on) [NSCursor hide]; else [NSCursor unhide];
    if (!on) {   // 放開時按著的鼠標鍵一並鬆開、小手停下 | on release, let go of held mouse buttons and stop the hand
        for (int b = 0; b < MB_N; b++) if (g_mbrow[b] >= 0 && !dm_bind_is_pointer(g_mbrow[b])) dm_bind_press(g_mbrow[b], 0);
        g_an_acc[AN_MOVE][0] = g_an_acc[AN_MOVE][1] = 0; dm_bind_publish(dm_input_set);
    }
    hint_update();
}
// 暫停 = 縮到最小那套掛起（音頻停、出圖擋住、客體時鐘凍結 原因 3），窗口還在 | pause = the same suspension as minimizing (audio stopped, presents blocked, guest clock frozen with reason 3) while the window stays
static void pause_set(int on) {
    if (on == g_paused || g_win.miniaturized) return;
    g_paused = on;
    if (on) { capture_set(0); input_release_all(); dm_focus_set(2); dm_audio_suspend(1); guest_clock_freeze_for(3, 1); dm_gfx_suspend(1); }
    else { dm_gfx_suspend(0); guest_clock_freeze_for(3, 0); dm_audio_suspend(0); if (g_win.isKeyWindow) dm_focus_set(1); }
    LOG("前端：%s", on ? "暫停" : "繼續");
    hint_update();
}
static NSString *log_path(void) {   // 啓動器把標準輸出接到日誌文件：按文件描述符反查路徑 | the launcher points stdout at the log file: look the path up from the file descriptor
    char p[PATH_MAX]; struct stat st;
    if (fstat(1, &st) || !S_ISREG(st.st_mode) || fcntl(1, F_GETPATH, p) == -1) return nil;
    return @(p);
}
static NSURL *shot_dir(void) {   // 系統截圖存放位置（截圖 App 裡設的），沒設就是桌面 | the system screenshot location (set in the Screenshot app), the Desktop if unset
    NSString *d = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.apple.screencapture"][@"location"];
    BOOL dir = NO; d = d.length ? d.stringByExpandingTildeInPath : nil;
    if (!d || ![NSFileManager.defaultManager fileExistsAtPath:d isDirectory:&dir] || !dir) d = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES).firstObject;
    return [NSURL fileURLWithPath:d isDirectory:YES];
}

// 遊戲語言（遊戲資料裡有的 13 種，RomFS System/RegionLangMask.txt）：選了寫進本 App 的 defaults「GameLanguage」，啓動器下次按它設 DM_LANG；第 0 項 = 跟系統（刪掉這個鍵）
// Game languages (the 13 in the game data, RomFS System/RegionLangMask.txt): a choice is written to this app's defaults "GameLanguage" and the launcher sets DM_LANG from it next time; item 0 = follow the system (removes the key)
static const struct { const char *code, *name; } k_langs[] = {
    {"", NULL}, {"en-US", "English (US)"}, {"en-GB", "English (UK)"}, {"fr", "Français"}, {"fr-CA", "Français (Canada)"}, {"es", "Español (España)"},
    {"es-419", "Español (Latinoamérica)"}, {"de", "Deutsch"}, {"it", "Italiano"}, {"nl", "Nederlands"}, {"ja", "日本語"}, {"ko", "한국어"},
    {"zh-Hans", "簡體中文"}, {"zh-Hant", "繁體中文"},
};
static NSString *lang_pref(void) { return [NSUserDefaults.standardUserDefaults stringForKey:@"GameLanguage"] ?: @""; }
// 幀率（可選剪口 fps60，只在這個遊戲的 options.tsv 有它時顯示）：選了寫進 defaults「FrameRate」，啓動器下次按它設 DM_OPTIONS；30 = 刪掉這個鍵
// 畫面放大（defaults「Upscale」，缺省開）：即時生效，改 mtl_set_upscale
// Frame rate (optional cut fps60, shown only when this game's options.tsv has it): a choice is written to defaults "FrameRate" and the launcher sets DM_OPTIONS from it next time; 30 = removes the key
// Upscaling (defaults "Upscale", on by default): takes effect immediately through mtl_set_upscale
void mtl_set_upscale(int on);
static int fps_pref(void) { return (int)[NSUserDefaults.standardUserDefaults integerForKey:@"FrameRate"] == 60 ? 60 : 30; }
static int upscale_pref(void) { id v = [NSUserDefaults.standardUserDefaults objectForKey:@"Upscale"]; return v ? [v boolValue] : 1; }

// 雙擊標題欄進全螢幕：遊戲畫面形狀固定，系統的「縮放 / 填滿」只會給一個大一點的視窗。系統設定成「縮到最小」或「不動作」時照系統；雙擊紅黃綠按鈕不管
// Double-clicking the title bar enters full screen: the picture keeps its shape, so the system's Zoom / Fill only gives a larger window. When the system setting is Minimize or Do Nothing the system handles it; double-clicks on the traffic-light buttons are left alone
@interface DMWindow : NSWindow
@end
@implementation DMWindow
- (void)sendEvent:(NSEvent *)e {
    if (e.type == NSEventTypeLeftMouseDown && e.clickCount == 2 && !(self.styleMask & NSWindowStyleMaskFullScreen) && e.locationInWindow.y >= NSMaxY(self.contentLayoutRect)) {
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults; NSString *act = [d stringForKey:@"AppleActionOnDoubleClick"];
        int sys = [d boolForKey:@"AppleMiniaturizeOnDoubleClick"] || [act isEqualToString:@"Minimize"] || [act isEqualToString:@"None"];
        if (!sys && ![[self.contentView.superview hitTest:e.locationInWindow] isKindOfClass:NSButton.class]) { [self toggleFullScreen:nil]; return; }
    }
    [super sendEvent:e];
}
@end

// ---------- 菜單與窗口代理 | Menus and the window delegate ----------
@interface DMApp : NSObject <NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation>
@end
@implementation DMApp
- (void)togglePause:(id)sender { (void)sender; pause_set(!g_paused); }
- (void)takeScreenshot:(id)sender {
    (void)sender;
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"yyyy-MM-dd HH.mm.ss";
    NSURL *dir = shot_dir(), *url = [dir URLByAppendingPathComponent:[NSString stringWithFormat:@"%@ %@.png", app_name(), [f stringFromDate:NSDate.date]]];
    dm_gfx_shot_at(0, url.fileSystemRepresentation);
    flash([NSString stringWithFormat:T(T_SHOT_SAVED), [NSFileManager.defaultManager displayNameAtPath:dir.path]]);
}
- (void)editControls:(id)sender { (void)sender; capture_set(0); controls_open(); }   // 控制窗口（controls_mac.m） | the Controls window (controls_mac.m)
- (void)setFrameRate:(NSMenuItem *)it {
    int fps = (int)it.tag; if (fps == fps_pref()) return;
    if (fps == 60) [NSUserDefaults.standardUserDefaults setInteger:60 forKey:@"FrameRate"]; else [NSUserDefaults.standardUserDefaults removeObjectForKey:@"FrameRate"];
    capture_set(0);
    NSAlert *a = [NSAlert new]; a.messageText = [NSString stringWithFormat:T(T_FPS_NEXT), fps]; if (fps == 60) a.informativeText = T(T_FPS_SLOW); [a addButtonWithTitle:T(T_OK)];
    if (g_win.attachedSheet) [a runModal]; else [a beginSheetModalForWindow:g_win completionHandler:nil];
}
// 掌機模式：遊戲按 720p 渲染（主機模式 1080p），GPU 像素少一半多；即時切換（hle_oe.c dm_set_opmode 推運行模式通知），記進 defaults 供啓動腳本讀
// Handheld mode: the game renders at 720p (1080p in console mode), less than half the GPU pixels; switched live (hle_oe.c dm_set_opmode pushes the operation-mode notification) and stored in the defaults for the launch script
- (void)toggleFPS:(NSMenuItem *)it {
    (void)it; int on = !fpsc_pref();
    [NSUserDefaults.standardUserDefaults setBool:on forKey:@"ShowFPS"]; fps_show(on);
}
- (void)toggleHandheld:(NSMenuItem *)it {
    (void)it; int on = dm_opmode() != 0;
    [NSUserDefaults.standardUserDefaults setBool:on forKey:@"Handheld"]; dm_set_opmode(on ? 0 : 1);
    LOG("前端：掌機模式%s", on ? "開" : "關");
}
- (void)toggleUpscale:(NSMenuItem *)it {
    (void)it; int on = !upscale_pref();
    [NSUserDefaults.standardUserDefaults setBool:on forKey:@"Upscale"]; mtl_set_upscale(on);
    LOG("前端：MetalFX 放大%s", on ? "開" : "關");
}
- (void)setGameLanguage:(NSMenuItem *)it {
    int i = (int)it.tag; NSString *code = @(k_langs[i].code);
    if ([code isEqualToString:lang_pref()]) return;
    if (code.length) [NSUserDefaults.standardUserDefaults setObject:code forKey:@"GameLanguage"]; else [NSUserDefaults.standardUserDefaults removeObjectForKey:@"GameLanguage"];
    [NSUserDefaults.standardUserDefaults synchronize];   // 啓動器用 defaults 命令讀，要先落盤 | the launcher reads it with the defaults command, so flush it first
    capture_set(0);
    NSAlert *a = [NSAlert new]; a.messageText = [NSString stringWithFormat:T(T_LANG_NEXT), k_langs[i].name ? @(k_langs[i].name) : T(T_LANG_SYS)]; [a addButtonWithTitle:T(T_OK)];
    if (g_win.attachedSheet) [a runModal]; else [a beginSheetModalForWindow:g_win completionHandler:nil];
}
// 抓圖形診斷：本幀截圖 + 兩幀後的通道轉儲與顏色目標，存到日誌文件夾下的 diag-<時間>/（nvn_diag_capture） | capture graphics diagnostics: a screenshot of this frame plus the pass dump and colour targets two frames later, into diag-<time>/ under the log folder (nvn_diag_capture)
void nvn_diag_capture(const char *path_fmt);
- (void)captureDiag:(id)sender {
    (void)sender; if (g_paused) return;
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *dir = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/nxnative"] stringByAppendingPathComponent:[@"diag-" stringByAppendingString:[f stringFromDate:NSDate.date]]];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    dm_gfx_shot_at(0, [dir stringByAppendingPathComponent:@"pantalla.png"].fileSystemRepresentation);
    nvn_diag_capture([dir stringByAppendingPathComponent:@"rt_%d.png"].fileSystemRepresentation);
    LOG("前端：圖形診斷 → %s", dir.UTF8String);
    // 轉儲寫完後把日誌拷進同一個文件夾：下次開遊戲日誌會被重寫 | once the dump is written, copy the log into the same folder: the next launch rewrites the log
    NSString *log = log_path();
    if (log) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [NSFileManager.defaultManager copyItemAtPath:log toPath:[dir stringByAppendingPathComponent:@"registro.log"] error:nil]; });
    flash(T(T_DIAG_DONE));
}
- (void)showAlbum:(id)sender { (void)sender; album_open(); }
- (void)showAlbumFolder:(id)sender { (void)sender; album_show_folder(); }
- (void)showSaves:(id)sender { (void)sender; const char *s = getenv("DM_SAVE"); if (s) [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:@(s) isDirectory:YES]]; }
- (void)showLog:(id)sender { (void)sender; NSString *p = log_path(); if (p) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:p]]]; }
- (void)showControls:(id)sender {
    (void)sender; capture_set(0);
    NSAlert *a = [NSAlert new]; a.messageText = T(T_CONTROLS); [a addButtonWithTitle:T(T_OK)];
    a.informativeText = [T(dm_bind_is_pointer(g_mbrow[MB_LEFT]) ? T_CONTROLS_TAP : T_CONTROLS_MOUSE) stringByAppendingString:T(T_CONTROLS_BODY)];
    if (g_win.attachedSheet) [a runModal]; else [a beginSheetModalForWindow:g_win completionHandler:nil];
}
- (void)setGameSize:(NSMenuItem *)it {   // tag = 內容寬（點），高按畫面形狀；放不下就縮到屏幕可用區域 | tag = content width in points, height by the picture's shape; shrunk to the screen's usable area if it does not fit
    NSRect vis = g_win.screen.visibleFrame, fr = g_win.frame; NSSize p = picture_size();
    CGFloat w = it.tag, h = round(w * p.height / p.width), chrome = fr.size.height - g_view.bounds.size.height;
    if (h + chrome > vis.size.height) { h = vis.size.height - chrome; w = round(h * p.width / p.height); }
    if (w > vis.size.width) { w = vis.size.width; h = round(w * p.height / p.width); }
    NSRect nf = [g_win frameRectForContentRect:NSMakeRect(0, 0, w, h)];
    nf.origin.x = NSMidX(fr) - nf.size.width / 2; nf.origin.y = NSMaxY(fr) - nf.size.height;   // 標題欄不動、左右以原中線為準 | keep the title bar in place, centred on the old midline
    nf.origin.x = fmin(fmax(nf.origin.x, vis.origin.x), NSMaxX(vis) - nf.size.width); nf.origin.y = fmin(fmax(nf.origin.y, vis.origin.y), NSMaxY(vis) - nf.size.height);
    [g_win setFrame:nf display:YES animate:YES];
}
- (BOOL)validateMenuItem:(NSMenuItem *)it {
    SEL a = it.action; int fs = (g_win.styleMask & NSWindowStyleMaskFullScreen) != 0;
    if (a == @selector(togglePause:)) { it.title = g_paused ? T(T_RESUME) : T(T_PAUSE); return !g_win.miniaturized; }
    if (a == @selector(takeScreenshot:)) return !g_paused && !g_win.miniaturized;
    if (a == @selector(setGameSize:)) { NSSize c = g_view.bounds.size; it.state = !fs && fabs(c.width - it.tag) < 1 ? NSControlStateValueOn : NSControlStateValueOff; return !fs && !g_win.miniaturized; }
    if (a == @selector(showSaves:)) return getenv("DM_SAVE") != NULL;
    if (a == @selector(setFrameRate:)) { it.state = it.tag == fps_pref() ? NSControlStateValueOn : NSControlStateValueOff; return YES; }
    if (a == @selector(toggleFPS:)) { it.state = fpsc_pref() ? NSControlStateValueOn : NSControlStateValueOff; return YES; }
    if (a == @selector(toggleHandheld:)) { it.state = dm_opmode() == 0 ? NSControlStateValueOn : NSControlStateValueOff; return YES; }
    if (a == @selector(toggleUpscale:)) { it.state = upscale_pref() ? NSControlStateValueOn : NSControlStateValueOff; return YES; }
    if (a == @selector(setGameLanguage:)) { it.state = [@(k_langs[it.tag].code) isEqualToString:lang_pref()] ? NSControlStateValueOn : NSControlStateValueOff; return YES; }
    if (a == @selector(showLog:)) return log_path() != nil;
    return YES;
}
- (void)windowDidFailToEnterFullScreen:(NSWindow *)w { (void)w; LOG("【紅】前端：進全螢幕失敗"); }
- (void)windowDidFailToExitFullScreen:(NSWindow *)w { (void)w; LOG("【紅】前端：退出全螢幕失敗"); }
- (BOOL)windowShouldClose:(NSWindow *)w { (void)w; [NSApp terminate:self]; return NO; }   // 關窗 = 退出（先問） | closing the window = quitting (asks first)
// 「縮放」（視窗選單、按住 Option 點綠色按鈕）也直接進全螢幕，理由同 DMWindow 的雙擊標題欄
// Zoom (the Window menu, Option-clicking the green button) also enters full screen, for the same reason as DMWindow's title-bar double-click
- (BOOL)windowShouldZoom:(NSWindow *)w toFrame:(NSRect)f { (void)f; if (!(w.styleMask & NSWindowStyleMaskFullScreen)) [w toggleFullScreen:nil]; return NO; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
    (void)app; capture_set(0);
    NSAlert *a = [NSAlert new]; a.messageText = [NSString stringWithFormat:T(T_QUIT_Q), app_name()]; a.informativeText = T(T_QUIT_INFO);
    [a addButtonWithTitle:T(T_QUIT_OK)]; [a addButtonWithTitle:T(T_CANCEL)];
    if (g_win.attachedSheet || g_win.miniaturized || !g_win.visible) return [a runModal] == NSAlertFirstButtonReturn ? NSTerminateNow : NSTerminateCancel;
    [a beginSheetModalForWindow:g_win completionHandler:^(NSModalResponse r) { [NSApp replyToApplicationShouldTerminate:r == NSAlertFirstButtonReturn]; }];
    return NSTerminateLater;
}
@end
static DMApp *g_app;

static NSMenu *menu_add(NSMenu *bar, NSString *title) {
    NSMenuItem *top = [bar addItemWithTitle:title action:nil keyEquivalent:@""]; NSMenu *m = [[NSMenu alloc] initWithTitle:title]; top.submenu = m; return m;
}
static NSMenuItem *item_add(NSMenu *m, NSString *title, SEL act, NSString *key, NSEventModifierFlags mods, id target) {
    NSMenuItem *it = [m addItemWithTitle:title action:act keyEquivalent:key ?: @""];
    if (mods) it.keyEquivalentModifierMask = mods;
    it.target = target; return it;
}
static void menus_build(void) {
    NSString *n = app_short(); const NSEventModifierFlags CMD = NSEventModifierFlagCommand;
    NSMenu *bar = [NSMenu new];
    NSMenu *app = menu_add(bar, n);
    item_add(app, [NSString stringWithFormat:T(T_ABOUT), n], @selector(orderFrontStandardAboutPanel:), nil, 0, NSApp);
    [app addItem:NSMenuItem.separatorItem];
    item_add(app, T(T_EDIT_CONTROLS), @selector(editControls:), @",", CMD, g_app);
    [app addItem:NSMenuItem.separatorItem];
    item_add(app, [NSString stringWithFormat:T(T_HIDE), n], @selector(hide:), @"h", CMD, NSApp);
    item_add(app, T(T_HIDE_OTHERS), @selector(hideOtherApplications:), @"h", CMD | NSEventModifierFlagOption, NSApp);
    item_add(app, T(T_SHOW_ALL), @selector(unhideAllApplications:), nil, 0, NSApp);
    [app addItem:NSMenuItem.separatorItem];
    item_add(app, [NSString stringWithFormat:T(T_QUIT), n], @selector(terminate:), @"q", CMD, NSApp);
    NSMenu *ed = menu_add(bar, T(T_EDIT));   // 目標留空 = 交給當前焦點（輸入框裡的文字） | no target = the current first responder (the text in the input box)
    item_add(ed, T(T_UNDO), NSSelectorFromString(@"undo:"), @"z", CMD, nil);
    item_add(ed, T(T_REDO), NSSelectorFromString(@"redo:"), @"z", CMD | NSEventModifierFlagShift, nil);
    [ed addItem:NSMenuItem.separatorItem];
    item_add(ed, T(T_CUT), @selector(cut:), @"x", CMD, nil); item_add(ed, T(T_COPY), @selector(copy:), @"c", CMD, nil);
    item_add(ed, T(T_PASTE), @selector(paste:), @"v", CMD, nil); item_add(ed, T(T_SELECT_ALL), @selector(selectAll:), @"a", CMD, nil);
    NSMenu *game = menu_add(bar, T(T_GAME));
    item_add(game, T(T_PAUSE), @selector(togglePause:), @"p", CMD, g_app);
    item_add(game, T(T_SHOT), @selector(takeScreenshot:), @"s", CMD | NSEventModifierFlagShift, g_app);
    [game addItem:NSMenuItem.separatorItem];
    item_add(game, T(T_SAVES), @selector(showSaves:), nil, 0, g_app);
    NSMenu *lang = [[NSMenu alloc] initWithTitle:T(T_LANG)]; [game addItemWithTitle:T(T_LANG) action:nil keyEquivalent:@""].submenu = lang;
    for (int i = 0; i < (int)(sizeof k_langs / sizeof *k_langs); i++) {
        item_add(lang, k_langs[i].name ? @(k_langs[i].name) : T(T_LANG_SYS), @selector(setGameLanguage:), nil, 0, g_app).tag = i;
        if (!i) [lang addItem:NSMenuItem.separatorItem];
    }
    if (dm_option_known("fps60")) {   // 這個遊戲有 60 FPS 的可選剪口才給選 | offered only when this game has the 60 FPS optional cut
        NSMenu *fps = [[NSMenu alloc] initWithTitle:T(T_FPS)]; [game addItemWithTitle:T(T_FPS) action:nil keyEquivalent:@""].submenu = fps;
        item_add(fps, @"30 FPS", @selector(setFrameRate:), nil, 0, g_app).tag = 30;
        item_add(fps, @"60 FPS", @selector(setFrameRate:), nil, 0, g_app).tag = 60;
    }
    item_add(game, T(T_HANDHELD), @selector(toggleHandheld:), nil, 0, g_app);
    item_add(game, T(T_SHOWFPS), @selector(toggleFPS:), @"f", CMD | NSEventModifierFlagOption, g_app);
    item_add(game, T(T_DEVICES), @selector(editControls:), nil, 0, g_app);
    NSMenu *view = menu_add(bar, T(T_VIEW));
    static const int widths[3] = {960, 1280, 1600};
    NSSize p = picture_size();
    for (int i = 0; i < 3; i++) item_add(view, [NSString stringWithFormat:@"%d × %d", widths[i], (int)round(widths[i] * p.height / p.width)], @selector(setGameSize:), [NSString stringWithFormat:@"%d", i + 1], CMD, g_app).tag = widths[i];
    [view addItem:NSMenuItem.separatorItem];
    item_add(view, T(T_FULL), @selector(toggleFullScreen:), @"f", CMD | NSEventModifierFlagControl, nil);
    [view addItem:NSMenuItem.separatorItem];
    item_add(view, T(T_UPSCALE), @selector(toggleUpscale:), nil, 0, g_app);
    NSMenu *ext = menu_add(bar, T(T_EXTRAS));   // 遊戲內存進相簿的照片（album_mac.m） | photos the game saved to its album (album_mac.m)
    item_add(ext, [@(album_title(0)) stringByAppendingString:@"…"], @selector(showAlbum:), @"e", CMD | NSEventModifierFlagShift, g_app);
    item_add(ext, @(album_title(1)), @selector(showAlbumFolder:), nil, 0, g_app);
    NSMenu *win = menu_add(bar, T(T_WINDOW));
    item_add(win, T(T_MIN), @selector(performMiniaturize:), @"m", CMD, nil);
    item_add(win, T(T_ZOOM), @selector(performZoom:), nil, 0, nil);
    [win addItem:NSMenuItem.separatorItem];
    item_add(win, T(T_FRONT), @selector(arrangeInFront:), nil, 0, NSApp);
    NSMenu *help = menu_add(bar, T(T_HELP));
    item_add(help, T(T_CONTROLS), @selector(showControls:), @"?", CMD, g_app);
    item_add(help, T(T_LOG), @selector(showLog:), nil, 0, g_app);
    item_add(help, T(T_DIAG), @selector(captureDiag:), @"d", CMD | NSEventModifierFlagOption | NSEventModifierFlagShift, g_app);
    NSApp.mainMenu = bar; NSApp.windowsMenu = win; NSApp.helpMenu = help;
}

typedef struct { void (*fn)(void); } guest_arg;
static void *guest_tramp(void *p) {
    static char alt[65536];                       // 信號備用棧是每線程的；崩潰打印要在客體線程上也生效 | The signal alternate stack is per thread; crash printing must also work on the guest thread
    stack_t ss = {.ss_sp = alt, .ss_size = sizeof alt}; sigaltstack(&ss, 0);
    ((guest_arg *)p)->fn(); LOG("客體線程結束"); exit(0);
}

void front_run(void (*guest)(void)) {
    if (!getenv("DM_WINDOW")) { guest(); return; }
    keymap_load();
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        g_app = [DMApp new]; NSApp.delegate = g_app;
        menus_build(); mtl_set_upscale(upscale_pref());
        NSSize pic = picture_size(); NSRect r = NSMakeRect(0, 0, 1280, round(1280 * pic.height / pic.width));
        NSWindow *win = [[DMWindow alloc] initWithContentRect:r
                                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                      backing:NSBackingStoreBuffered defer:NO];
        g_win = win; win.delegate = g_app;
        win.title = app_name();
        win.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
        win.contentAspectRatio = pic; win.contentMinSize = NSMakeSize(640, round(640 * pic.height / pic.width));
        NSView *v = win.contentView; g_view = v;
        CALayer *root = [CALayer layer]; root.backgroundColor = NSColor.blackColor.CGColor;
        v.layer = root; v.wantsLayer = YES;   // 先給圖層再開 wantsLayer：視圖托管這個圖層，子圖層由這裡擺 | layer first, then wantsLayer: the view hosts this layer and the sublayers are placed here
        g_layer = [CAMetalLayer layer];
        g_layer.device = MTLCreateSystemDefaultDevice();
        g_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        [root addSublayer:g_layer];
        [win center];
        win.frameAutosaveName = @"GameWindow";   // 記住上次的位置和大小（有記錄就套用） | remember the last position and size (applied when one is stored)
        layer_layout();
        v.postsFrameChangedNotifications = YES;
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:NSViewFrameDidChangeNotification object:v queue:nil usingBlock:^(NSNotification *n) { (void)n; layer_layout(); }];
        [nc addObserverForName:NSWindowDidChangeBackingPropertiesNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; layer_layout(); }];
        [win makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        hint_update();
        if (fpsc_pref()) fps_show(1);
        // 鍵盤：⌘ 組合鍵交給菜單；按下 ⌘ 放開鼠標；沒映射的 Esc 也放開 | Keyboard: ⌘ combinations go to the menus; pressing ⌘ releases the mouse; an unmapped Esc releases it too
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp | NSEventMaskFlagsChanged handler:^NSEvent *(NSEvent *e) {
            if (e.window != win) return e;   // 只吃遊戲窗口的鍵；軟鍵盤輸入框等其他窗口照常收字 | Only swallow keys for the game window; other windows such as the software keyboard input box receive typing as usual
            if (e.type == NSEventTypeFlagsChanged) { if (e.modifierFlags & NSEventModifierFlagCommand) capture_set(0); return e; }
            int down = e.type == NSEventTypeKeyDown;
            if (!down) { on_key(e, 0); return nil; }   // 抬起一律送到：⌘ 期間按下的遊戲鍵也能鬆開 | key-ups always go through, so game keys pressed around ⌘ still get released
            if (e.modifierFlags & NSEventModifierFlagCommand) return e;
            if (e.keyCode == KC_ESCAPE && g_keyrow[KC_ESCAPE] < 0) { capture_set(0); return nil; }
            if (!g_paused && !e.isARepeat && kbd_on()) on_key(e, 1);
            return nil;   // 吃掉，免得系統提示音 | Swallow it to avoid the system beep
        }];
        // 鼠標：映射到 Pointer 的鍵在鼠標處觸屏（拖動跟著走，鬆開抬起）；其餘沒鎖定時歸系統，在畫面上點一下鎖定，鎖定後按鍵按映射表、移動累積成 mouse:Move
        // Mouse: a button mapped to Pointer touches the screen at the mouse (following drags, lifted on release); otherwise, while not captured the mouse belongs to the system and a click on the picture captures it, after which buttons follow the table and moves accumulate into mouse:Move
        win.acceptsMouseMovedEvents = YES;
        NSEventMask mm = NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged | NSEventMaskRightMouseDown | NSEventMaskRightMouseUp |
                         NSEventMaskRightMouseDragged | NSEventMaskOtherMouseDown | NSEventMaskOtherMouseUp | NSEventMaskOtherMouseDragged | NSEventMaskMouseMoved;
        [NSEvent addLocalMonitorForEventsMatchingMask:mm handler:^NSEvent *(NSEvent *e) {
            if (e.window != win) return e;
            NSEventType ty = e.type;
            int b = ty == NSEventTypeLeftMouseDown || ty == NSEventTypeLeftMouseUp || ty == NSEventTypeLeftMouseDragged ? MB_LEFT :
                    ty == NSEventTypeRightMouseDown || ty == NSEventTypeRightMouseUp || ty == NSEventTypeRightMouseDragged ? MB_RIGHT :
                    ty == NSEventTypeMouseMoved ? -1 : MB_OTHER;
            int down = ty == NSEventTypeLeftMouseDown || ty == NSEventTypeRightMouseDown || ty == NSEventTypeOtherMouseDown;
            int up = ty == NSEventTypeLeftMouseUp || ty == NSEventTypeRightMouseUp || ty == NSEventTypeOtherMouseUp;
            NSPoint p = [v convertPoint:e.locationInWindow fromView:nil];
            int inside = NSPointInRect(p, v.bounds);   // 標題欄、窗口邊不算 | the title bar and window edges do not count
            if (g_paused || !kbd_on()) return inside ? nil : e;
            if (b >= 0 && dm_bind_is_pointer(g_mbrow[b])) {
                if (up) { dm_touch_set(NULL, 0); return nil; }
                if (!inside) return e;
                NSRect gr = game_rect(); float nx = (float)((p.x - gr.origin.x) / gr.size.width), ny = (float)(1.0 - (p.y - gr.origin.y) / gr.size.height);   // AppKit 視圖原點在左下，觸屏原點在左上 | The AppKit view origin is at bottom left, the touchscreen origin is at top left
                if (nx < 0 || nx >= 1 || ny < 0 || ny >= 1) return nil;   // 點在黑邊上 | on a black bar
                dm_touch t = {0, nx, ny}; dm_touch_set(&t, 1); return nil;
            }
            if (!g_captured && capture_wanted()) {
                if (ty == NSEventTypeLeftMouseDown && inside && win.isKeyWindow) { capture_set(1); return nil; }   // 這一下只鎖定，不當 A | this click only captures, it is not A
                return e;
            }
            if (b >= 0 && (down || up)) { if (inside || up) { dm_bind_press(g_mbrow[b], down); dm_bind_publish(dm_input_set); } return inside ? nil : e; }
            if (g_captured) an_add(AN_MOVE, (float)e.deltaX, (float)-e.deltaY);   // 屏幕 y 向下、搖桿 y 向上 | screen y points down, stick y points up
            return inside ? nil : e;
        }];
        // 觸控板：雙指滾動（滾輪也算）、旋轉、捏合、三指滑 | Trackpad: two-finger scroll (the wheel counts too), rotate, pinch, three-finger swipe
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel | NSEventMaskRotate | NSEventMaskMagnify | NSEventMaskSwipe handler:^NSEvent *(NSEvent *e) {
            if (e.window != win) return e;
            if (g_paused || !kbd_on()) return nil;
            switch (e.type) {
                case NSEventTypeScrollWheel: {   // 按手指方向：自然滾動時增量即手指方向，否則反過來；滾輪一格按 10 點算 | by finger direction: with natural scrolling the delta is the finger direction, otherwise reversed; a wheel notch counts as 10 points
                    float k = e.hasPreciseScrollingDeltas ? 1.f : 10.f, sx = (float)e.scrollingDeltaX * k, sy = (float)e.scrollingDeltaY * k;
                    if (!e.isDirectionInvertedFromDevice) { sx = -sx; sy = -sy; }
                    an_add(AN_SCROLL, sx, -sy); break; }
                case NSEventTypeRotate: an_add(AN_ROTATE, -(float)e.rotation, 0); break;   // 逆時針為正 → 順時針轉是往右 | counterclockwise is positive → turning clockwise is right
                case NSEventTypeMagnify: pulse(e.magnification > 0 ? PU_PINCH_OUT : PU_PINCH_IN); break;
                case NSEventTypeSwipe: if (e.deltaX) pulse(e.deltaX > 0 ? PU_SWIPE_L : PU_SWIPE_R); else if (e.deltaY) pulse(e.deltaY > 0 ? PU_SWIPE_U : PU_SWIPE_D); break;
                default: return e;
            }
            return nil;
        }];
        [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *tm) { (void)tm; input_tick(); }];
        pads_watch();
        // 生命週期（hle.h / dm.h）：失焦 → 2、拿回焦點 → 1；最小化 → 3 + 音頻暫停 + GPU 掛起，還原 → 恢復（隨後拿回焦點 → 1）；暫停中這兩樣由暫停管
        // Lifecycle (hle.h / dm.h): focus lost → 2, focus regained → 1; minimized → 3 + audio paused + GPU suspended, restored → resume (followed by focus regained → 1); while paused the pause owns those two
        [nc addObserverForName:NSWindowDidResignKeyNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; capture_set(0); input_release_all(); if (!win.miniaturized) dm_focus_set(2); }];
        [nc addObserverForName:NSWindowDidBecomeKeyNotification object:win queue:nil usingBlock:^(NSNotification *n) {
            (void)n;
            if (keymap_changed()) { input_release_all(); keymap_load(); LOG("前端：鍵位表改過，已重讀 %s", g_keymap_path); }
            if (!g_paused) dm_focus_set(1);
            pads_read();   // 失焦時清掉了手柄狀態，按回當前的 | the controller state was cleared on focus loss; put back the current one
            hint_update();
        }];
        [nc addObserverForName:NSWindowDidMiniaturizeNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; capture_set(0); if (!g_paused) { dm_focus_set(3); dm_audio_suspend(1); dm_gfx_suspend(1); } }];
        [nc addObserverForName:NSWindowDidDeminiaturizeNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; if (!g_paused) { dm_gfx_suspend(0); dm_audio_suspend(0); dm_focus_set(2); } }];
        [nc addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(NSNotification *n) { (void)n; capture_set(0); }];
        // 全螢幕的形狀不一定是畫面的形狀：進全螢幕前先拿掉比例限制（不拿掉 AppKit 會馬上退回視窗），退出後再加回來；黑邊由 layer_layout 補
        // The full-screen shape need not match the picture's: drop the aspect constraint before entering (otherwise AppKit drops straight back to the window) and restore it after leaving; layer_layout adds the bars
        [nc addObserverForName:NSWindowWillEnterFullScreenNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; win.contentResizeIncrements = NSMakeSize(1, 1); }];
        [nc addObserverForName:NSWindowDidExitFullScreenNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; win.contentAspectRatio = pic; }];
        for (NSNotificationName nm in @[NSWindowWillEnterFullScreenNotification, NSWindowDidEnterFullScreenNotification, NSWindowWillExitFullScreenNotification, NSWindowDidExitFullScreenNotification])
            [nc addObserverForName:nm object:win queue:nil usingBlock:^(NSNotification *n) { LOG("前端：%s", n.name.UTF8String); }];   // 全螢幕切換的每一步記一行 | one line per full-screen transition step
        // 客體線程：棧 64 MiB（Switch 主線程棧由 npdm 指定，宿主給足）
        // Guest thread: 64 MiB stack (the Switch main thread stack is specified by npdm; the host gives plenty)
        static guest_arg ga; ga.fn = guest;
        pthread_attr_t a; pthread_attr_init(&a); pthread_attr_setstacksize(&a, 64u << 20);
        pthread_t th; if (pthread_create(&th, &a, guest_tramp, &ga)) die("pthread_create guest");
        // 診斷 DM_TEST_FULLSCREEN=秒：過這麼多秒進全螢幕，再 3 秒把實際上屏的畫面（drawable 尺寸）存到 DM_TEST_FULLSCREEN_SHOT 後結束
        // Diagnostic DM_TEST_FULLSCREEN=seconds: enter full screen after that many seconds, 3 seconds later save the presented picture (drawable size) to DM_TEST_FULLSCREEN_SHOT and quit
        if (getenv("DM_TEST_FULLSCREEN")) {
            double sec = atof(getenv("DM_TEST_FULLSCREEN")); const char *shotp = getenv("DM_TEST_FULLSCREEN_SHOT");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sec * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [win toggleFullScreen:nil]; });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((sec + 3) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                LOG("前端：全螢幕測試 視窗 %.0fx%.0f 螢幕 %.0fx%.0f 圖層 %.0fx%.0f drawable %.0fx%.0f", win.frame.size.width, win.frame.size.height, win.screen.frame.size.width, win.screen.frame.size.height,
                    g_layer.frame.size.width, g_layer.frame.size.height, g_layer.drawableSize.width, g_layer.drawableSize.height);
                void mtl_grab_next_present(void (^cb)(CGImageRef img));
                NSString *path = shotp ? @(shotp) : nil;
                mtl_grab_next_present(^(CGImageRef img) {
                    if (img && path) { NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:img]; [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]; }
                    LOG("前端：全螢幕測試 擷取 %zux%zu", img ? CGImageGetWidth(img) : 0, img ? CGImageGetHeight(img) : 0); exit(0); });
            });
        }
        [NSApp run];
    }
}

// 輸入單（軟鍵盤的 Mac 版），照遊戲島名頁的樣子畫：黃底、白色膠囊輸入欄、白色「B 取消」與橙色「A 確定」膠囊按鈕（下沿有立體厚邊，按下下沈），圓體字。
// 空白或超過上限時確定按不下；Return 確定、Esc 取消（輸入法組字時 Return 先交給輸入法）；打開時全選原有文字，直接打字就是重寫
// Input sheet (the Mac version of the software keyboard), drawn after the game's island name page: yellow ground, a white capsule input field, a white "B Cancel" and an orange "A OK" capsule button (with a raised bottom edge that sinks when pressed), rounded type.
// OK cannot be pressed while the text is blank or over the limit; Return confirms and Esc cancels (while an input method is composing, Return goes to the input method first); the existing text is selected on open, so typing replaces it
static NSColor *rgb(unsigned h, CGFloat a) { return [NSColor colorWithSRGBRed:(h >> 16 & 255) / 255.0 green:(h >> 8 & 255) / 255.0 blue:(h & 255) / 255.0 alpha:a]; }
enum { C_GROUND = 0xFFC21A, C_GROUND_EDGE = 0xE9A400, C_WHITE = 0xFFFFFF, C_ORANGE = 0xFF7A00, C_ORANGE_EDGE = 0xD85E00, C_NAVY = 0x1F2B46 };   // 取自島名頁截圖 | sampled from the island name page
static NSFont *round_font(CGFloat size, NSFontWeight w) {
    NSFont *f = [NSFont systemFontOfSize:size weight:w];
    NSFontDescriptor *d = [f.fontDescriptor fontDescriptorWithDesign:NSFontDescriptorSystemDesignRounded];
    NSFont *r = d ? [NSFont fontWithDescriptor:d size:size] : nil;
    return r ?: f;
}
static void capsule(NSRect body, CGFloat edge, NSColor *fill, NSColor *rim) {   // 膠囊 + 下沿厚邊（未翻轉坐標：厚邊在下） | capsule + raised bottom edge (unflipped coordinates: the edge is below)
    CGFloat r = body.size.height / 2;
    [rim setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(body, 0, -edge) xRadius:r yRadius:r] fill];
    [fill setFill]; [[NSBezierPath bezierPathWithRoundedRect:body xRadius:r yRadius:r] fill];
}
@interface DMGround : NSView
@end
@implementation DMGround
- (void)drawRect:(NSRect)dirty { (void)dirty; [rgb(C_GROUND, 1) setFill]; NSRectFill(self.bounds); }
@end
@interface DMIcon : NSView   // App 圖標（自己畫：NSImageView 走圖層，離屏截圖裡不出現） | the app icon (drawn here: NSImageView goes through layers and is missing from offscreen captures)
@property(strong) NSImage *image;
@end
@implementation DMIcon
- (void)drawRect:(NSRect)dirty { (void)dirty; [self.image drawInRect:self.bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}]; }
@end
@interface DMCapsuleField : NSView   // 輸入欄的白色膠囊底 | the input field's white capsule base
@end
@implementation DMCapsuleField
- (void)drawRect:(NSRect)dirty { (void)dirty; NSRect b = self.bounds; capsule(NSMakeRect(0, 4, b.size.width, b.size.height - 4), 4, rgb(C_WHITE, 1), rgb(C_GROUND_EDGE, 1)); }
@end
@interface DMPill : NSButton   // 遊戲風格膠囊按鈕：左邊手柄鍵圓標（A / B） | game-style capsule button with a controller key badge (A / B) on the left
@property(strong) NSColor *fill, *rim, *ink, *badgeFill, *badgeInk; @property(copy) NSString *badge;
@end
@implementation DMPill
- (BOOL)isFlipped { return NO; }   // NSButton 缺省翻轉；這裡按未翻轉畫（厚邊在下） | NSButton is flipped by default; drawn unflipped here (edge below)
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    CGFloat a = self.enabled ? 1 : 0.45, edge = 4, sink = self.isHighlighted ? 3 : 0;
    NSRect b = self.bounds, body = NSMakeRect(0, edge - sink, b.size.width, b.size.height - edge);
    capsule(body, edge - sink, [self.fill colorWithAlphaComponent:a], [self.rim colorWithAlphaComponent:a]);
    CGFloat d = body.size.height - 16; NSRect c = NSMakeRect(body.origin.x + 10, body.origin.y + 8, d, d);
    [[self.badgeFill colorWithAlphaComponent:a] setFill]; [[NSBezierPath bezierPathWithOvalInRect:c] fill];
    NSDictionary *ba = @{NSFontAttributeName: round_font(d * 0.6, NSFontWeightHeavy), NSForegroundColorAttributeName: [self.badgeInk colorWithAlphaComponent:a]};
    NSSize bs = [self.badge sizeWithAttributes:ba]; [self.badge drawAtPoint:NSMakePoint(NSMidX(c) - bs.width / 2, NSMidY(c) - bs.height / 2) withAttributes:ba];
    NSDictionary *ta = @{NSFontAttributeName: round_font(16, NSFontWeightBold), NSForegroundColorAttributeName: [self.ink colorWithAlphaComponent:a]};
    NSSize ts = [self.title sizeWithAttributes:ta]; CGFloat left = NSMaxX(c) + 6, room = NSMaxX(body) - 12 - left;
    [self.title drawAtPoint:NSMakePoint(left + (room - ts.width) / 2, NSMidY(body) - ts.height / 2) withAttributes:ta];
}
- (void)resetCursorRects { if (self.enabled) [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
@end
@interface DMInputSheet : NSObject <NSTextFieldDelegate>
@property(strong) NSPanel *panel; @property(strong) NSTextField *field, *count; @property(strong) DMPill *ok; @property int max;
@end
@implementation DMInputSheet
- (void)refresh {
    NSString *t = self.field.stringValue; NSUInteger n = t.length;   // 按 UTF-16 單元算，與 hle_swkbd.c 截斷一致 | counted in UTF-16 units, matching the truncation in hle_swkbd.c
    BOOL over = self.max > 0 && n > (NSUInteger)self.max, on = !over && [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
    if (on != self.ok.enabled) { self.ok.enabled = on; self.ok.needsDisplay = YES; [self.panel invalidateCursorRectsForView:self.ok]; }
    if (self.max > 0) { self.count.stringValue = [NSString stringWithFormat:@"%lu / %d", (unsigned long)n, self.max]; self.count.textColor = over ? rgb(0xD0021B, 1) : rgb(C_NAVY, 0.55); }
}
- (void)controlTextDidChange:(NSNotification *)n { (void)n; [self refresh]; }
- (void)finish:(NSButton *)b {
    if (self.panel.sheetParent) [self.panel.sheetParent endSheet:self.panel returnCode:b.tag]; else [NSApp stopModalWithCode:b.tag];
}
@end
static DMPill *sheet_button(NSString *title, NSString *badge, BOOL primary, NSString *key, NSModalResponse tag, DMInputSheet *s) {
    DMPill *b = [DMPill new]; b.title = title; b.badge = badge; b.bordered = NO; b.target = s; b.action = @selector(finish:); b.keyEquivalent = key; b.tag = tag;
    b.fill = rgb(primary ? C_ORANGE : C_WHITE, 1); b.rim = rgb(primary ? C_ORANGE_EDGE : C_GROUND_EDGE, 1); b.ink = rgb(primary ? C_WHITE : C_NAVY, 1);
    b.badgeFill = rgb(primary ? C_WHITE : C_NAVY, 1); b.badgeInk = rgb(primary ? C_ORANGE : C_WHITE, 1);
    return b;
}
static DMInputSheet *input_sheet(NSString *title, NSString *info, NSString *placeholder, NSString *initial, int max) {
    DMInputSheet *s = [DMInputSheet new]; s.max = max > 0 && max <= 100 ? max : 0;   // 內嵌鍵盤給的是緩衝上限（500），不顯示 | the inline keyboard passes the buffer limit (500), which is not shown
    const CGFloat W = 480, P = 28, ICON = 60, GAP = 14, tx = P + ICON + GAP, tw = W - tx - P, BH = 46, BW = 140, FH = 54;
    NSTextField *ti = [NSTextField labelWithString:title]; ti.font = round_font(19, NSFontWeightBold); ti.textColor = rgb(C_NAVY, 1);
    NSTextField *in = info.length ? [NSTextField wrappingLabelWithString:info] : nil;
    if (in) { in.font = round_font(13, NSFontWeightMedium); in.textColor = rgb(C_NAVY, 0.72); in.selectable = NO; }
    CGFloat infoH = in ? ceil([in.cell cellSizeForBounds:NSMakeRect(0, 0, tw, 1000)].height) : 0, textH = 24 + (in ? 4 + infoH : 0), headH = fmax(ICON, textH);
    NSTextField *f = [NSTextField textFieldWithString:initial]; f.font = round_font(22, NSFontWeightSemibold); f.textColor = rgb(C_NAVY, 1);
    f.bezeled = NO; f.bordered = NO; f.drawsBackground = NO; f.focusRingType = NSFocusRingTypeNone; f.delegate = s;
    f.lineBreakMode = NSLineBreakByClipping; f.cell.scrollable = YES; f.cell.usesSingleLineMode = YES;
    if (placeholder.length) f.placeholderAttributedString = [[NSAttributedString alloc] initWithString:placeholder attributes:@{NSFontAttributeName: f.font, NSForegroundColorAttributeName: rgb(C_NAVY, 0.35)}];
    CGFloat lh = ceil([f.cell cellSizeForBounds:NSMakeRect(0, 0, 1000, 1000)].height);
    DMPill *ok = sheet_button(T(T_OK), @"A", YES, @"\r", NSModalResponseOK, s), *cancel = sheet_button(T(T_CANCEL), @"B", NO, @"\033", NSModalResponseCancel, s);
    CGFloat yb = 24, yf = yb + BH + 20, yh = yf + FH + 22, H = yh + headH + P;
    NSPanel *pn = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, W, H) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];   // 當單掛上時沒有標題欄；獨立對話框時標題欄留空 | no title bar when attached as a sheet; an empty title bar as a standalone dialog
    pn.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];   // 遊戲配色不隨深色模式變 | the game palette does not follow dark mode
    DMGround *bg = [[DMGround alloc] initWithFrame:NSMakeRect(0, 0, W, H)]; pn.contentView = bg;
    DMIcon *icon = [[DMIcon alloc] initWithFrame:NSMakeRect(P - 6, yh + headH - ICON, ICON, ICON)]; icon.image = NSApp.applicationIconImage;
    CGFloat ty = yh + headH - (headH - textH) / 2;   // 文字塊與圖標竪向居中 | the text block is vertically centred on the icon
    ti.frame = NSMakeRect(tx, ty - 24, tw, 24);
    if (in) in.frame = NSMakeRect(tx, ty - 28 - infoH, tw, infoH);
    DMCapsuleField *cap = [[DMCapsuleField alloc] initWithFrame:NSMakeRect(P, yf, W - 2 * P, FH)];
    f.frame = NSMakeRect(22, 4 + (FH - 4 - lh) / 2, W - 2 * P - 44, lh); [cap addSubview:f];
    ok.frame = NSMakeRect(W - P - BW, yb, BW, BH); cancel.frame = NSMakeRect(W - P - BW - 14 - BW, yb, BW, BH);
    NSTextField *cnt = [NSTextField labelWithString:@""]; cnt.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightSemibold];
    cnt.frame = NSMakeRect(P + 4, yb + 4 + (BH - 4 - 18) / 2, 100, 18); cnt.hidden = s.max == 0;
    for (NSView *x in @[icon, ti, cap, ok, cancel, cnt]) [bg addSubview:x];
    if (in) [bg addSubview:in];
    pn.initialFirstResponder = f; pn.defaultButtonCell = ok.cell;
    s.panel = pn; s.field = f; s.count = cnt; s.ok = ok; [s refresh];
    return s;
}

// 軟鍵盤輸入框（front.h）：主線程在遊戲窗口上掛這張輸入單（窗口裡有別的單或窗口不可見時改成獨立對話框），客體線程等結果。無窗口模式不彈（返回 -1，調用方按取消）
// Software keyboard input box (front.h): the main thread attaches this input sheet to the game window (a standalone dialog when another sheet is up or the window is not visible) and the guest thread waits for the result. Not shown in windowless mode (returns -1, the caller treats it as cancel)
int front_text_input(const char *title, const char *sub, const char *guide, const char *initial, int max_chars, char *out, int out_cap) {
    if (!g_layer) return -1;
    __block int r = 0;
    __block NSString *text = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        capture_set(0);
        if (g_win.miniaturized) [g_win deminiaturize:nil];
        NSString *t = title && *title ? [NSString stringWithUTF8String:title] : nil, *sb = sub && *sub ? [NSString stringWithUTF8String:sub] : nil;
        NSString *gd = guide && *guide ? [NSString stringWithUTF8String:guide] : nil, *init = initial ? [NSString stringWithUTF8String:initial] : nil;
        DMInputSheet *s = input_sheet(t.length ? t : T(T_INPUT), sb ?: @"", gd ?: @"", init ?: @"", max_chars);
        void (^finish)(NSModalResponse) = ^(NSModalResponse resp) { r = resp == NSModalResponseOK; text = s.field.stringValue; [s.panel orderOut:nil]; dispatch_semaphore_signal(done); };
        if (g_win.attachedSheet || !g_win.visible) { [s.panel center]; [s.field selectText:nil]; finish([NSApp runModalForWindow:s.panel]); }
        else { [g_win beginSheet:s.panel completionHandler:finish]; [s.panel makeFirstResponder:s.field]; [s.field selectText:nil]; }
    });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (!r) return 0;
    snprintf(out, out_cap, "%s", text.UTF8String ?: "");   // 截斷按 UTF-16 單元在 hle_swkbd.c 統一做 | truncation is done uniformly in hle_swkbd.c in UTF-16 units
    return 1;
}

// 存檔沒寫成（hle_fs.c 調，蓋過它的弱實現）：在遊戲窗口上掛一張提示；同一時間只掛一張 | Save not written (called by hle_fs.c, overriding its weak implementation): attach a notice to the game window; only one at a time
void front_save_failed(int err) {
    LOG("前端：存檔沒寫成（errno=%d），提示玩家", err);
    if (!g_layer) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        static int showing; if (showing) return;
        showing = 1; capture_set(0);
        NSAlert *a = [NSAlert new]; a.alertStyle = NSAlertStyleWarning; a.messageText = T(T_SAVE_FAIL);
        a.informativeText = err == ENOSPC ? T(T_SAVE_SPACE) : [NSString stringWithFormat:T(T_SAVE_OTHER), err];
        [a addButtonWithTitle:T(T_OK)];
        if (g_win.attachedSheet) { [a runModal]; showing = 0; }
        else [a beginSheetModalForWindow:g_win completionHandler:^(NSModalResponse r) { (void)r; showing = 0; }];
    });
}
