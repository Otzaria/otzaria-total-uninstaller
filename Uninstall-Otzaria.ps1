<#
.SYNOPSIS
    מסיר אוצריא טוטאלי — מאתר ומסיר כל שארית של אוצריא מהמחשב.

.DESCRIPTION
    כברירת מחדל הסקריפט רק סורק ומדווח (אינו מוחק דבר). כדי למחוק בפועל
    יש להריץ עם ‎-Remove‎.

    הסרה מלאה כוללת: תיקיות התקנה מכל הדורות, שורשי נתונים (כולל השמות
    ההיסטוריים), הספרייה והאינדקס, גיבויים, רכיבים נלווים, רישומי Windows,
    קיצורים, רכיבי PATH, כללי חומת אש, משימות מתוזמנות ועקבות מערכת.

.PARAMETER Remove
    מבצע את המחיקה בפועל. בלעדיו — סריקה ודיווח בלבד.

.PARAMETER Yes
    מדלג על שאלת האישור לפני המחיקה.

.PARAMETER KeepLibrary
    משאיר את הספרייה (הספרים והאינדקס) במקומה.

.PARAMETER KeepBackups
    משאיר את תיקיות הגיבוי.

.PARAMETER KeepData
    משאיר את נתוני המשתמש (הגדרות, סימניות, הערות, תוספים).

.PARAMETER IncludeUserFiles
    מוחק גם קבצים שהמשתמש שמר בעצמו (‎.otzplugin‎, גיבויי JSON, מתקינים
    שהורדו). בלעדיו הם מדווחים ולא נמחקים.

.PARAMETER Deep
    מפעיל סריקות איטיות: התקנות ניידות בכל הכוננים, רשימות קפיצה ודוחות WER.

.PARAMETER SkipVendorUninstaller
    לא מריץ את מסיר ההתקנה הרשמי של אוצריא לפני המחיקה הידנית.

.PARAMETER NoElevate
    לא מנסה להפעיל מחדש כמנהל גם כשנדרשות הרשאות.

.PARAMETER ReportPath
    נתיב לקובץ דוח JSON. ברירת מחדל: ‎otzaria-uninstall-report.json‎ ליד הסקריפט.

.EXAMPLE
    .\Uninstall-Otzaria.ps1
    סריקה בלבד — מציגה מה יימחק.

.EXAMPLE
    .\Uninstall-Otzaria.ps1 -Remove -Deep
    הסרה מלאה כולל הסריקות האיטיות.

.EXAMPLE
    .\Uninstall-Otzaria.ps1 -Remove -KeepLibrary -KeepBackups
    מסיר את התוכנה ואת נתוניה, ומשאיר את הספרים ואת הגיבויים.
#>
[CmdletBinding()]
param(
    [switch]$Remove,
    [switch]$Yes,
    [switch]$KeepLibrary,
    [switch]$KeepBackups,
    [switch]$KeepData,
    [switch]$IncludeUserFiles,
    [switch]$Deep,
    [switch]$SkipVendorUninstaller,
    [switch]$NoElevate,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot 'lib\OtzariaInventory.ps1')
. (Join-Path $scriptRoot 'lib\OtzariaScanners.ps1')

if (-not $ReportPath) {
    $ReportPath = Join-Path $scriptRoot 'otzaria-uninstall-report.json'
}

# ─────────────────────────── עזרים ───────────────────────────

function Test-OtzAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-OtzSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Get-OtzDirectorySize {
    param([string]$Path)
    $total = 0L
    try {
        Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $total += $_.Length }
    } catch { }
    return $total
}

# מחיקה של קובץ נעול נדחית להפעלה הבאה (MoveFileEx עם DELAY_UNTIL_REBOOT):
# otzaria.exe שנעול ע"י תהליך גוסס לא ישאיר את התיקייה כולה מאחור.
$script:MoveFileExDefined = $false
function Register-OtzDeleteOnReboot {
    param([string]$Path)
    if (-not $script:MoveFileExDefined) {
        Add-Type -Namespace OtzNative -Name Win32 -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);
'@
        $script:MoveFileExDefined = $true
    }
    return [OtzNative.Win32]::MoveFileEx($Path, $null, 0x4)
}

