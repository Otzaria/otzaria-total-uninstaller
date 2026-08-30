#!/usr/bin/env bash
# מסיר אוצריא טוטאלי — Linux ו-macOS.
# כברירת מחדל: סריקה ודיווח בלבד. למחיקה בפועל: --remove
#
# כלל ברזל: שם שמכיל "otzaria" אינו הוכחת בעלות. תיקייה שהגיעה מהגדרות
# המשתמש נמחקת רק אחרי מבחן בעלות — קובץ שרק אוצריא יוצרת.
#
# תואם Bash 3.2 (ברירת המחדל ב-macOS) — בלי מערכים אסוציאטיביים ובלי mapfile.
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

מחיקת יעדים מערכתיים (/opt, /usr, /var/lib, /Applications) דורשת sudo.
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

add() {
    local group="$1" path="$2"
    [ -n "$path" ] || return 0
    [ -e "$path" ] || return 0
    # שמירה מפני נתיב קצר מדי (שורש כונן) או תיקיית הבית עצמה
    [ "${#path}" -ge 6 ] || return 0
    [ "$path" != "$HOME" ] || return 0
    local entry
    for entry in ${TARGETS+"${TARGETS[@]}"}; do
        [ "$entry" = "$group|$path" ] && return 0
    done
    TARGETS+=("$group|$path")
}

group_label() {
    case "$1" in
        app) echo "התוכנה עצמה" ;;
        data) echo "נתוני משתמש" ;;
        library) echo "ספרייה ואינדקס" ;;
        backups) echo "גיבויים" ;;
        *) echo "$1" ;;
    esac
}

# ── מבחני בעלות ────────────────────────────────────────────────────────────

# תיקיית ספרים — אותם סימנים שמסיר ההתקנה הרשמי בודק ב-IsOtzariaBooksFolder.
is_books_folder() {
    local path="${1:-}"
    [ -n "$path" ] && [ -d "$path" ] || return 1
    [ -f "$path/seforim.db" ] || [ -f "$path/otzar-HB_catalog.db" ] || [ -d "$path/תלמוד בבלי" ]
}

is_index_folder() {
    local path="${1:-}"
    [ -n "$path" ] && [ -d "$path" ] || return 1
    [ -f "$path/meta.json" ] || [ -f "$path/tantivy.lock" ] || [ -f "$path/.tantivy-writer.lock" ]
}

is_databases_folder() {
    local path="${1:-}"
    [ -n "$path" ] && [ -d "$path" ] || return 1
    local name
    for name in seforim.db cache.db otzaria_lexical.db lexical.db user_books.db                 plugins_host.db personal_notes.db talmud_synopsis_pooled.db; do
        [ -f "$path/$name" ] && return 0
    done
    return 1
}

# תיקיית התקנה — קובץ ההרצה וחבילת ה-assets של Flutter שלצידו.
is_install_dir() {
    local path="${1:-}"
    [ -n "$path" ] && [ -d "$path" ] || return 1
    [ -f "$path/otzaria" ] && [ -d "$path/data/flutter_assets" ]
}

