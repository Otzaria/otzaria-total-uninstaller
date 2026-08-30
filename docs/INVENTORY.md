# מלאי היעדים — מה נמחק ולמה

כל רשומה כאן מגיעה מקוד המקור של אוצריא או מהמתקין, כולל מגרסאות שכבר אינן בשימוש.
מטרת המסמך: שכל יעד יהיה ניתן לאימות מול המקור שיצר אותו, ושלא יהיו יעדים "כי ליתר ביטחון".

## תיקיות התקנה

| נתיב | מקור |
|---|---|
| `%ProgramFiles%\Otzaria` | `installer/otzaria.iss` — `GetDefaultInstallDir` → `{autopf}\Otzaria` |
| `%ProgramFiles%\אוצריא` | ברירת המחדל בגרסאות שבהן `MyAppName` שימש גם כשם התיקייה |
| `%ProgramFiles(x86)%\…` | התקנת 32 סיביות היסטורית |
| `C:\אוצריא` | נתיב שנסרק ע"י `FindPreviousInstallDir` במתקין — התקנות ישנות בשורש הכונן |
| `%LOCALAPPDATA%\Programs\Otzaria` | התקנת משתמש (`IsAdminInstallMode = false`) |

תיקיות התקנה נוספות מתגלות דינמית מתוך `InstallLocation` / `UninstallString` שברשומות
ההסרה, כך שגם נתיב מותאם שהמשתמש בחר מכוסה.

## שורשי נתונים

`AppPaths.getDataRootPath()` (`lib/core/app_paths.dart`) קובע את שורש הנתונים:
`%APPDATA%\otzaria` בהתקנת משתמש, `%ProgramData%\otzaria` בהתקנת מנהל. מתחתיו יושבים
`books`, `index`, `databases`, `plugins`, `per_book_settings`, `webview2`, `logs`,
קובצי ה-Hive (`bookmarks`, `history`, `tabs`, `workspaces`, `app_preferences`,
`error_reports_queue`, `plugin_reports_queue`) והמסמנים (`library_loaded.marker`,
`library_path.txt`).

| נתיב | מקור |
|---|---|
| `%APPDATA%\otzaria` | שורש הנתונים הנוכחי |
| `%APPDATA%\אוצריא` | `shared_preferences` נכתב ל-`%APPDATA%\<CompanyName>\<ProductName>`; ב-`windows/runner/Runner.rc` שני השדות היו `אוצריא` |
| `%APPDATA%\Otzaria` | `CompanyName` בגרסאות הביניים |
| `%APPDATA%\com.example\otzaria` | `CompanyName` בגרסאות המוקדמות (ברירת המחדל של Flutter) |
| `%LOCALAPPDATA%\otzaria` | מטמון |
| `%ProgramData%\otzaria` | שורש הנתונים בהתקנת מנהל — מזוהה גם ע"י `OrphanLibraryService` שבתוכנה עצמה |
| `Documents\otzaria` | שורש היסטורי מבוסס `getApplicationDocumentsDirectory` |

## ספרייה ואינדקס

הספרים והאינדקס יושבים תחת שורש הנתונים, אלא אם המשתמש העביר אותם. הנתיב שנבחר נרשם
ב-`library_path.txt` שבשורש הנתונים (`AppPaths.libraryPathRecordFileName`), ולכן הסורק
קורא אותו **לפני** שהוא מוחק את השורש.

שורש הספרייה עשוי להיות תיקייה שהמשתמש בחר ושיש בה עוד תוכן שלו, ולכן השורש עצמו
לעולם אינו נמחק — נמחקות ממנו רק תיקיות בשמות שאוצריא יוצרת: `books`, `index`,
`databases`, `dictionaries`, `library_update_cache`, `pdfium`, `per_book_settings`.

## גיבויים

`AppPaths.getDefaultBackupPath()` — `Documents\אוצריא - גיבויים`, ובנוסף `backups`
שבתוך שורש הנתונים (נמחק יחד איתו).

## רכיבים נלווים

| נתיב | מה זה |
|---|---|
| `%LOCALAPPDATA%\Otzaria Plugin Store` | אפליקציית חנות התוספים (מתקין NSIS נפרד, רשומת הסרה משלה) |
| `%LOCALAPPDATA%\com.otzaria.store` | פרופיל ה-WebView2 של החנות |
| `%ProgramData%\OtzariaDesktop` | סוכן/שרת נלווה |

## רישום Windows

### נכתב ע"י התוכנה בכל הפעלה

`PluginProtocolRegistrationService.buildWindowsRegistrationEntries` כותב ל-
`HKCU\Software\Classes`:

- `otzaria` (+ `DefaultIcon`, `shell\open\command`) — הפרוטוקול `otzaria://`
- `OtzariaPluginFile` (+ `EditFlags`, `DefaultIcon`, `shell\open\command`)
- `.otzplugin` (+ `Content Type` = `application/x-otzaria-plugin`)