function Get-OtzNormalizedPath {
    param([string]$Path)
    try { return [System.IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return $Path }
}

function Get-OtzRegistryHive {
    param([string]$Prefix)
    switch ($Prefix.ToUpperInvariant()) {
        'HKCU' { return [Microsoft.Win32.RegistryHive]::CurrentUser }
        'HKLM' { return [Microsoft.Win32.RegistryHive]::LocalMachine }
        'HKCR' { return [Microsoft.Win32.RegistryHive]::ClassesRoot }
        default { throw "כוורת רישום לא מוכרת: $Prefix" }
    }
}

function Get-OtzRegistryViews {
    param([string]$View)
    if ($View -eq 'Both') {
        return @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)
    }
    return @([Microsoft.Win32.RegistryView]::Default)
}

function Split-OtzRegistryPath {
    param([string]$Path)
    $parts = $Path -split '\\', 2
    return @{ Hive = Get-OtzRegistryHive $parts[0]; SubKey = $parts[1] }
}

# ─────────────────────── בניית הממצאים ───────────────────────

function Expand-OtzTarget {
    param([Parameter(Mandatory)]$Target, [string[]]$DataRoots)

    switch ($Target.Kind) {

        'Path' {
            if (-not (Test-Path -LiteralPath $Target.Target)) { return }
            $path = $Target.Target
            $size = if (Test-Path -LiteralPath $path -PathType Container) { Get-OtzDirectorySize $path } else { (Get-Item -LiteralPath $path).Length }
            New-OtzFinding -Id $Target.Id -Group $Target.Group -Kind 'Directory' -Target $path -SizeBytes $size -Note $Target.Note -Remove {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            }.GetNewClosure()
        }

        'PathGlob' {
            $parent = Split-Path -Parent $Target.Target
            $leaf = Split-Path -Leaf $Target.Target
            if (-not (Test-Path -LiteralPath $parent)) { return }
            Get-ChildItem -LiteralPath $parent -Filter $leaf -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $item = $_
                $path = $item.FullName
                $size = if ($item.PSIsContainer) { Get-OtzDirectorySize $path } else { $item.Length }
                New-OtzFinding -Id $Target.Id -Group $Target.Group -Kind $(if ($item.PSIsContainer) { 'Directory' } else { 'File' }) `
                    -Target $path -SizeBytes $size -Note $Target.Note -Remove {
                    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
                }.GetNewClosure()
            }
        }

        'RegKey' {
            $parsed = Split-OtzRegistryPath $Target.Target
            foreach ($view in (Get-OtzRegistryViews $Target.View)) {
                $hive = $parsed.Hive
                $sub = $parsed.SubKey
                $currentView = $view
                $exists = $false
                $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $currentView)
                try {
                    $key = $root.OpenSubKey($sub, $false)
                    if ($key) { $exists = $true; $key.Close() }
                } catch { } finally { $root.Close() }
                if (-not $exists) { continue }

                $label = "$($Target.Target)$(if ($Target.View -eq 'Both') { " [$currentView]" })"
                New-OtzFinding -Id $Target.Id -Group $Target.Group -Kind 'RegKey' -Target $label -Note $Target.Note -Remove {
                    $r = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $currentView)
                    try { $r.DeleteSubKeyTree($sub, $false) } finally { $r.Close() }
                }.GetNewClosure()
            }
        }

        'RegValueMatch' {
            $parsed = Split-OtzRegistryPath $Target.Target
            $hive = $parsed.Hive
            $sub = $parsed.SubKey
            $pattern = $Target.Match
            $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Default)
            $names = @()
            try {
                $key = $root.OpenSubKey($sub, $false)
                if ($key) {
                    $names = @($key.GetValueNames() | Where-Object {
                        $_ -match $pattern -or ([string]$key.GetValue($_)) -match $pattern
                    })
                    $key.Close()
                }
            } catch { } finally { $root.Close() }

            foreach ($name in $names) {
                $valueName = $name
                New-OtzFinding -Id $Target.Id -Group $Target.Group -Kind 'RegValue' `
                    -Target "$($Target.Target) :: $valueName" -Note $Target.Note -Remove {
                    $r = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Default)
                    try {
                        $k = $r.OpenSubKey($sub, $true)
                        if ($k) { $k.DeleteValue($valueName, $false); $k.Close() }
                    } finally { $r.Close() }
                }.GetNewClosure()
            }
        }

        'Scan' {
            switch ($Target.Target) {
                'shortcuts' { Get-OtzShortcutFindings }
                'path'      { Get-OtzPathFindings }
                'firewall'  { Get-OtzFirewallFindings }
                'tasks'     { Get-OtzScheduledTaskFindings }
                'library'   { Get-OtzCustomLibraryFindings -DataRoots $DataRoots }
                'userfiles' { Get-OtzUserFileFindings }
                'jumplists' { if ($Deep) { Get-OtzJumpListFindings } }
                'wer'       { if ($Deep) { Get-OtzWerFindings } }
                'portable'  { if ($Deep) { Get-OtzPortableFindings } }
            }
        }
    }
}

