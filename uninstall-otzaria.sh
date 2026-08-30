#!/usr/bin/env bash
# מסיר אוצריא טוטאלי — Linux ו-macOS.
# כברירת מחדל: סריקה ודיווח בלבד. למחיקה בפועל: --remove
set -uo pipefail

REMOVE=0
KEEP_LIBRARY=0
KEEP_BACKUPS=0
KEEP_DATA=0
ASSUME_YES=0

usage() {
    cat <<'USAGE'
שימוש: uninstall-otzaria.sh [אפשרויות]

  --remove         מוחק בפועל (בלעדיו — סריקה ודיווח בלבד)
  --yes            בלי שאלת אישור
  --keep-library   משאיר את הספרייה (הספרים והאינדקס)
  --keep-backups   משאיר את הגיבויים
  --keep-data      משאיר את נתוני המשתמש
  -h, --help       העזרה הזו

מחיקת יעדים מערכתיים (/opt, /usr, /var/lib) דורשת sudo.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --remove) REMOVE=1 ;;
        --yes) ASSUME_YES=1 ;;
        --keep-library) KEEP_LIBRARY=1 ;;
        --keep-backups) KEEP_BACKUPS=1 ;;
        --keep-data) KEEP_DATA=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "אפשרות לא מוכרת: $1" >&2; usage; exit 2 ;;
    esac
    shift
done

OS="$(uname -s)"
TARGETS=()   # "group|path"

add() { TARGETS+=("$1|$2"); }

# ── התקנה ──────────────────────────────────────────────────────────────────
if [ "$OS" = "Darwin" ]; then
    add app "/Applications/Otzaria.app"
    add app "$HOME/Applications/Otzaria.app"
    add data "$HOME/Library/Application Support/otzaria"
    add data "/Library/Application Support/otzaria"
    add data "/Library/Application Support/Otzaria"
    for bundle in com.mendelg.otzaria org.otzaria.otzaria; do
        add app "$HOME/Library/Preferences/$bundle.plist"
        add data "$HOME/Library/Caches/$bundle"
        add data "$HOME/Library/WebKit/$bundle"
        add data "$HOME/Library/HTTPStorages/$bundle"
        add data "$HOME/Library/Saved Application State/$bundle.savedState"
    done
    add backups "$HOME/Documents/אוצריא - גיבויים"
else
    add app "/opt/otzaria"
    add app "/usr/local/otzaria"
    add app "/usr/local/bin/otzaria"
    add app "/usr/bin/otzaria"
    add app "/usr/share/applications/otzaria.desktop"
    add app "$HOME/.local/share/applications/otzaria.desktop"
    add app "$HOME/.local/share/mime/packages/otzaria-plugin.xml"
    add data "$HOME/.local/share/otzaria"
    add data "$HOME/.config/otzaria"
    add data "$HOME/.cache/otzaria"
    add library "/var/lib/otzaria"
    add backups "$HOME/Documents/אוצריא - גיבויים"
    # אייקון ה-MIME של קובצי ‎.otzplugin‎ בכל גודל תמה שהותקן
    while IFS= read -r icon; do
        add app "$icon"
    done < <(find "$HOME/.local/share/icons" -name 'application-x-otzaria-plugin.png' 2>/dev/null)
    # קיצורים שנוצרו על שולחן העבודה (גם ע"י תוספים) — מזוהים לפי היעד
    while IFS= read -r desktop_file; do
        if grep -qiE 'otzaria' "$desktop_file" 2>/dev/null; then
            add app "$desktop_file"
        fi
    done < <(find "$HOME/Desktop" "$HOME/שולחן העבודה" -maxdepth 1 -name '*.desktop' 2>/dev/null)
fi

# ── ספרייה בנתיב מותאם ─────────────────────────────────────────────────────
# נקרא מ-library_path.txt לפני שהשורש נמחק.
for root in "$HOME/.local/share/otzaria" "$HOME/Library/Application Support/otzaria"; do
    record="$root/library_path.txt"
    [ -f "$record" ] || continue
    lib="$(tr -d '\r\n' < "$record")"
    [ -n "$lib" ] && [ -d "$lib" ] || continue
    case "$lib" in "$root"*) continue ;; esac
    add library "$(dirname "$lib")"
