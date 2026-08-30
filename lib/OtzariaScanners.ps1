<#
.SYNOPSIS
    סריקות דינמיות — יעדים שאי אפשר לרשום מראש כי שמם או מיקומם משתנים.
.DESCRIPTION
    כל סורק מחזיר "ממצאים": אובייקטים עם תיאור ועם Remove — scriptblock שמבצע
    את ההסרה בפועל. הסורקים לעולם אינם מוחקים בעצמם.

    כלל ברזל: שם שמכיל "otzaria" אינו הוכחת בעלות. כל יעד שנמחק כתיקייה שלמה
    חייב לעבור מבחן בעלות — קובץ או מבנה שרק אוצריא יוצרת.
#>

function New-OtzFinding {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Group,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Target,
        [long]$SizeBytes = 0,
        [string]$Note = '',
        [scriptblock]$Remove
    )
    [pscustomobject]@{
        Id     = $Id
        Group  = $Group
        Kind   = $Kind
        Target = $Target
        SizeBytes = $SizeBytes
        Note   = $Note
        Remove = $Remove
    }
}

# ── מבחני בעלות ─────────────────────────────────────────────────────────────

# סינון גס בלבד — לעולם לא כעילה יחידה למחיקת תיקייה.
function Test-OtzOtzariaPath {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match 'otzaria' -or $Value -match 'אוצריא')
}

# Test-Path זורק על מחרוזת שאינה נתיב חוקי (ארגומנט של משימה, ערך רישום
# פגום). מבחני הבעלות חייבים להחזיר False ולא להפיל את הסריקה.
function Test-OtzPathSafe {
    param([string]$Path, [switch]$Container)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        if ($Container) { return (Test-Path -LiteralPath $Path -PathType Container) }
        return (Test-Path -LiteralPath $Path)
    } catch { return $false }
}

# תיקיית התקנה: חייבת להכיל את ה-EXE של אוצריא ואת חבילת ה-assets של Flutter
# שלצידו. תיקייה שרק שמה "Otzaria" אינה עוברת.
function Test-OtzInstallDirectory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -lt 6) { return $false }
    if (-not (Test-OtzPathSafe $Path -Container)) { return $false }
    if (-not (Test-OtzPathSafe (Join-Path $Path 'otzaria.exe'))) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Path 'data\flutter_assets'))
}

# תיקיית התקנה או שארית שלה: גם אחרי מחיקת ה-EXE נשארים סימני מתקין. משמש
# למטרות המלאי, ששמן לבדו ("Otzaria") עלול להתנגש עם תיקייה של המשתמש —
# למשל ריפו קוד המקור, ש-Windows רואה כזהה לנתיב ההתקנה ההיסטורי.
function Test-OtzInstallOwnership {
    param([string]$Path)
    if (Test-OtzInstallDirectory $Path) { return $true }
    if (-not (Test-OtzPathSafe $Path -Container)) { return $false }
    # otzaria.exe לבדו אינו סימן: build artifact שהונח בריפו המקור נראה זהה.
    # התקנה אמיתית תמיד נושאת גם את חבילת ה-assets (נבדק ב-Test-OtzInstallDirectory)
    # או סימן שהמתקין כתב.
    # unins000.exe אף הוא אינו סימן: הוא של Inno Setup, ומופיע בכל תוכנה שנארזה בו.
    foreach ($marker in @('system_install.marker', 'portable.marker')) {
        if (Test-OtzPathSafe (Join-Path $Path $marker)) { return $true }
    }
    return $false
}

# קובץ הרצה של אוצריא. שם הקובץ לבדו אינו מספיק כשהקובץ קיים — נדרשת תיקיית
# התקנה סביבו או פרטי גרסה של אוצריא. קובץ שכבר נמחק מתקבל כשארית.
function Test-OtzOwnedExecutable {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $dir = Split-Path -Parent $Path
    if ($dir -and (Test-OtzInstallDirectory $dir)) { return $true }
    if ($dir -and (Split-Path -Leaf $dir) -eq 'Otzaria Plugin Store') { return $true }
    if ((Split-Path -Leaf $Path) -ne 'otzaria.exe') { return $false }
    if (-not (Test-OtzPathSafe $Path)) { return $true }
    try {
        $info = (Get-Item -LiteralPath $Path -ErrorAction Stop).VersionInfo
        return ((Test-OtzOtzariaPath $info.ProductName) -or (Test-OtzOtzariaPath $info.CompanyName))
    } catch { return $false }
}