# ───────────────────── תהליכים ומסירים רשמיים ─────────────────

function Stop-OtzProcesses {
    param([switch]$WhatIfOnly)

    $names = @('otzaria', 'Otzaria Plugin Store', 'app')
    $running = New-Object System.Collections.Generic.List[object]

    foreach ($name in $names) {
        foreach ($proc in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            $path = ''
            try { $path = $proc.Path } catch { }
            if ($name -ne 'otzaria' -and -not (Test-OtzOtzariaPath $path)) { continue }
            $running.Add($proc)
        }
    }

    # תהליכי WebView2 של אוצריא מזוהים לפי תיקיית פרופיל המשתמש שבשורת הפקודה.
    try {
        foreach ($wp in @(Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" -ErrorAction SilentlyContinue)) {
            if (Test-OtzOtzariaPath $wp.CommandLine) {
                $p = Get-Process -Id $wp.ProcessId -ErrorAction SilentlyContinue
                if ($p) { $running.Add($p) }
            }
        }
    } catch { }

    foreach ($proc in $running) {
        if ($WhatIfOnly) {
            Write-Host ("  [תהליך רץ] {0} (PID {1})" -f $proc.ProcessName, $proc.Id) -ForegroundColor Yellow
            continue
        }
        try {
            $proc | Stop-Process -Force -ErrorAction Stop
            Write-Host ("  נסגר: {0} (PID {1})" -f $proc.ProcessName, $proc.Id) -ForegroundColor DarkGray
        } catch {
            Write-Warning ("סגירת {0} נכשלה: {1}" -f $proc.ProcessName, $_.Exception.Message)
        }
    }
    if ($running.Count -gt 0 -and -not $WhatIfOnly) { Start-Sleep -Seconds 2 }
    return $running.Count
}

function Get-OtzVendorUninstallers {
    $results = @()
    $roots = @(
        @{ Hive = [Microsoft.Win32.RegistryHive]::LocalMachine; Sub = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' },
        @{ Hive = [Microsoft.Win32.RegistryHive]::CurrentUser;  Sub = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' }
    )
    $views = @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)

    foreach ($spec in $roots) {
        foreach ($view in $views) {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($spec.Hive, $view)
            try {
                $key = $base.OpenSubKey($spec.Sub, $false)
                if (-not $key) { continue }
                foreach ($name in $key.GetSubKeyNames()) {
                    $sub = $key.OpenSubKey($name, $false)
                    if (-not $sub) { continue }
                    try {
                        $display = [string]$sub.GetValue('DisplayName')
                        $uninstall = [string]$sub.GetValue('UninstallString')
                        $location = [string]$sub.GetValue('InstallLocation')
                        $isOtzaria = (Test-OtzOtzariaPath $name) -or (Test-OtzOtzariaPath $display) -or
                                     (Test-OtzOtzariaPath $uninstall) -or ($name -like '*EEC4F712*')
                        if ($isOtzaria -and $uninstall) {
                            $results += [pscustomobject]@{
                                Name = if ($display) { $display } else { $name }
                                UninstallString = $uninstall
                                InstallLocation = $location
                            }
                        }
                    } finally { $sub.Close() }
                }
                $key.Close()
            } catch { } finally { $base.Close() }
        }
    }
    # אותה רשומה מופיעה בשני מבטי הרישום — מדווחים ומריצים אותה פעם אחת.
    return @($results | Sort-Object UninstallString -Unique)
}

function Invoke-OtzVendorUninstaller {
    param([Parameter(Mandatory)]$Entry)

    $command = $Entry.UninstallString.Trim()
    $exe = $command
    $argText = ''
    if ($command.StartsWith('"')) {
        $end = $command.IndexOf('"', 1)
        $exe = $command.Substring(1, $end - 1)
        $argText = $command.Substring($end + 1).Trim()
    } elseif ($command -match '^(?<exe>\S+\.exe)\s*(?<rest>.*)$') {
        $exe = $Matches['exe']
        $argText = $Matches['rest']
    }

    if (-not (Test-Path -LiteralPath $exe)) {
        Write-Warning "מסיר ההתקנה לא נמצא: $exe"
        return $false
    }

    # Inno Setup: הסרה שקטה בלי חלונות ובלי אתחול.
    $silent = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
    $allArgs = @()
    if ($argText) { $allArgs += $argText }
    $allArgs += $silent

    Write-Host ("  מריץ את מסיר ההתקנה של {0}..." -f $Entry.Name) -ForegroundColor DarkGray
    try {
        $proc = Start-Process -FilePath $exe -ArgumentList $allArgs -PassThru -Wait -ErrorAction Stop
        # Inno מפעיל מסיר-משנה ויוצא מיד; ממתינים שהתהליך הבן יסתיים.
        Start-Sleep -Seconds 3
        while (Get-Process -Name 'unins*' -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 2 }
        Write-Host ("  הסתיים (קוד {0})" -f $proc.ExitCode) -ForegroundColor DarkGray
        return $true
    } catch {
        Write-Warning ("הרצת מסיר ההתקנה נכשלה: {0}" -f $_.Exception.Message)
        return $false
    }
}

# ─────────────────────────── ראשי ───────────────────────────

$needsAdminLater = $false

if ($Remove -and -not (Test-OtzAdmin) -and -not $NoElevate) {
    Write-Host 'הסרה מלאה דורשת הרשאות מנהל — מפעיל מחדש כמנהל...' -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($MyInvocation.MyCommand.Path)`"")
    foreach ($key in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$key]
        if ($value -is [switch]) {
            if ($value.IsPresent) { $argList += "-$key" }
        } else {
            $argList += @("-$key", "`"$value`"")
        }
    }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -ErrorAction Stop
        return
    } catch {
        Write-Warning 'ההפעלה כמנהל בוטלה — ממשיך בהרשאות הנוכחיות; יעדים מערכתיים יידלגו.'
        $needsAdminLater = $true
    }
}

