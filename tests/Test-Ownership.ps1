<#
.SYNOPSIS
    בדיקות בטיחות למבחני הבעלות — הליבה שמונעת מחיקה של תיקיות שאינן של אוצריא.
.DESCRIPTION
    כל בדיקה בונה מבנה תיקיות זמני ומוודאת שהמבחן מכריע נכון. אין כאן מחיקה
    של דבר מחוץ לתיקייה הזמנית.

    הרצה:  powershell -ExecutionPolicy Bypass -File .\tests\Test-Ownership.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'lib\OtzariaScanners.ps1')

$script:Failures = 0
$script:Total = 0

function Assert-Otz {
    param([string]$Name, [bool]$Actual, [bool]$Expected)
    $script:Total++
    if ($Actual -eq $Expected) {
        Write-Host "  [עבר]  $Name" -ForegroundColor DarkGray
    } else {
        Write-Host "  [נכשל] $Name — צפוי $Expected, התקבל $Actual" -ForegroundColor Red
        $script:Failures++
    }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) "otz-tests-$PID"
New-Item -ItemType Directory -Path $root -Force | Out-Null

function New-Fixture {
    param([string]$Name, [string[]]$Files = @(), [string[]]$Directories = @())
    $dir = Join-Path $root $Name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($file in $Files) {
        $full = Join-Path $dir $file
        New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
        Set-Content -LiteralPath $full -Value 'x' -Encoding ASCII
    }
    foreach ($sub in $Directories) {
        New-Item -ItemType Directory -Path (Join-Path $dir $sub) -Force | Out-Null
    }
    return $dir
}