# קובץ ששייך לרכיב של אוצריא: ההורה שלו הוא תיקייה ייעודית בשם מדויק —
# לא התאמת substring. משמש למשימות שמריצות סקריפט דרך powershell.exe.
function Test-OtzOwnedComponentPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $dir = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($dir)) { return $false }
    return ((Split-Path -Leaf $dir) -in @('OtzariaDesktop', 'Otzaria', 'אוצריא', 'Otzaria Plugin Store'))
}

# שורש נתונים: תיקייה שאוצריא יצרה בה את מבנה העבודה שלה. שם התיקייה לבדו
# ("otzaria") אינו מספיק — הוא מתנגש עם תיקיות עבודה של המשתמש.
function Test-OtzDataRootMarkers {
    param([string]$Path)
    if (-not (Test-OtzPathSafe $Path -Container)) { return $false }

    foreach ($marker in @('library_loaded.marker', 'library_path.txt', 'shared_preferences.json',
                          'per_book_settings', 'webview2')) {
        if (Test-OtzPathSafe (Join-Path $Path $marker)) { return $true }
    }
    if ((Get-ChildItem -LiteralPath $Path -Filter '*.hive' -Force -ErrorAction SilentlyContinue |
        Select-Object -First 1)) { return $true }

    # תת-תיקיות בשמות גנריים ('books', 'index', 'databases', 'plugins') אינן
    # ראיה בפני עצמן — כל אחת חייבת לעבור את מבחן הבעלות שלה.
    if (Test-OtzBooksFolder (Join-Path $Path 'books')) { return $true }
    if (Test-OtzIndexFolder (Join-Path $Path 'index')) { return $true }
    if (Test-OtzDatabasesFolder (Join-Path $Path 'databases')) { return $true }
    return (Test-OtzPathSafe (Join-Path $Path 'plugins\installed') -Container)
}

# שמות הבן של השורשים המקוננים ההיסטוריים
# (%APPDATA%\<CompanyName>\<ProductName>) — רשימה סגורה, לא סריקה של כל בן.
$script:OtzNestedDataRootNames = @('otzaria', 'אוצריא')

# שורשי נתונים מקוננים: shared_preferences נכתב ל-
# %APPDATA%\<CompanyName>\<ProductName>, ולכן השורש האמיתי יושב עומק אחד
# פנימה — %APPDATA%\אוצריא\אוצריא.
#
# הבן נסרק אך ורק בשמות המוצר המדויקים, ורק כדי לקרוא ממנו את ההעדפות.
# בן שרירותי אינו נסרק ואינו מאשר דבר: shared_preferences.json הוא שם גנרי
# של Flutter, ומוצר אחר תחת אותו CompanyName היה הופך למחיקת האב כולו.
$script:OtzariaProductFolderNames = @('otzaria', 'אוצריא')

function Get-OtzNestedDataRoots {
    param([string]$Path)
    if (-not (Test-OtzPathSafe $Path -Container)) { return }
    foreach ($name in $script:OtzariaProductFolderNames) {
        $child = Join-Path $Path $name
        if ((Test-OtzPathSafe $child -Container) -and (Test-OtzDataRootMarkers $child)) { $child }
    }
}

# שורש נתונים מאושר אך ורק לפי סימנים שנמצאים בו ישירות. השורשים המקוננים
# ההיסטוריים הם יעדים נפרדים במלאי, ולא נגזרים מהאב.
function Test-OtzDataRootOwnership {
    param([string]$Path)
    return (Test-OtzDataRootMarkers $Path)
}

# תיקיית מילונים — קבצי המילון שאוצריא מורידה. 'dictionaries' הוא שם גנרי.
function Test-OtzDictionariesFolder {
    param([string]$Path)
    if (-not (Test-OtzPathSafe $Path -Container)) { return $false }
    foreach ($name in @('dictionary.json', 'Acronyms.json', 'otzaria_lexical.db', 'lexical.db')) {
        if (Test-OtzPathSafe (Join-Path $Path $name)) { return $true }
    }
    return $false
}