Write-Host ''
Write-Host '════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '   מסיר אוצריא טוטאלי' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ("מצב: {0}" -f $(if ($Remove) { 'הסרה בפועל' } else { 'סריקה בלבד (הוסף ‎-Remove‎ כדי למחוק)' })) -ForegroundColor Cyan
Write-Host ''

$isAdmin = Test-OtzAdmin
if (-not $isAdmin) {
    Write-Warning 'הסקריפט אינו רץ כמנהל — יעדים מערכתיים (Program Files, ProgramData, HKLM) יידלגו.'
}

# 1. תהליכים
Write-Host '[1/5] תהליכים רצים' -ForegroundColor White
$runningCount = Stop-OtzProcesses -WhatIfOnly:(-not $Remove)
if ($runningCount -eq 0) { Write-Host '  אין תהליכים של אוצריא' -ForegroundColor DarkGray }

# 2. מסירי ההתקנה הרשמיים
Write-Host '[2/5] מסירי התקנה רשומים' -ForegroundColor White
$vendors = @(Get-OtzVendorUninstallers)
if ($vendors.Count -eq 0) {
    Write-Host '  לא נמצאה התקנה רשומה' -ForegroundColor DarkGray
} else {
    foreach ($vendor in $vendors) {
        Write-Host ("  {0} — {1}" -f $vendor.Name, $vendor.UninstallString) -ForegroundColor DarkGray
    }
    if ($Remove -and -not $SkipVendorUninstaller) {
        foreach ($vendor in $vendors) { Invoke-OtzVendorUninstaller -Entry $vendor | Out-Null }
    }
}

# 3. איסוף ממצאים
Write-Host '[3/5] סריקת שאריות' -ForegroundColor White
$inventory = @(Get-OtzariaInventory)

