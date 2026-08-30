<#
.SYNOPSIS
    סריקות דינמיות — יעדים שאי אפשר לרשום מראש כי שמם או מיקומם משתנים.
.DESCRIPTION
    כל סורק מחזיר "ממצאים": אובייקטים עם תיאור ועם Remove — scriptblock שמבצע
    את ההסרה בפועל. הסורקים לעולם אינם מוחקים בעצמם.
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

function Test-OtzOtzariaPath {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match 'otzaria' -or $Value -match 'אוצריא')
}

# ── קיצורי דרך ──────────────────────────────────────────────────────────────
# נבדק היעד עצמו ולא שם הקובץ: תוסף רשאי ליצור קיצור בשם כלשהו
# (PluginShortcutService), ורק ה-TargetPath מסגיר אותו.
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

            $isOtzaria = (Test-OtzOtzariaPath $target) -or ($arguments -match 'otzaria://') -or (Test-OtzOtzariaPath $lnk.Name)
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
        $hits = $parts | Where-Object { Test-OtzOtzariaPath $_ }
        if (-not $hits) { continue }

        $subKeyPath = $spec.Sub
        $hiveName = $spec.Hive
        $valueKind = $kind
        $kept = ($parts | Where-Object { -not (Test-OtzOtzariaPath $_) }) -join ';'

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
function Get-OtzFirewallFindings {
    $policy = $null
    try { $policy = New-Object -ComObject HNetCfg.FwPolicy2 } catch { return }
    foreach ($rule in $policy.Rules) {
        $app = ''
        try { $app = [string]$rule.ApplicationName } catch { }
        if (-not (Test-OtzOtzariaPath $app) -and -not (Test-OtzOtzariaPath $rule.Name)) { continue }
        $name = [string]$rule.Name
        New-OtzFinding -Id 'scan.firewall' -Group 'traces' -Kind 'FirewallRule' -Target $name -Note $app -Remove {
            $p = New-Object -ComObject HNetCfg.FwPolicy2
            $p.Rules.Remove($name)
        }.GetNewClosure()
    }
}

# ── משימות מתוזמנות ─────────────────────────────────────────────────────────
function Get-OtzScheduledTaskFindings {
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return }
    Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
        $task = $_
        $exePaths = @($task.Actions | Where-Object { $_.PSObject.Properties['Execute'] } |
            ForEach-Object { [string]$_.Execute }) -join ' '
        if (-not (Test-OtzOtzariaPath $exePaths) -and -not (Test-OtzOtzariaPath $task.TaskName)) { return }
        $taskName = $task.TaskName
        $taskPath = $task.TaskPath
        New-OtzFinding -Id 'scan.tasks' -Group 'traces' -Kind 'ScheduledTask' -Target "$taskPath$taskName" -Note $exePaths -Remove {
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
                $isHit = ($text -match 'otzaria' -or $text -match 'אוצריא')
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
            $isHit = Test-OtzOtzariaPath $dir.Name
            if (-not $isHit) {
                $wer = Join-Path $dir.FullName 'Report.wer'
                if (Test-Path -LiteralPath $wer) {
                    try { $isHit = (Select-String -LiteralPath $wer -Pattern 'otzaria' -Quiet -ErrorAction SilentlyContinue) -eq $true } catch { }
                }
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
# מזוהות לפי portable.marker שליד ה-EXE; הנתונים יושבים ב-otzaria_data שלידו.
function Get-OtzPortableFindings {
    param([int]$Depth = 4)
    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Root -match '^[A-Za-z]:\\$' }

    foreach ($drive in $drives) {
        Get-ChildItem -LiteralPath $drive.Root -Filter 'portable.marker' -Recurse -Depth $Depth -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $dir = $_.Directory
            if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'otzaria.exe'))) { return }
            $path = $dir.FullName
            New-OtzFinding -Id 'scan.portable' -Group 'data' -Kind 'Directory' -Target $path `
                -Note 'התקנה ניידת — כולל otzaria_data' -Remove {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            }.GetNewClosure()
        }
    }
}

# ── ספרייה בנתיב מותאם ──────────────────────────────────────────────────────
# הנתיב נרשם ב-library_path.txt שבשורש הנתונים; חובה לקרוא אותו לפני שמוחקים
# את השורש עצמו.
function Get-OtzCustomLibraryFindings {
    param([string[]]$DataRoots)

    $seen = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $DataRoots) {
        $record = Join-Path $root 'library_path.txt'
        if (-not (Test-Path -LiteralPath $record)) { continue }
        $libPath = ''
        try { $libPath = (Get-Content -LiteralPath $record -Raw -ErrorAction Stop).Trim() } catch { continue }
        if ([string]::IsNullOrWhiteSpace($libPath) -or -not (Test-Path -LiteralPath $libPath)) { continue }

        # הנתיב שנרשם הוא תיקיית הספרים; שורש הספרייה הוא ההורה שלה.
        $libRoot = Split-Path -Parent $libPath
        foreach ($candidate in @($libPath, $libRoot)) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            $full = [System.IO.Path]::GetFullPath($candidate)
            # שורש שכבר נמחק כשורש נתונים, או נתיב-על מסוכן (כונן שלם) — מדלגים.
            if ($full.Length -le 3) { continue }
            if ($DataRoots | Where-Object { $_ -and $full.Equals([System.IO.Path]::GetFullPath($_), [StringComparison]::OrdinalIgnoreCase) }) { continue }
            if (-not $seen.Add($full)) { continue }
            $path = $full
            New-OtzFinding -Id 'scan.library' -Group 'library' -Kind 'Directory' -Target $path `
                -Note "נרשם ב-$record" -Remove {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            }.GetNewClosure()
            break
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