try {
    Write-Host ''
    Write-Host 'מבחני בעלות — תיקיית התקנה' -ForegroundColor White

    $install = New-Fixture 'Otzaria-install' -Files @('otzaria.exe') -Directories @('data\flutter_assets')
    Assert-Otz 'התקנה מלאה מזוהה' (Test-OtzInstallDirectory $install) $true
    Assert-Otz 'התקנה מלאה עוברת בעלות' (Test-OtzInstallOwnership $install) $true

    $leftover = New-Fixture 'Otzaria-leftover' -Files @('system_install.marker')
    Assert-Otz 'שארית עם system_install.marker עוברת' (Test-OtzInstallOwnership $leftover) $true

    # ריפו קוד המקור: Windows אינו מבחין ברישיות, ולכן C:\Otzaria שבמלאי
    # מצביע גם על C:\otzaria. חייב להיפסל.
    $repo = New-Fixture 'Otzaria-sourcerepo' -Files @('pubspec.yaml', 'README.md') -Directories @('lib', 'installer', 'windows')
    Assert-Otz 'ריפו קוד המקור נפסל' (Test-OtzInstallOwnership $repo) $false

    # unins000.exe הוא של Inno Setup, לא של אוצריא — כל תוכנה שנארזה בו מכילה
    # אותו. אם הוא יתקבל כסימן, המסיר יריץ את מסיר ההתקנה של Git או VS Code.
    $innoApp = New-Fixture 'SomeInnoApp' -Files @('unins000.exe', 'app.exe')
    Assert-Otz 'תוכנת Inno אחרת נפסלת' (Test-OtzInstallOwnership $innoApp) $false

    $empty = New-Fixture 'Otzaria-empty'
    Assert-Otz 'תיקייה ריקה נפסלת' (Test-OtzInstallOwnership $empty) $false

    Write-Host ''
    Write-Host 'מבחני בעלות — שורש נתונים' -ForegroundColor White

    $dataHive = New-Fixture 'otzaria-data' -Files @('bookmarks.hive')
    Assert-Otz 'שורש נתונים עם hive' (Test-OtzDataRootOwnership $dataHive) $true

    $dataMarker = New-Fixture 'otzaria-data2' -Files @('library_loaded.marker')
    Assert-Otz 'שורש נתונים עם marker' (Test-OtzDataRootOwnership $dataMarker) $true

    $notData = New-Fixture 'otzaria-notdata' -Files @('notes.txt') -Directories @('src')
    Assert-Otz 'תיקיית עבודה של המשתמש נפסלת' (Test-OtzDataRootOwnership $notData) $false

    Write-Host ''
    Write-Host 'מבחני בעלות — ספרייה, אינדקס ומסדי נתונים' -ForegroundColor White

    $books = New-Fixture 'books-real' -Files @('seforim.db')
    Assert-Otz 'תיקיית ספרים עם seforim.db' (Test-OtzBooksFolder $books) $true

    $booksTalmud = New-Fixture 'books-talmud' -Directories @('תלמוד בבלי')
    Assert-Otz 'תיקיית ספרים עם תלמוד בבלי' (Test-OtzBooksFolder $booksTalmud) $true

    $booksFake = New-Fixture 'books-fake' -Files @('my-notes.docx')
    Assert-Otz 'תיקיית books של המשתמש נפסלת' (Test-OtzBooksFolder $booksFake) $false

    $index = New-Fixture 'index-real' -Files @('tantivy.lock')
    Assert-Otz 'תיקיית אינדקס' (Test-OtzIndexFolder $index) $true
    Assert-Otz 'תיקיית index גנרית נפסלת' (Test-OtzIndexFolder $booksFake) $false

    $db = New-Fixture 'db-real' -Files @('user_books.db')
    Assert-Otz 'מסדי נתונים לפי user_books.db' (Test-OtzDatabasesFolder $db) $true
    Assert-Otz 'תיקיית databases גנרית נפסלת' (Test-OtzDatabasesFolder $booksFake) $false

    Write-Host ''
    Write-Host 'מבחני בעלות — קובצי הרצה ותיקיות מוכרות' -ForegroundColor White

    $exe = Join-Path $install 'otzaria.exe'
    Assert-Otz 'EXE בתוך תיקיית התקנה' (Test-OtzOwnedExecutable $exe) $true

    $strayExe = Join-Path (New-Fixture 'stray' -Files @('otzaria.exe')) 'otzaria.exe'
    Assert-Otz 'קובץ otzaria.exe בלי תיקיית התקנה ובלי פרטי גרסה נפסל' (Test-OtzOwnedExecutable $strayExe) $false

    $goneExe = Join-Path $root 'nonexistent\otzaria.exe'
    Assert-Otz 'שארית של EXE שנמחק מתקבלת' (Test-OtzOwnedExecutable $goneExe) $true

    Assert-Otz 'Documents אינו שורש ספרייה חוקי' (Test-OtzWellKnownUserFolder (Join-Path $env:USERPROFILE 'Documents')) $true
    Assert-Otz 'פרופיל המשתמש אינו שורש ספרייה חוקי' (Test-OtzWellKnownUserFolder $env:USERPROFILE) $true
    Assert-Otz 'תיקייה רגילה כן יכולה להיות שורש ספרייה' (Test-OtzWellKnownUserFolder $root) $false

    Write-Host ''
    Write-Host 'מבחני בעלות — מלאי היעדים' -ForegroundColor White
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'lib\OtzariaInventory.ps1')
    $inventory = @(Get-OtzariaInventory)
    $pathTargets = @($inventory | Where-Object { $_.Kind -eq 'Path' })
    $unguarded = @($pathTargets | Where-Object {
        $_.Own -eq 'none' -and -not $_.Marker -and $_.Group -notin @('backups')
    })
    Assert-Otz 'לכל מטרת Path יש מבחן בעלות (למעט גיבויים בשם ייחודי)' ($unguarded.Count -eq 0) $true
    if ($unguarded.Count -gt 0) {
        $unguarded | ForEach-Object { Write-Host "        חסר מבחן: $($_.Id) → $($_.Target)" -ForegroundColor Yellow }
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Failures -gt 0) {
    Write-Host "נכשלו $($script:Failures) מתוך $($script:Total) בדיקות" -ForegroundColor Red
    exit 1
}
Write-Host "כל $($script:Total) הבדיקות עברו" -ForegroundColor Green
exit 0