# שורשי הנתונים נאספים תחילה — מהם נקרא library_path.txt לפני שהם נמחקים.
$dataRoots = @($inventory | Where-Object { $_.Kind -eq 'Path' -and $_.Group -in @('data', 'library') } |
    ForEach-Object { $_.Target } | Where-Object { Test-Path -LiteralPath $_ })

$findings = New-Object System.Collections.Generic.List[object]
foreach ($target in $inventory) {
    if ($target.Scope -eq 'Machine' -and -not $isAdmin) { continue }
    foreach ($finding in @(Expand-OtzTarget -Target $target -DataRoots $dataRoots)) {
        if ($finding) { $findings.Add($finding) }
    }
}

# תיקיות ההתקנה שנרשמו במסירי ההתקנה — מכסות נתיבים מותאמים שאינם במלאי
# הקבוע (למשל C:\אוצריא של גרסה ישנה).
foreach ($vendor in $vendors) {
    $location = $vendor.InstallLocation
    if (-not $location) {
        $exe = $vendor.UninstallString.Trim('"').Split('"')[0]
        if ($exe) { $location = Split-Path -Parent $exe }
    }
    if (-not $location -or -not (Test-Path -LiteralPath $location)) { continue }
    if ($location.Length -le 3) { continue }
    $path = [System.IO.Path]::GetFullPath($location)
    $findings.Add((New-OtzFinding -Id 'vendor.installdir' -Group 'app' -Kind 'Directory' -Target $path `
        -SizeBytes (Get-OtzDirectorySize $path) -Note $vendor.Name -Remove {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
    }.GetNewClosure()))
}

# איחוד כפילויות: נתיבי Windows אינם תלויי רישיות, ו-%APPDATA%\otzaria ו-
# %APPDATA%\Otzaria הם אותה תיקייה. בלי זה הנפח נספר פעמיים.
$pathKinds = @('Directory', 'File', 'Shortcut')
$seenKeys = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
$unique = New-Object System.Collections.Generic.List[object]
foreach ($finding in $findings) {
    $key = if ($finding.Kind -in $pathKinds) {
        Get-OtzNormalizedPath $finding.Target
    } else {
        "$($finding.Kind)|$($finding.Target)"
    }
    if ($seenKeys.Add($key)) { $unique.Add($finding) }
}

# פריט שיושב בתוך תיקייה שכבר נמחקת — מיותר, והמחיקה שלו תיכשל אחריה.
$directories = @($unique | Where-Object { $_.Kind -eq 'Directory' } |
    ForEach-Object { Get-OtzNormalizedPath $_.Target })
$findings = New-Object System.Collections.Generic.List[object]
foreach ($finding in $unique) {
    if ($finding.Kind -in $pathKinds) {
        $full = Get-OtzNormalizedPath $finding.Target
        $parent = $directories | Where-Object {
            $_ -ne $full -and $full.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase)
        }
        if ($parent) { continue }
    }
    $findings.Add($finding)
}

$skipGroups = @()
if ($KeepLibrary) { $skipGroups += 'library' }
if ($KeepBackups) { $skipGroups += 'backups' }
if ($KeepData)    { $skipGroups += 'data' }
if (-not $IncludeUserFiles) { $skipGroups += 'userfiles' }

$toRemove = @($findings | Where-Object { $_.Group -notin $skipGroups })
$skipped  = @($findings | Where-Object { $_.Group -in $skipGroups })

# 4. דיווח
Write-Host '[4/5] ממצאים' -ForegroundColor White
Write-Host ''
$groupLabels = @{
    app = 'התוכנה עצמה'; data = 'נתוני משתמש'; library = 'ספרייה ואינדקס'
    backups = 'גיבויים'; related = 'רכיבים נלווים'; traces = 'עקבות מערכת'
    userfiles = 'קבצים של המשתמש'
}

foreach ($group in @('app', 'data', 'library', 'backups', 'related', 'traces', 'userfiles')) {
    $items = @($findings | Where-Object { $_.Group -eq $group })
    if ($items.Count -eq 0) { continue }
    [long]$size = 0
    $sum = ($items | Measure-Object -Property SizeBytes -Sum).Sum
    if ($sum) { $size = [long]$sum }
    $isSkipped = $group -in $skipGroups
    $suffix = if ($isSkipped) { ' — נשמר' } else { '' }
    $color = if ($isSkipped) { 'DarkGray' } else { 'Yellow' }
    Write-Host ("  {0} ({1} פריטים, {2}){3}" -f $groupLabels[$group], $items.Count, (Format-OtzSize $size), $suffix) -ForegroundColor $color
    foreach ($item in $items) {
        $sizeText = if ($item.SizeBytes -gt 0) { " ({0})" -f (Format-OtzSize $item.SizeBytes) } else { '' }
        Write-Host ("      [{0}] {1}{2}" -f $item.Kind, $item.Target, $sizeText) -ForegroundColor DarkGray
    }
    Write-Host ''
}

[long]$totalSize = 0
$totalSum = ($toRemove | Measure-Object -Property SizeBytes -Sum).Sum
if ($totalSum) { $totalSize = [long]$totalSum }
Write-Host ("סה""כ למחיקה: {0} פריטים, {1}" -f $toRemove.Count, (Format-OtzSize $totalSize)) -ForegroundColor Cyan
if ($skipped.Count -gt 0) {
    Write-Host ("נשמרים לבקשתך: {0} פריטים" -f $skipped.Count) -ForegroundColor DarkGray
}
Write-Host ''

# 5. מחיקה
Write-Host '[5/5] ביצוע' -ForegroundColor White
$results = New-Object System.Collections.Generic.List[object]

if (-not $Remove) {
    Write-Host '  סריקה בלבד — לא נמחק דבר. להסרה בפועל: ‎.\Uninstall-Otzaria.ps1 -Remove‎' -ForegroundColor Green
} elseif ($toRemove.Count -eq 0) {
    Write-Host '  אין מה למחוק — המחשב נקי מאוצריא.' -ForegroundColor Green
} else {
    if (-not $Yes) {
        $answer = Read-Host 'למחוק את כל הפריטים שלמעלה? (כן/לא)'
        if ($answer -notin @('כן', 'y', 'Y', 'yes', 'כ')) {
            Write-Host '  בוטל.' -ForegroundColor Yellow
            return
        }
    }

    $deferred = 0
    foreach ($item in $toRemove) {
        $status = 'removed'
        $errMessage = ''
        try {
            & $item.Remove
        } catch {
            $errMessage = $_.Exception.Message
            $status = 'failed'
            # קובץ נעול — נדחה להפעלה הבאה במקום להשאיר שארית.
            if ($item.Kind -in @('File', 'Directory', 'Shortcut') -and (Test-Path -LiteralPath $item.Target)) {
                if (Register-OtzDeleteOnReboot -Path $item.Target) {
                    $status = 'deferred'
                    $deferred++
                }
            }
        }
        $results.Add([pscustomobject]@{ Id = $item.Id; Kind = $item.Kind; Target = $item.Target; Status = $status; Error = $errMessage })
        $color = switch ($status) { 'removed' { 'DarkGray' } 'deferred' { 'Yellow' } default { 'Red' } }
        Write-Host ("  [{0}] {1}" -f $status, $item.Target) -ForegroundColor $color
    }

    $failed = @($results | Where-Object { $_.Status -eq 'failed' })
    Write-Host ''
    Write-Host ("נמחקו: {0} | נדחו לאתחול: {1} | נכשלו: {2}" -f
        (@($results | Where-Object { $_.Status -eq 'removed' })).Count, $deferred, $failed.Count) -ForegroundColor Cyan
    if ($deferred -gt 0) {
        Write-Host 'פריטים שהיו נעולים יימחקו בהפעלה הבאה של המחשב.' -ForegroundColor Yellow
    }
    if ($failed.Count -gt 0) {
        Write-Host 'פריטים שנכשלו מפורטים בדוח.' -ForegroundColor Red
    }
}

# דוח
$report = [pscustomobject]@{
    Timestamp = (Get-Date).ToString('o')
    Mode      = if ($Remove) { 'remove' } else { 'scan' }
    IsAdmin   = $isAdmin
    Deep      = [bool]$Deep
    KeptGroups = $skipGroups
    Vendors   = $vendors
    Findings  = @($findings | Select-Object Id, Group, Kind, Target, SizeBytes, Note)
    Results   = $results
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host ''
Write-Host ("דוח מלא נשמר ב: {0}" -f $ReportPath) -ForegroundColor Cyan
