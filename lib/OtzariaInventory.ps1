<#
.SYNOPSIS
    מלאי היעדים של אוצריא ב-Windows — כל מה שהתוכנה כתבה למחשב אי־פעם.
.DESCRIPTION
    כל רשומה מתארת יעד אחד: קובץ/תיקייה, מפתח רישום, ערך רישום או סריקה דינמית.
    המקור לכל רשומה מתועד ב-docs/INVENTORY.md.
#>

# קבוצות (Group):
#   app       - התוכנה עצמה: תיקיות התקנה, קיצורים, רישומי הסרה
#   data      - נתוני משתמש: הגדרות, סימניות, טאבים, תוספים, מטמון
#   library   - הספרייה (הספרים) והאינדקס — עשרות ג'יגה
#   backups   - גיבויים שהתוכנה יצרה
#   related   - רכיבים נלווים (חנות התוספים, OtzariaDesktop)
#   traces    - עקבות מערכת: temp, prefetch, MuiCache, רשימות קפיצה
#   userfiles - קבצים של המשתמש עצמו (‎.otzplugin‎ שהוריד וכד') — דיווח בלבד

$script:OtzariaAppId = '{EEC4F712-CD05-4D15-A753-509E840A51A5}_is1'

function New-OtzTarget {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('Path', 'PathGlob', 'RegKey', 'RegValueMatch', 'Scan')][string]$Kind,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][ValidateSet('app', 'data', 'library', 'backups', 'related', 'traces', 'userfiles')][string]$Group,
        [ValidateSet('User', 'Machine')][string]$Scope = 'User',
        [ValidateSet('Default', 'Both')][string]$View = 'Default',
        [string]$Match,
        [string]$Note = ''
    )
    [pscustomobject]@{
        Id    = $Id
        Kind  = $Kind
        Target = $Target
        Group = $Group
        Scope = $Scope
        View  = $View
        Match = $Match
        Note  = $Note
    }
}