אותם מפתחות נמחקים גם מ-`HKLM\Software\Classes` (המתקין כותב אותם ל-`HKA`, שהוא
`HKLM` בהתקנת מנהל), ובשני מבטי הרישום — 32 ו-64 סיביות.

### נכתב ע"י המתקין

- `HKLM\…\Uninstall\{EEC4F712-CD05-4D15-A753-509E840A51A5}_is1` — ה-`AppId` מ-`otzaria.iss`
- אותה רשומה תחת `HKCU` בהתקנת משתמש
- רכיב `PATH` בתיקיית ההתקנה (`ShouldAddToSystemPath` / `ShouldAddToUserPath`) —
  נמחק כרכיב בודד, ונכתב חזרה כ-`REG_EXPAND_SZ` בלי הרחבה, אחרת `%SystemRoot%` נצרב כטקסט

### נכתב ע"י Windows בעקבות ההרצה

- `Notifications\Settings\Otzaria.Otzaria` — ה-AppUserModelID שנקבע ב-`windows/runner/main.cpp`
- `Notifications\Settings\com.otzaria.app` — ה-AppUserModelID של שירות ההתראות בלוח השנה
- `MuiCache`, `AppCompatFlags\Compatibility Assistant\Store`, `AppCompatFlags\Layers`,
  `Search\JumplistData`, `Explorer\FeatureUsage\AppLaunch` ו-`AppSwitched` — נמחקים בהם
  **ערכים בודדים** שמזכירים את התוכנה, לא המפתח כולו
- `Explorer\FileExts\.otzplugin`, `Explorer\RecentDocs\.otzplugin`

## קיצורים

המתקין יוצר קיצור בתפריט ההתחלה, בשולחן העבודה וקיצור "לוח שנה" עם
`otzaria://open/calendar`. בנוסף, `PluginShortcutService` מאפשר לתוסף ליצור קיצור
**בשם כלשהו** בשולחן העבודה או בתפריט ההתחלה. לכן הסורק אינו מסתמך על שם הקובץ אלא
פותח כל `.lnk` בשולחן העבודה, בתפריט ההתחלה ובסרגל המשימות ובודק את היעד ואת הפרמטרים.

## קבצים זמניים

מ-`Directory.systemTemp` בקוד: `otzaria_update`, `otzaria_plugin_uploads`,
`otzaria_temp_index_*`, `otzaria-settings-*`, `otz_plugin_*`, וקובצי ה-PID של
מופע יחיד. בנוסף כל `%TEMP%\otzaria*`.

## עקבות מערכת

- `%LOCALAPPDATA%\CrashDumps\otzaria.exe*.dmp`
- דוחות WER ב-`ReportArchive` / `ReportQueue` שמזכירים את התוכנה (`-Deep`)
- `%SystemRoot%\Prefetch\OTZARIA.EXE-*.pf`
- רשימות קפיצה — שם הקובץ הוא גיבוב של ה-AppUserModelID ולכן נבדק **תוכן** הקובץ
  (נתיב ה-EXE מופיע בו כ-UTF-16LE) (`-Deep`)
- כללי חומת אש שנוצרו בעקבות שרת ה-localhost של ממשק הקבצים לתוספים
- משימות מתוזמנות שמפעילות את התוכנה

## Linux

| נתיב | מקור |
|---|---|
| `~/.local/share/otzaria` | שורש הנתונים |
| `~/.local/share/applications/otzaria.desktop` | `_ensureLinuxRegistration` |
| `~/.local/share/mime/packages/otzaria-plugin.xml` | אותה פונקציה |
| `~/.local/share/icons/hicolor/*/mimetypes/application-x-otzaria-plugin.png` | `_installLinuxMimeIcon` |
| `/var/lib/otzaria` | נתיב מערכתי בחבילות ההפצה |
| `/opt/otzaria`, `/usr/local/otzaria`, `/usr/bin/otzaria` | יעדי התקנה |

לאחר המחיקה מורצים `update-mime-database`, `update-desktop-database` ו-
`gtk-update-icon-cache` כדי שהשיוכים ייעלמו מהמעטפת.

## macOS

`/Applications/Otzaria.app`, `~/Library/Application Support/otzaria`,
`/Library/Application Support/Otzaria`, ולכל אחד משני מזהי החבילה ההיסטוריים
(`com.mendelg.otzaria`, `org.otzaria.otzaria`): `Preferences/*.plist`, `Caches`,
`WebKit`, `HTTPStorages`, `Saved Application State`. בסיום מורץ `lsregister -kill -r`
כדי לנקות את רישום השיוכים.

## מה במפורש לא נמחק

- מנוע WebView2 של Microsoft — רכיב מערכת שתוכנות אחרות משתמשות בו
- גופנים שהמשתמש התקין בעצמו — אוצריא סורקת גופנים אך לעולם אינה מתקינה
- ספריות זמן ריצה של Visual C++
- מאגר קוד המקור של אוצריא, אם הוא קיים במחשב — הוא לא "התקנה"
- קבצי `.otzplugin` וגיבויי JSON ששמורים אצל המשתמש, אלא אם ניתן `-IncludeUserFiles`