# מבחן הבעלות של יעד מוצהר — משמש גם למלאי הקבוע וגם לממצאים הדינמיים,
# כדי שלא ייווצר מסלול מחיקה שעוקף אותו.
function Test-OtzTargetOwnership {
    param([Parameter(Mandatory)]$Target)

    switch ($Target.Own) {
        'install'  { return (Test-OtzInstallOwnership $Target.Target) }
        'dataroot' { return (Test-OtzDataRootOwnership $Target.Target) }
    }

    if ($Target.Marker) {
        foreach ($marker in $Target.Marker) {
            if (Test-OtzPathSafe (Join-Path $Target.Target $marker)) { return $true }
        }
        return $false
    }
    return $true
}

# רשומת הסרה שמורצת — פעולה בלתי הפיכה, ולכן שם התצוגה אינו קובע: מוצר אחר
# ששמו מתחיל ב-"Otzaria" לא יורץ. הרכיבים הנלווים מזוהים בשם תיקייה מדויק.
function Test-OtzVendorOwnership {
    param(
        [string]$KeyName,
        [string]$InstallLocation,
        [string]$UninstallDirectory
    )
    if ($KeyName -like '*EEC4F712*') { return $true }
    if (Test-OtzInstallOwnership $InstallLocation) { return $true }
    if (Test-OtzInstallOwnership $UninstallDirectory) { return $true }
    foreach ($dir in @($InstallLocation, $UninstallDirectory)) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        if ((Split-Path -Leaf $dir) -in @('Otzaria Plugin Store', 'OtzariaDesktop')) { return $true }
    }
    return $false
}

# תיקיית ספרים — אותם סימנים שהמתקין הרשמי בודק ב-IsOtzariaBooksFolder,
# לפני DelTree על נתיב שהגיע מההגדרות של המשתמש.
function Test-OtzBooksFolder {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -lt 6) { return $false }
    if (-not (Test-OtzPathSafe $Path -Container)) { return $false }
    return ((Test-OtzPathSafe (Join-Path $Path 'seforim.db')) -or
            (Test-OtzPathSafe (Join-Path $Path 'otzar-HB_catalog.db')) -or
            (Test-OtzPathSafe (Join-Path $Path 'תלמוד בבלי')))
}

function Test-OtzIndexFolder {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -lt 6) { return $false }
    if (-not (Test-OtzPathSafe $Path -Container)) { return $false }
    return ((Test-OtzPathSafe (Join-Path $Path 'meta.json')) -or
            (Test-OtzPathSafe (Join-Path $Path 'tantivy.lock')) -or
            (Test-OtzPathSafe (Join-Path $Path '.tantivy-writer.lock')))
}

function Test-OtzDatabasesFolder {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -lt 6) { return $false }
    if (-not (Test-OtzPathSafe $Path -Container)) { return $false }
    foreach ($name in @('seforim.db', 'cache.db', 'otzaria_lexical.db', 'lexical.db',
                        'user_books.db', 'plugins_host.db', 'personal_notes.db',
                        'talmud_synopsis_pooled.db')) {
        if (Test-OtzPathSafe (Join-Path $Path $name)) { return $true }
    }
    return $false
}

