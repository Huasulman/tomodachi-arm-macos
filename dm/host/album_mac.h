// Mac「Extras」菜單的照片窗口（album_mac.m）：遊戲內存進相簿的照片。
// The photos window of the Mac "Extras" menu (album_mac.m): the photos the game saved to its album.
#pragma once

void album_open(void);                  // 打開（或帶到前面）照片窗口 | open the Photos window (or bring it to the front)
void album_show_folder(void);           // 在 Finder 打開相簿目錄 | open the album directory in Finder
const char *album_title(int which);     // 菜單標題：0「照片」、1「打開資料夾」 | menu titles: 0 "Photos", 1 "Open Folder"
