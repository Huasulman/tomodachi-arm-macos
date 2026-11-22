// Mac 控制窗口（controls_mac.m）與前端（front_mac.m）之間的接口：鍵盤改鍵寫玩家的鍵位表，手柄改鍵存 defaults 的 PadMap。
// Interface between the Mac Controls window (controls_mac.m) and the front end (front_mac.m): keyboard remaps go into the player's keymap, controller remaps into PadMap in the defaults.
#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>

// 實體手柄鍵，按位置（Xbox 佈局的名字）。GameController 與 XInput 都先換成這些位，再按鍵位表換成 Switch 鍵
// Physical controller buttons, by position (named after the Xbox layout). GameController and XInput are both turned into these bits first, then into Switch buttons through the mapping
enum { P_SOUTH, P_EAST, P_WEST, P_NORTH, P_LB, P_RB, P_LT, P_RT, P_START, P_BACK, P_LS, P_RS, P_UP, P_DOWN, P_LEFT, P_RIGHT, P_N };

// front_mac.m 提供 | provided by front_mac.m
int front_ui_lang(void);                                  // 0 英文、1 繁體中文、2 西班牙文 | 0 English, 1 Traditional Chinese, 2 Spanish
const char *front_keymap_path(void);                      // 玩家的鍵位表（NULL = 沒有） | the player's keymap (NULL = none)
const char *front_keymap_defaults(void);                  // 默認鍵位表文本 | the default keymap text
const char *front_keyname(int keycode);                   // 鍵碼 → 鍵位表裡的鍵名（NULL = 不能映射） | key code → key name in the keymap (NULL = not mappable)
void front_keymap_apply(void);                            // 鍵位表文件改了：重讀 | the keymap file changed: reread it
int front_input_mode(void);                               // 0 全部、1 只用手柄、2 只用鍵盤滑鼠 | 0 everything, 1 controller only, 2 keyboard and mouse only
void front_input_mode_set(int mode);
void front_padmap_get(int map[16], int *custom);          // 每個 Switch 鍵（DM_BTN_* 位序）對應的實體鍵 P_*，-1 = 不映射 | the physical button P_* for each Switch button (DM_BTN_* bit order), -1 = unmapped
void front_padmap_set(const int *map);                    // NULL = 回到按手柄類型的默認 | NULL = back to the per-controller-type default
NSArray<NSString *> *front_pad_names(void);               // 接著的手柄名 | names of the connected controllers

// controls_mac.m 提供 | provided by controls_mac.m
void controls_open(void);                                 // 打開（或帶到前面）控制窗口 | open the Controls window (or bring it to the front)
void controls_pad_phys(uint32_t phys);                    // 實體鍵狀態變了（主線程，錄手柄鍵用） | the physical button state changed (main thread, for capturing controller buttons)