# תיקייה מוכרת של המשתמש (Documents, Downloads, פרופיל, OneDrive) — גם אם
# המשתמש הצביע לשם כשורש הספרייה, אסור למחוק ממנה תיקיות בשמות גנריים.
function Test-OtzWellKnownUserFolder {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
    $normalized = $Path.TrimEnd('\')
    $known = @(
        $env:USERPROFILE, $env:PUBLIC, $env:APPDATA, $env:LOCALAPPDATA, $env:ProgramData,
        $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:SystemRoot, $env:OneDrive,
        (Join-Path $env:USERPROFILE 'Documents'), (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Desktop'), (Join-Path $env:USERPROFILE 'Pictures'),
        (Join-Path $env:USERPROFILE 'Music'), (Join-Path $env:USERPROFILE 'Videos')
    ) | Where-Object { $_ }
    foreach ($folder in $known) {
        if ($normalized -eq $folder.TrimEnd('\')) { return $true }
    }
    return $false
}

# ── קיצורי דרך ──────────────────────────────────────────────────────────────
# נבדק היעד עצמו ולא שם הקובץ: תוסף רשאי ליצור קיצור בשם כלשהו
# (PluginShortcutService), וקיצור של תוכנה אחרת עלול לשאת "otzaria" בשמו.
function Get-OtzShortcutFindings {
    $roots = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu'),
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:PUBLIC 'Desktop'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    if (-not $roots) { return }
    $shell = New-Object -ComObject WScript.Shell

    foreach ($root in $roots) {
        Get-ChildItem -LiteralPath $root -Filter *.lnk -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $lnk = $_
            $target = ''
            $arguments = ''
            try {
                $sc = $shell.CreateShortcut($lnk.FullName)
                $target = [string]$sc.TargetPath
                $arguments = [string]$sc.Arguments
            } catch { }

            # קיצור ליעד שכבר נמחק: אין EXE לבדוק, ולכן נדרש שם קובץ מדויק
            # של תיקיית התקנה — לא התאמת substring.
            $targetGone = $target -and -not (Test-OtzPathSafe $target)
            $staleOtzaria = $targetGone -and ((Split-Path -Leaf $target) -eq 'otzaria.exe')

            $isOtzaria = (Test-OtzOwnedExecutable $target) -or ($arguments -match 'otzaria://') -or $staleOtzaria
            if (-not $isOtzaria) { return }

            $path = $lnk.FullName
            New-OtzFinding -Id 'scan.shortcuts' -Group 'app' -Kind 'Shortcut' -Target $path `
                -SizeBytes $lnk.Length -Note $target -Remove { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }.GetNewClosure()
        }
    }
}

# ── רכיבי PATH ──────────────────────────────────────────────────────────────
# המתקין מוסיף את תיקיית ההתקנה ל-PATH (Check: ShouldAddToUserPath/System).
# חובה לכתוב חזרה REG_EXPAND_SZ בלי להרחיב, אחרת %SystemRoot% נצרב כטקסט.
function Test-OtzPathEntryOwned {
    param([string]$Entry)
    $value = $Entry.Trim().TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }
    if (Test-OtzInstallDirectory $value) { return $true }
    # רכיב יתום שנשאר אחרי הסרה — מזוהה רק בשם תיקייה מדויק, לא ב-substring.
    if (Test-OtzPathSafe $value) { return $false }
    return ((Split-Path -Leaf $value) -in @('Otzaria', 'אוצריא'))
}

function Get-OtzPathFindings {
    $specs = @(
        @{ Hive = 'User';    Sub = 'Environment'; Scope = 'User' },
        @{ Hive = 'Machine'; Sub = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'; Scope = 'Machine' }
    )

    foreach ($spec in $specs) {
        $base = if ($spec.Hive -eq 'User') { [Microsoft.Win32.RegistryHive]::CurrentUser } else { [Microsoft.Win32.RegistryHive]::LocalMachine }
        $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey($base, [Microsoft.Win32.RegistryView]::Default)
        try {
            $key = $root.OpenSubKey($spec.Sub, $false)
            if (-not $key) { continue }
            $raw = $key.GetValue('Path', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $kind = $key.GetValueKind('Path')
            $key.Close()
        } catch { continue } finally { $root.Close() }

        if (-not $raw) { continue }
        $parts = ([string]$raw) -split ';'
        $hits = $parts | Where-Object { Test-OtzPathEntryOwned $_ }
        if (-not $hits) { continue }

        $subKeyPath = $spec.Sub
        $hiveName = $spec.Hive
        $valueKind = $kind
        $kept = ($parts | Where-Object { -not (Test-OtzPathEntryOwned $_) }) -join ';'

        New-OtzFinding -Id 'scan.path' -Group 'app' -Kind 'RegValue' `
            -Target "$($spec.Hive) PATH: $($hits -join ' | ')" -Note $spec.Scope -Remove {
            $b = if ($hiveName -eq 'User') { [Microsoft.Win32.RegistryHive]::CurrentUser } else { [Microsoft.Win32.RegistryHive]::LocalMachine }
            $r = [Microsoft.Win32.RegistryKey]::OpenBaseKey($b, [Microsoft.Win32.RegistryView]::Default)
            try {
                $k = $r.OpenSubKey($subKeyPath, $true)
                $k.SetValue('Path', $kept, $valueKind)
                $k.Close()
            } finally { $r.Close() }
        }.GetNewClosure()
    }
}

# ── כללי חומת אש ────────────────────────────────────────────────────────────
# רק לפי נתיב התוכנית שבכלל; שם הכלל אינו קובע.
function Get-OtzFirewallFindings {
    $policy = $null
    try { $policy = New-Object -ComObject HNetCfg.FwPolicy2 } catch { return }
    foreach ($rule in $policy.Rules) {
        $app = ''
        try { $app = [string]$rule.ApplicationName } catch { }
        if (-not (Test-OtzOwnedExecutable $app)) {
            # כלל שנשאר אחרי מחיקת ה-EXE: שם הקובץ המדויק בלבד.
            if (-not ($app -and (Split-Path -Leaf $app) -eq 'otzaria.exe')) { continue }
        }
        $name = [string]$rule.Name
        New-OtzFinding -Id 'scan.firewall' -Group 'traces' -Kind 'FirewallRule' -Target $name -Note $app -Remove {
            $p = New-Object -ComObject HNetCfg.FwPolicy2
            $p.Rules.Remove($name)
        }.GetNewClosure()
    }
}

# ── משימות מתוזמנות ─────────────────────────────────────────────────────────
# רק לפי ה-EXE שהמשימה מריצה; שם המשימה אינו קובע.
function Get-OtzScheduledTaskFindings {
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return }
    Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
        $task = $_
        $executables = @($task.Actions | Where-Object { $_.PSObject.Properties['Execute'] } |
            ForEach-Object { [string]$_.Execute })
        $owned = $executables | Where-Object {
            (Test-OtzOwnedExecutable $_) -or ((Split-Path -Leaf $_) -eq 'otzaria.exe')
        }
        # משימה שמריצה מפעיל כללי (powershell.exe) — הבעלות נקבעת לפי הסקריפט
        # שבארגומנטים, שההורה שלו הוא תיקיית רכיב בשם מדויק.
        if (-not $owned) {
            $arguments = @($task.Actions | Where-Object { $_.PSObject.Properties['Arguments'] } |
                ForEach-Object { [string]$_.Arguments }) -join ' '
            $quoted = [regex]::Matches($arguments, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
            $owned = @($quoted | Where-Object { Test-OtzOwnedComponentPath $_ })
        }
        if (-not $owned) { return }
        $taskName = $task.TaskName
        $taskPath = $task.TaskPath
        New-OtzFinding -Id 'scan.tasks' -Group 'traces' -Kind 'ScheduledTask' -Target "$taskPath$taskName" `
            -Note ($owned -join ' ') -Remove {
            Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction Stop
        }.GetNewClosure()
    }
}

# ── רשימות קפיצה ────────────────────────────────────────────────────────────
# הקובץ מזוהה לפי ה-AppUserModelID המגובב בשמו, ולכן נבדק התוכן: נתיב ה-EXE
# מופיע בו כ-UTF-16LE.
function Get-OtzJumpListFindings {
    $roots = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Recent\AutomaticDestinations'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Recent\CustomDestinations')
    ) | Where-Object { Test-Path -LiteralPath $_ }

    foreach ($root in $roots) {
        Get-ChildItem -LiteralPath $root -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $file = $_
            $isHit = $false
            try {
                $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
                $text = [System.Text.Encoding]::Unicode.GetString($bytes)
                $isHit = ($text -match 'otzaria\.exe' -or $text -match 'Otzaria\.Otzaria')
            } catch { }
            if (-not $isHit) { return }
            $path = $file.FullName
            New-OtzFinding -Id 'trace.jumplists' -Group 'traces' -Kind 'File' -Target $path -SizeBytes $file.Length -Remove {
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            }.GetNewClosure()
        }
    }
}

# ── דוחות שגיאה של Windows ──────────────────────────────────────────────────
function Get-OtzWerFindings {
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportArchive'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportQueue'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue')
    ) | Where-Object { Test-Path -LiteralPath $_ }

    foreach ($root in $roots) {
        Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $dir = $_
            $isHit = $dir.Name -match 'otzaria\.exe'
            if (-not $isHit) {
                # דוחות של תהליכים מערכתיים חסומים בקריאה — מדלגים בשקט.
                $wer = Join-Path $dir.FullName 'Report.wer'
                try {
                    if (Test-Path -LiteralPath $wer -ErrorAction SilentlyContinue) {
                        $isHit = (Select-String -LiteralPath $wer -Pattern 'otzaria\.exe' -Quiet -ErrorAction SilentlyContinue) -eq $true
                    }
                } catch { }
            }
            if (-not $isHit) { return }
            $path = $dir.FullName
            New-OtzFinding -Id 'trace.wer' -Group 'traces' -Kind 'Directory' -Target $path -Remove {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            }.GetNewClosure()
        }
    }
}

# ── התקנות ניידות ───────────────────────────────────────────────────────────
# portable.marker לבדו אינו מספיק — נדרשת תיקיית התקנה מלאה של אוצריא.
function Get-OtzPortableFindings {
    param([int]$Depth = 4)
    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Root -match '^[A-Za-z]:\\$' }

    foreach ($drive in $drives) {
        Get-ChildItem -LiteralPath $drive.Root -Filter 'portable.marker' -Recurse -Depth $Depth -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $dir = $_.Directory
            if (-not (Test-OtzInstallDirectory $dir.FullName)) { return }
            $path = $dir.FullName
            New-OtzFinding -Id 'scan.portable' -Group 'data' -Kind 'Directory' -Target $path `
                -Note 'התקנה ניידת — כולל otzaria_data' -Remove {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            }.GetNewClosure()
        }
    }
}

# ── נתיבים מותאמים מההגדרות ─────────────────────────────────────────────────
# הספרייה, האינדקס, מסדי הנתונים והגיבויים יכולים לשבת בנתיבים נפרדים
# שנשמרו ב-shared_preferences.json; המתקין הרשמי קורא אותו באותה דרך.
function Get-OtzPreferenceValue {
    param([string]$DataRoot, [string]$Key)
    $prefs = Join-Path $DataRoot 'shared_preferences.json'
    if (-not (Test-Path -LiteralPath $prefs)) { return $null }
    try {
        $json = Get-Content -LiteralPath $prefs -Raw -ErrorAction Stop | ConvertFrom-Json
    } catch { return $null }
    foreach ($name in @("flutter.$Key", $Key)) {
        if ($json.PSObject.Properties[$name]) {
            $value = [string]$json.PSObject.Properties[$name].Value
            if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
        }
    }
    return $null
}

function Get-OtzCustomLibraryFindings {
    param([string[]]$DataRoots)

    # תיקיות שאוצריא יוצרת בשורש הספרייה. השורש עצמו לעולם אינו נמחק —
    # ייתכן שהמשתמש בחר תיקייה שיש בה עוד תוכן שלו.
    # 'index' ו-'databases' הם שמות גנריים ולכן נבדקים בנפרד; השאר ייחודיים.
    $ownedNames = @('books', 'library_update_cache', 'pdfium', 'per_book_settings',
                    '.otzaria-books-backup', '.otzaria-index-backup')
    $seen = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)

    function Add-OwnedDirectory {
        param([string]$Candidate, [string]$Source, [string]$Group = 'library')
        if ([string]::IsNullOrWhiteSpace($Candidate)) { return }
        if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) { return }
        $full = [System.IO.Path]::GetFullPath($Candidate)
        if ($full.Length -le 3) { return }
        if (-not $seen.Add($full)) { return }
        $path = $full
        New-OtzFinding -Id 'scan.library' -Group $Group -Kind 'Directory' -Target $path -Note $Source -Remove {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        }.GetNewClosure()
    }

    foreach ($root in $DataRoots) {
        # ── ספרייה ──
        $libPath = $null
        $record = Join-Path $root 'library_path.txt'
        if (Test-Path -LiteralPath $record) {
            try { $libPath = (Get-Content -LiteralPath $record -Raw -ErrorAction Stop).Trim() } catch { }
        }
        if ([string]::IsNullOrWhiteSpace($libPath)) {
            $libPath = Get-OtzPreferenceValue -DataRoot $root -Key 'key-library-path'
        }

        if (-not [string]::IsNullOrWhiteSpace($libPath)) {
            $booksPath = if ((Split-Path -Leaf $libPath) -eq 'books') { $libPath } else { Join-Path $libPath 'books' }
            $libRoot = if ((Split-Path -Leaf $libPath) -eq 'books') { Split-Path -Parent $libPath } else { $libPath }

            # מבחן הבעלות של המתקין הרשמי: בלעדיו לא נוגעים בנתיב מההגדרות.
            if (((Test-OtzBooksFolder $booksPath) -or (Test-OtzBooksFolder $libPath)) -and
                -not (Test-OtzWellKnownUserFolder $libRoot)) {
                foreach ($name in $ownedNames) {
                    Add-OwnedDirectory -Candidate (Join-Path $libRoot $name) -Source "ספרייה מותאמת, לפי $root"
                }
                $siblingIndex = Join-Path $libRoot 'index'
                if (Test-OtzIndexFolder $siblingIndex) {
                    Add-OwnedDirectory -Candidate $siblingIndex -Source "ספרייה מותאמת, לפי $root"
                }
                $siblingDb = Join-Path $libRoot 'databases'
                if (Test-OtzDatabasesFolder $siblingDb) {
                    Add-OwnedDirectory -Candidate $siblingDb -Source "ספרייה מותאמת, לפי $root"
                }
                $siblingDict = Join-Path $libRoot 'dictionaries'
                if (Test-OtzDictionariesFolder $siblingDict) {
                    Add-OwnedDirectory -Candidate $siblingDict -Source "ספרייה מותאמת, לפי $root"
                }
            }
        }

        # ── אינדקס, מסדי נתונים, ספרים אישיים ──
        $indexPath = Get-OtzPreferenceValue -DataRoot $root -Key 'key-index-path'
        if ($indexPath -and (Test-OtzIndexFolder $indexPath)) {
            Add-OwnedDirectory -Candidate $indexPath -Source "אינדקס מותאם, לפי $root"
        }
        $dbPath = Get-OtzPreferenceValue -DataRoot $root -Key 'key-databases-path'
        if ($dbPath -and (Test-OtzDatabasesFolder $dbPath)) {
            Add-OwnedDirectory -Candidate $dbPath -Source "מסדי נתונים מותאמים, לפי $root"
        }

        # ── גיבויים מותאמים — נמחקים קבצים בשמות של אוצריא, לא התיקייה ──
        $backupPath = Get-OtzPreferenceValue -DataRoot $root -Key 'key-backup-path'
        if ($backupPath -and (Test-Path -LiteralPath $backupPath -PathType Container)) {
            foreach ($pattern in @('otzaria_backup_*', 'otzaria_archive.json', 'otzaria_db_backup_*')) {
                Get-ChildItem -LiteralPath $backupPath -Filter $pattern -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    $file = $_
                    $path = $file.FullName
                    New-OtzFinding -Id 'scan.library' -Group 'backups' -Kind 'File' -Target $path `
                        -SizeBytes $file.Length -Note "גיבויים בנתיב מותאם, לפי $root" -Remove {
                        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
                    }.GetNewClosure()
                }
            }
        }
    }
}

# ── פרופילי משתמשים אחרים ───────────────────────────────────────────────────
# בהסרת התקנת מנהל, המשתמש שמריץ אינו בהכרח זה שהתקין — המתקין הרשמי עובר
# על כל הפרופילים, וכך גם כאן. דורש הרשאות מנהל.
function Get-OtzOtherProfileFindings {
    $profilesRoot = Split-Path -Parent $env:USERPROFILE
    if (-not (Test-OtzPathSafe $profilesRoot -Container)) { return }
    $currentProfile = [System.IO.Path]::GetFullPath($env:USERPROFILE)

    # אותם מבחני בעלות של המלאי הקבוע: לפרופיל של משתמש אחר עלולה להיות
    # תיקייה בשם זהה שאינה של אוצריא — ריפו מקור, תיקיית עבודה.
    $relatives = @(
        @{ Path = 'AppData\Roaming\otzaria'; Group = 'data'; Own = 'dataroot' },
        @{ Path = 'AppData\Roaming\אוצריא'; Group = 'data'; Own = 'dataroot' },
        @{ Path = 'AppData\Roaming\אוצריא\אוצריא'; Group = 'data'; Own = 'dataroot' },
        @{ Path = 'AppData\Roaming\Otzaria'; Group = 'data'; Own = 'dataroot' },
        @{ Path = 'AppData\Roaming\Otzaria\otzaria'; Group = 'data'; Own = 'dataroot' },
        @{ Path = 'AppData\Roaming\com.example\otzaria'; Group = 'data'; Own = 'dataroot' },
        @{ Path = 'AppData\Local\otzaria'; Group = 'data'; Own = 'dataroot' },
        @{ Path = 'AppData\Local\אוצריא'; Group = 'data'; Own = 'dataroot' },
        @{ Path = 'Documents\otzaria'; Group = 'data'; Own = 'dataroot' },
        @{ Path = 'AppData\Local\Programs\Otzaria'; Group = 'app'; Own = 'install' },
        @{ Path = 'AppData\Local\Programs\אוצריא'; Group = 'app'; Own = 'install' },
        @{ Path = 'AppData\Local\Otzaria Plugin Store'; Group = 'related'; Own = 'none'; Marker = @('app.exe', 'uninstall.exe') },
        @{ Path = 'AppData\Local\com.otzaria.store'; Group = 'related'; Own = 'none'; Marker = @('EBWebView') },
        @{ Path = 'Documents\אוצריא - גיבויים'; Group = 'backups'; Own = 'none' },
        @{ Path = 'Documents\OtzariaBackups'; Group = 'backups'; Own = 'none' }
    )

    Get-ChildItem -LiteralPath $profilesRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $profileDir = $_
        if ([System.IO.Path]::GetFullPath($profileDir.FullName) -eq $currentProfile) { return }
        if ($profileDir.Name -in @('Public', 'Default', 'Default User', 'All Users')) { return }

        foreach ($entry in $relatives) {
            $candidate = Join-Path $profileDir.FullName $entry.Path
            if (-not (Test-OtzPathSafe $candidate -Container)) { continue }
            $target = [pscustomobject]@{
                Target = $candidate
                Own    = $entry.Own
                Marker = if ($entry.ContainsKey('Marker')) { $entry.Marker } else { $null }
            }
            if (-not (Test-OtzTargetOwnership $target)) { continue }
            $path = $candidate
            New-OtzFinding -Id 'scan.profiles' -Group $entry.Group -Kind 'Directory' -Target $path `
                -Note "פרופיל $($profileDir.Name)" -Remove {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            }.GetNewClosure()
        }
    }
}

# שורשי הנתונים של משתמשים אחרים, כדי שגם ה-library_path.txt וההעדפות שלהם
# ייקראו ולא רק תיקיית השורש תימחק.
function Get-OtzOtherProfileDataRoots {
    $profilesRoot = Split-Path -Parent $env:USERPROFILE
    if (-not (Test-OtzPathSafe $profilesRoot -Container)) { return }
    $currentProfile = [System.IO.Path]::GetFullPath($env:USERPROFILE)

    Get-ChildItem -LiteralPath $profilesRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $profileDir = $_
        if ([System.IO.Path]::GetFullPath($profileDir.FullName) -eq $currentProfile) { return }
        if ($profileDir.Name -in @('Public', 'Default', 'Default User', 'All Users')) { return }
        foreach ($relative in @('AppData\Roaming\otzaria', 'AppData\Roaming\אוצריא',
                                'AppData\Roaming\אוצריא\אוצריא',
                                'AppData\Roaming\Otzaria', 'AppData\Roaming\Otzaria\otzaria',
                                'AppData\Roaming\com.example\otzaria',
                                'AppData\Local\otzaria', 'AppData\Local\אוצריא',
                                'Documents\otzaria')) {
            $candidate = Join-Path $profileDir.FullName $relative
            if (-not (Test-OtzPathSafe $candidate -Container)) { continue }
            if (Test-OtzDataRootMarkers $candidate) { $candidate }
            Get-OtzNestedDataRoots $candidate
        }
    }
}

# ── קבצים של המשתמש — דיווח בלבד ────────────────────────────────────────────
function Get-OtzUserFileFindings {
    $roots = @(
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Documents')
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $patterns = @('*.otzplugin', 'otzaria_backup_*.json', 'otzaria_archive.json', 'otzaria_notes*.json', 'otzaria_books.csv', 'otzaria-*-windows*.exe')
    foreach ($root in $roots) {
        foreach ($pattern in $patterns) {
            Get-ChildItem -LiteralPath $root -Filter $pattern -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $file = $_
                $path = $file.FullName
                New-OtzFinding -Id 'scan.userfiles' -Group 'userfiles' -Kind 'File' -Target $path -SizeBytes $file.Length -Remove {
                    Remove-Item -LiteralPath $path -Force -ErrorAction Stop
                }.GetNewClosure()
            }
        }
    }
}