done

# ── התקנות ניידות ──────────────────────────────────────────────────────────
while IFS= read -r marker; do
    dir="$(dirname "$marker")"
    [ -x "$dir/otzaria" ] && add data "$dir"
done < <(find "$HOME" -maxdepth 4 -name 'portable.marker' 2>/dev/null)

# ── דיווח ──────────────────────────────────────────────────────────────────
declare -A GROUP_LABEL=(
    [app]="התוכנה עצמה" [data]="נתוני משתמש" [library]="ספרייה ואינדקס" [backups]="גיבויים"
)

skip_group() {
    case "$1" in
        library) [ "$KEEP_LIBRARY" = 1 ] ;;
        backups) [ "$KEEP_BACKUPS" = 1 ] ;;
        data)    [ "$KEEP_DATA" = 1 ] ;;
        *) false ;;
    esac
}

echo
echo "════════════════════════════════════════════"
echo "   מסיר אוצריא טוטאלי ($OS)"
echo "════════════════════════════════════════════"
[ "$REMOVE" = 1 ] && echo "מצב: הסרה בפועל" || echo "מצב: סריקה בלבד (הוסף --remove כדי למחוק)"
echo

FOUND=()
for entry in "${TARGETS[@]}"; do
    group="${entry%%|*}"
    path="${entry#*|}"
    [ -e "$path" ] || continue
    size="$(du -sh "$path" 2>/dev/null | cut -f1)"
    if skip_group "$group"; then
        echo "  [נשמר]  ${GROUP_LABEL[$group]:-$group}: $path (${size:-?})"
    else
        echo "  [למחיקה] ${GROUP_LABEL[$group]:-$group}: $path (${size:-?})"
        FOUND+=("$path")
    fi
done

if [ "${#FOUND[@]}" -eq 0 ]; then
    echo
    echo "אין שאריות של אוצריא."
    exit 0
fi

echo
echo "סה\"כ למחיקה: ${#FOUND[@]} פריטים"

if [ "$REMOVE" != 1 ]; then
    echo "סריקה בלבד — לא נמחק דבר."
    exit 0
fi

if [ "$ASSUME_YES" != 1 ]; then
    printf 'למחוק את כל הפריטים שלמעלה? (כן/לא) '
    read -r answer
    case "$answer" in כן|y|Y|yes) ;; *) echo "בוטל."; exit 0 ;; esac
fi

# ── תהליכים ────────────────────────────────────────────────────────────────
pkill -f '/otzaria$' 2>/dev/null
pkill -x otzaria 2>/dev/null
sleep 1

# ── מחיקה ──────────────────────────────────────────────────────────────────
FAILED=0
for path in "${FOUND[@]}"; do
    if rm -rf "$path" 2>/dev/null; then
        echo "  נמחק: $path"
    elif [ "$(id -u)" != 0 ] && sudo -n true 2>/dev/null && sudo rm -rf "$path" 2>/dev/null; then
        echo "  נמחק (sudo): $path"
    else
        echo "  נכשל: $path" >&2
        FAILED=$((FAILED + 1))
    fi
done

# ── רענון מסדי הנתונים של המערכת ───────────────────────────────────────────
if [ "$OS" = "Darwin" ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -kill -r -domain local -domain system -domain user >/dev/null 2>&1
    defaults delete com.mendelg.otzaria >/dev/null 2>&1
    defaults delete org.otzaria.otzaria >/dev/null 2>&1
else
    command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1
    command -v update-mime-database >/dev/null && update-mime-database "$HOME/.local/share/mime" >/dev/null 2>&1
    command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1
fi

echo
if [ "$FAILED" -gt 0 ]; then
    echo "הסתיים עם $FAILED כשלונות — נסה שוב עם sudo."
    exit 1
fi
echo "הסתיים. אוצריא הוסרה במלואה."