function Get-OtzariaInventory {
    [CmdletBinding()]
    param()

    $heb   = 'אוצריא'
    $appId = $script:OtzariaAppId
    $pf    = $env:ProgramFiles
    $pf86  = ${env:ProgramFiles(x86)}
    $pd    = $env:ProgramData
    $lad   = $env:LOCALAPPDATA
    $rad   = $env:APPDATA
    $up    = $env:USERPROFILE
    $docs  = Join-Path $up 'Documents'

    # ── תיקיות התקנה ────────────────────────────────────────────────────────
    New-OtzTarget -Id 'install.pf.en' -Kind Path -Group app -Scope Machine -Target (Join-Path $pf 'Otzaria') -Note 'התקנת מנהל (ברירת המחדל הנוכחית)'
    New-OtzTarget -Id 'install.pf.he' -Kind Path -Group app -Scope Machine -Target (Join-Path $pf $heb) -Note 'התקנת מנהל בשם עברי (גרסאות ישנות)'
    if ($pf86) {
        New-OtzTarget -Id 'install.pf86.en' -Kind Path -Group app -Scope Machine -Target (Join-Path $pf86 'Otzaria')
        New-OtzTarget -Id 'install.pf86.he' -Kind Path -Group app -Scope Machine -Target (Join-Path $pf86 $heb)
    }
    New-OtzTarget -Id 'install.rootdrive.he' -Kind Path -Group app -Scope Machine -Target (Join-Path "$env:SystemDrive\" $heb) -Note 'נתיב התקנה ישן בשורש הכונן'
    New-OtzTarget -Id 'install.rootdrive.en' -Kind Path -Group app -Scope Machine -Target (Join-Path "$env:SystemDrive\" 'Otzaria') -Note 'ברירת המחדל עד commit c5a1ebd44 — C:\Otzaria'
    New-OtzTarget -Id 'install.peruser.en' -Kind Path -Group app -Target (Join-Path $lad 'Programs\Otzaria') -Note 'התקנת משתמש'
    New-OtzTarget -Id 'install.peruser.he' -Kind Path -Group app -Target (Join-Path $lad "Programs\$heb")

    # ── שורשי נתונים (AppPaths.getDataRootPath לאורך הדורות) ────────────────
    New-OtzTarget -Id 'data.roaming' -Kind Path -Group data -Target (Join-Path $rad 'otzaria') -Note 'שורש הנתונים הנוכחי: hive, תוספים, webview2, logs'
    New-OtzTarget -Id 'data.roaming.he' -Kind Path -Group data -Target (Join-Path $rad $heb) -Note 'shared_preferences ישן (CompanyName עברי)'
    New-OtzTarget -Id 'data.roaming.cap' -Kind Path -Group data -Target (Join-Path $rad 'Otzaria') -Note 'CompanyName "Otzaria" (גרסאות ביניים)'
    New-OtzTarget -Id 'data.roaming.example' -Kind Path -Group data -Target (Join-Path $rad 'com.example\otzaria') -Note 'CompanyName "com.example" (גרסאות מוקדמות)'
    New-OtzTarget -Id 'data.local' -Kind Path -Group data -Target (Join-Path $lad 'otzaria')
    New-OtzTarget -Id 'data.local.he' -Kind Path -Group data -Target (Join-Path $lad $heb) -Note 'נתיב legacy שהמתקין הרשמי עדיין מנקה'
    New-OtzTarget -Id 'data.programdata' -Kind Path -Group data -Scope Machine -Target (Join-Path $pd 'otzaria') -Note 'נתוני התקנת מנהל — כולל books ו-index'
    New-OtzTarget -Id 'data.docs' -Kind Path -Group data -Target (Join-Path $docs 'otzaria') -Note 'שורש ישן בתיקיית המסמכים'
    New-OtzTarget -Id 'data.docs.he' -Kind Path -Group library -Target (Join-Path $docs $heb)

    # ── גיבויים ─────────────────────────────────────────────────────────────
    New-OtzTarget -Id 'backups.docs' -Kind Path -Group backups -Target (Join-Path $docs "$heb - גיבויים") -Note 'תיקיית הגיבויים בברירת המחדל'
    New-OtzTarget -Id 'backups.docs.legacy' -Kind Path -Group backups -Target (Join-Path $docs 'OtzariaBackups') -Note 'נתיב הגיבויים עד commit 0de51c8fc'

    # ── רכיבים נלווים ───────────────────────────────────────────────────────
    New-OtzTarget -Id 'store.app' -Kind Path -Group related -Target (Join-Path $lad 'Otzaria Plugin Store') -Note 'אפליקציית חנות התוספים'
    New-OtzTarget -Id 'store.webview' -Kind Path -Group related -Target (Join-Path $lad 'com.otzaria.store') -Note 'פרופיל WebView2 של החנות'
    New-OtzTarget -Id 'store.roaming' -Kind Path -Group related -Target (Join-Path $rad 'Otzaria Plugin Store')
    New-OtzTarget -Id 'desktop.agent' -Kind Path -Group related -Scope Machine -Target (Join-Path $pd 'OtzariaDesktop') -Note 'OtzariaDesktop — סוכן/שרת נלווה'
    New-OtzTarget -Id 'desktop.agent.root' -Kind Path -Group related -Scope Machine -Target (Join-Path "$env:SystemDrive\" 'OtzariaDesktop') -Note 'אותו סוכן בשורש הכונן'

    # ── קבצים זמניים ────────────────────────────────────────────────────────
    foreach ($pattern in @('otzaria*', 'otz_plugin*', 'otzaria_update', 'otzaria_plugin_uploads', 'otzaria_temp_index_*', 'otzaria-settings-*')) {
        New-OtzTarget -Id "temp.$pattern" -Kind PathGlob -Group traces -Target (Join-Path $env:TEMP $pattern)
    }
    New-OtzTarget -Id 'temp.machine' -Kind PathGlob -Group traces -Scope Machine -Target (Join-Path $env:SystemRoot 'Temp\otzaria*')

    # ── עקבות מערכת ─────────────────────────────────────────────────────────
    New-OtzTarget -Id 'trace.crashdumps' -Kind PathGlob -Group traces -Target (Join-Path $lad 'CrashDumps\otzaria.exe*.dmp')
    New-OtzTarget -Id 'trace.wer' -Kind Scan -Group traces -Target 'wer' -Note 'דוחות שגיאה של Windows שמזכירים את otzaria.exe'
    New-OtzTarget -Id 'trace.prefetch' -Kind PathGlob -Group traces -Scope Machine -Target (Join-Path $env:SystemRoot 'Prefetch\OTZARIA.EXE-*.pf')
    New-OtzTarget -Id 'trace.jumplists' -Kind Scan -Group traces -Target 'jumplists' -Note 'רשימות קפיצה (AutomaticDestinations / CustomDestinations)'
    New-OtzTarget -Id 'trace.recent' -Kind PathGlob -Group traces -Target (Join-Path $rad 'Microsoft\Windows\Recent\*otzplugin*.lnk')

    # ── רישום: שיוכי קבצים ופרוטוקול (נכתבים מחדש בכל הפעלה של התוכנה) ─────
    foreach ($hive in @('HKCU', 'HKLM')) {
        $scope = if ($hive -eq 'HKLM') { 'Machine' } else { 'User' }
        New-OtzTarget -Id "reg.$hive.proto" -Kind RegKey -Group app -Scope $scope -View Both -Target "$hive\Software\Classes\otzaria" -Note 'הפרוטוקול otzaria://'
        New-OtzTarget -Id "reg.$hive.progid" -Kind RegKey -Group app -Scope $scope -View Both -Target "$hive\Software\Classes\OtzariaPluginFile"
        New-OtzTarget -Id "reg.$hive.ext" -Kind RegKey -Group app -Scope $scope -View Both -Target "$hive\Software\Classes\.otzplugin"
    }
    New-OtzTarget -Id 'reg.fileexts' -Kind RegKey -Group app -Target 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.otzplugin'
    New-OtzTarget -Id 'reg.recentdocs' -Kind RegKey -Group traces -Target 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs\.otzplugin'

    # ── רישום: רשומות הסרה ──────────────────────────────────────────────────
    New-OtzTarget -Id 'reg.uninstall.machine' -Kind RegKey -Group app -Scope Machine -View Both -Target "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$appId"
    New-OtzTarget -Id 'reg.uninstall.user' -Kind RegKey -Group app -View Both -Target "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$appId"
    New-OtzTarget -Id 'reg.uninstall.store' -Kind RegKey -Group related -Target 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Otzaria Plugin Store'
    New-OtzTarget -Id 'reg.apppaths' -Kind RegKey -Group app -Scope Machine -View Both -Target 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\otzaria.exe'

    # ── רישום: התראות (שני ה-AppUserModelID שהתוכנה השתמשה בהם) ────────────
    New-OtzTarget -Id 'reg.notifications.aumid' -Kind RegKey -Group traces -Target 'HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Otzaria.Otzaria'
    New-OtzTarget -Id 'reg.notifications.app' -Kind RegKey -Group traces -Target 'HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\com.otzaria.app'

    # ── רישום: ערכים בתוך מפתחות משותפים — נמחק הערך, לא המפתח ─────────────
    New-OtzTarget -Id 'regvalue.muicache' -Kind RegValueMatch -Group traces -Match 'otzaria' -Target 'HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
    New-OtzTarget -Id 'regvalue.compat.user' -Kind RegValueMatch -Group traces -Match 'otzaria' -Target 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store'
    New-OtzTarget -Id 'regvalue.compat.machine' -Kind RegValueMatch -Group traces -Scope Machine -Match 'otzaria' -Target 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store'
    New-OtzTarget -Id 'regvalue.layers' -Kind RegValueMatch -Group traces -Match 'otzaria' -Target 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    New-OtzTarget -Id 'regvalue.jumplistdata' -Kind RegValueMatch -Group traces -Match 'otzaria' -Target 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search\JumplistData'
    New-OtzTarget -Id 'regvalue.applaunch' -Kind RegValueMatch -Group traces -Match 'otzaria' -Target 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppLaunch'
    New-OtzTarget -Id 'regvalue.appswitched' -Kind RegValueMatch -Group traces -Match 'otzaria' -Target 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppSwitched'

    # ── סריקות דינמיות ──────────────────────────────────────────────────────
    New-OtzTarget -Id 'scan.shortcuts' -Kind Scan -Group app -Target 'shortcuts' -Note 'קיצורים (כולל כאלה שתוספים יצרו) שהיעד שלהם otzaria.exe'
    New-OtzTarget -Id 'scan.path' -Kind Scan -Group app -Target 'path' -Note 'רכיבי PATH שמצביעים לתיקיית ההתקנה'
    New-OtzTarget -Id 'scan.firewall' -Kind Scan -Group traces -Target 'firewall' -Note 'כללי חומת אש שנוצרו עבור otzaria.exe'
    New-OtzTarget -Id 'scan.tasks' -Kind Scan -Group traces -Target 'tasks' -Note 'משימות מתוזמנות שמפעילות את התוכנה'
    New-OtzTarget -Id 'scan.portable' -Kind Scan -Group data -Target 'portable' -Note 'התקנות ניידות (portable.marker) בכונני המחשב'
    New-OtzTarget -Id 'scan.library' -Kind Scan -Group library -Target 'library' -Note 'ספרייה שהמשתמש העביר לנתיב מותאם (library_path.txt)'
    New-OtzTarget -Id 'scan.profiles' -Kind Scan -Group data -Scope Machine -Target 'profiles' -Note 'נתוני אוצריא בפרופילים של משתמשים אחרים — כמו במתקין הרשמי'
    New-OtzTarget -Id 'scan.userfiles' -Kind Scan -Group userfiles -Target 'userfiles' -Note 'קבצי ‎.otzplugin‎ וגיבויי JSON ששמורים אצל המשתמש — דיווח בלבד'
}