# שורש נתונים — מבנה העבודה שאוצריא יוצרת. שם התיקייה לבדו אינו מספיק.
is_data_root() {
    local path="${1:-}"
    [ -n "$path" ] && [ -d "$path" ] || return 1
    local marker
    for marker in library_loaded.marker library_path.txt shared_preferences.json per_book_settings webview2; do
        [ -e "$path/$marker" ] && return 0
    done
    ls "$path"/*.hive >/dev/null 2>&1 && return 0
    # שמות גנריים ('books', 'index', 'databases', 'plugins') אינם ראיה בפני
    # עצמם — כל תת-תיקייה חייבת לעבור את מבחן הבעלות שלה.
    is_books_folder "$path/books" && return 0
    is_index_folder "$path/index" && return 0
    is_databases_folder "$path/databases" && return 0
    [ -d "$path/plugins/installed" ]
}

# יעד קבוע שנמחק כתיקייה שלמה חייב להוכיח בעלות — התקנה או שורש נתונים.
add_owned_dir() {
    local group="$1" path="$2"
    is_install_dir "$path" || is_data_root "$path" || return 0
    add "$group" "$path"
}

# נקודת עצירה לבדיקות: טוען את מבחני הבעלות בלבד.
[ "${OTZARIA_UNINSTALLER_LIB_ONLY:-0}" = "1" ] && return 0 2>/dev/null

# קריאת ערך מ-shared_preferences.json בלי jq — אותה גישה של המתקין הרשמי.
pref_value() {
    local root="$1" key="$2" prefs="$1/shared_preferences.json"
    [ -f "$prefs" ] || return 0
    sed -n "s/.*\"\(flutter\.\)\{0,1\}$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\2/p" "$prefs" | head -n 1
}

# ── התקנה ונתונים ──────────────────────────────────────────────────────────
DATA_ROOTS=()

if [ "$OS" = "Darwin" ]; then
    # שם היישום הוא PRODUCT_NAME שב-AppInfo.xcconfig — עברי בגרסאות הנוכחיות.
    for app_name in "אוצריא.app" "Otzaria.app" "otzaria.app"; do
        add app "/Applications/$app_name"
        add app "$HOME/Applications/$app_name"
    done
    DATA_ROOTS+=("$HOME/Library/Application Support/otzaria")
    add_owned_dir data "$HOME/Library/Application Support/otzaria"
    add_owned_dir data "$HOME/Library/Application Support/אוצריא"
    add_owned_dir data "/Library/Application Support/otzaria"
    add_owned_dir data "/Library/Application Support/Otzaria"
    # מזהי החבילה לאורך הדורות
    for bundle in com.example.otzaria com.mendelg.otzaria org.otzaria.otzaria; do
        add app "$HOME/Library/Preferences/$bundle.plist"
        add data "$HOME/Library/Caches/$bundle"
        add data "$HOME/Library/WebKit/$bundle"
        add data "$HOME/Library/HTTPStorages/$bundle"
        add data "$HOME/Library/Saved Application State/$bundle.savedState"
    done
    add backups "$HOME/Documents/אוצריא - גיבויים"
    add backups "$HOME/Documents/OtzariaBackups"
else
    add_owned_dir app "/opt/otzaria"
    add_owned_dir app "/usr/local/otzaria"
    add app "/usr/local/bin/otzaria"
    add app "/usr/bin/otzaria"
    add app "/usr/share/applications/otzaria.desktop"
    add app "$HOME/.local/share/applications/otzaria.desktop"
    add app "$HOME/.local/share/mime/packages/otzaria-plugin.xml"
    DATA_ROOTS+=("$HOME/.local/share/otzaria")
    add_owned_dir data "$HOME/.local/share/otzaria"
    add_owned_dir data "$HOME/.config/otzaria"
    add_owned_dir data "$HOME/.cache/otzaria"
    add_owned_dir library "/var/lib/otzaria"
    add backups "$HOME/Documents/אוצריא - גיבויים"
    add backups "$HOME/Documents/OtzariaBackups"
    # אייקון ה-MIME של קובצי ‎.otzplugin‎ בכל גודל תמה שהותקן
    while IFS= read -r icon; do
        add app "$icon"
    done < <(find "$HOME/.local/share/icons" -name 'application-x-otzaria-plugin.png' 2>/dev/null)
    # קיצורים — לפי ה-Exec שבקובץ, לא לפי שמו
    while IFS= read -r desktop_file; do
        if grep -qE '^Exec=.*(/otzaria|otzaria://)' "$desktop_file" 2>/dev/null; then
            add app "$desktop_file"
        fi
    done < <(find "$HOME/Desktop" -maxdepth 1 -name '*.desktop' 2>/dev/null)
fi

# ── נתיבים מותאמים מההגדרות ────────────────────────────────────────────────
# השורש שהמשתמש בחר לעולם אינו נמחק — רק תיקיות בשמות שאוצריא יוצרת, ורק
# אחרי שהספרייה עברה את מבחן הבעלות.
OWNED_NAMES="books index databases dictionaries library_update_cache pdfium per_book_settings .otzaria-books-backup .otzaria-index-backup"

for root in ${DATA_ROOTS+"${DATA_ROOTS[@]}"}; do
    [ -d "$root" ] || continue

    lib=""
    [ -f "$root/library_path.txt" ] && lib="$(tr -d '\r\n' < "$root/library_path.txt")"
    [ -n "$lib" ] || lib="$(pref_value "$root" 'key-library-path')"

    if [ -n "$lib" ]; then
        if [ "$(basename "$lib")" = "books" ]; then
            books="$lib"; lib_root="$(dirname "$lib")"
        else
            books="$lib/books"; lib_root="$lib"
        fi
        if is_books_folder "$books" || is_books_folder "$lib"; then
            for name in $OWNED_NAMES; do
                add library "$lib_root/$name"
            done
        else
            echo "  [דילוג] נתיב ספרייה מההגדרות שלא עבר מבחן בעלות: $lib" >&2
        fi
    fi

    index_path="$(pref_value "$root" 'key-index-path')"
    is_index_folder "$index_path" && add library "$index_path"

    db_path="$(pref_value "$root" 'key-databases-path')"
    is_databases_folder "$db_path" && add library "$db_path"

    # גיבויים בנתיב מותאם — קבצים בשמות של אוצריא בלבד, לא התיקייה
    backup_path="$(pref_value "$root" 'key-backup-path')"
    if [ -n "$backup_path" ] && [ -d "$backup_path" ]; then
        while IFS= read -r backup_file; do
            add backups "$backup_file"
        done < <(find "$backup_path" -maxdepth 1 -type f \( -name 'otzaria_backup_*' -o -name 'otzaria_archive.json' -o -name 'otzaria_db_backup_*' \) 2>/dev/null)
    fi
done

# ── התקנות ניידות ──────────────────────────────────────────────────────────
while IFS= read -r marker; do
    dir="$(dirname "$marker")"
    is_install_dir "$dir" && add data "$dir"
done < <(find "$HOME" -maxdepth 4 -name 'portable.marker' 2>/dev/null)

# ── דיווח ──────────────────────────────────────────────────────────────────
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
if [ "$REMOVE" = 1 ]; then echo "מצב: הסרה בפועל"; else echo "מצב: סריקה בלבד (הוסף --remove כדי למחוק)"; fi
echo

FOUND=()
for entry in ${TARGETS+"${TARGETS[@]}"}; do
    group="${entry%%|*}"
    path="${entry#*|}"
    size="$(du -sh "$path" 2>/dev/null | cut -f1)"
    if skip_group "$group"; then
        echo "  [נשמר]   $(group_label "$group"): $path (${size:-?})"
    else
        echo "  [למחיקה] $(group_label "$group"): $path (${size:-?})"
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
    for bundle in com.example.otzaria com.mendelg.otzaria org.otzaria.otzaria; do
        defaults delete "$bundle" >/dev/null 2>&1
    done
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
