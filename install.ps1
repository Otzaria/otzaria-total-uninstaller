<#
.SYNOPSIS
    Bootstrap להרצת מסיר אוצריא טוטאלי ישירות מהאינטרנט.

.DESCRIPTION
    עצמאי לחלוטין (ללא תלות ב-lib) — מיועד להרצה בתבנית:

        irm https://raw.githubusercontent.com/Otzaria/otzaria-total-uninstaller/main/install.ps1 | iex

    מוריד את ה-ZIP של הרילייס האחרון, מחלץ לתיקייה זמנית ומריץ את
    Uninstall-Otzaria.ps1. כל פרמטר מועבר הלאה לסקריפט, למשל:

        iex "& { $(irm https://raw.githubusercontent.com/Otzaria/otzaria-total-uninstaller/main/install.ps1) } -Remove"
#>
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$UninstallerArgs
)

$ErrorActionPreference = 'Stop'
# PS 5.1 ישן עלול לפתוח TLS 1.0 בלבד — GitHub דורש TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072

$repo = 'Otzaria/otzaria-total-uninstaller'
Write-Host "מאתר את הרילייס האחרון של $repo..."
$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing
$asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
if (-not $asset) { throw "לא נמצא קובץ ZIP ברילייס $($release.tag_name)" }

$t = Join-Path $env:TEMP 'otzaria-uninstall'
Remove-Item $t, "$t.zip" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("מוריד את {0} ({1})..." -f $asset.name, $release.tag_name)
Invoke-WebRequest $asset.browser_download_url -OutFile "$t.zip" -UseBasicParsing
Expand-Archive "$t.zip" $t -Force

$ps1 = Get-ChildItem $t -Recurse -Filter 'Uninstall-Otzaria.ps1' | Select-Object -First 1
if (-not $ps1) { throw 'Uninstall-Otzaria.ps1 לא נמצא בחבילה שחולצה' }

# הרצה בתהליך חדש עם Bypass — קובץ שהורד חסום במדיניות ההרצה שברירת המחדל
& powershell -NoProfile -ExecutionPolicy Bypass -File $ps1.FullName @UninstallerArgs
exit $LASTEXITCODE
