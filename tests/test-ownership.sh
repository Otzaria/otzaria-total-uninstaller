#!/usr/bin/env bash
# בדיקות בטיחות למבחני הבעלות בגרסת Linux/macOS.
# הרצה:  bash tests/test-ownership.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# טעינת מבחני הבעלות בלבד — הסקריפט עוצר בנקודת ה-LIB_ONLY.
OTZARIA_UNINSTALLER_LIB_ONLY=1
export OTZARIA_UNINSTALLER_LIB_ONLY
# shellcheck source=/dev/null
. "$SCRIPT_DIR/uninstall-otzaria.sh"

FAILURES=0
TOTAL=0

assert() {
    local name="$1" actual="$2" expected="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" = "$expected" ]; then
        echo "  [עבר]  $name"
    else
        echo "  [נכשל] $name — צפוי $expected, התקבל $actual"
        FAILURES=$((FAILURES + 1))
    fi
}

check() { if "$@"; then echo 1; else echo 0; fi }

ROOT="$(mktemp -d 2>/dev/null || mktemp -d -t otz)"
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/install/data/flutter_assets" && : > "$ROOT/install/otzaria"
mkdir -p "$ROOT/repo/lib" "$ROOT/repo/installer" && : > "$ROOT/repo/pubspec.yaml"
mkdir -p "$ROOT/data" && : > "$ROOT/data/library_loaded.marker"
mkdir -p "$ROOT/notdata" && : > "$ROOT/notdata/notes.txt"
mkdir -p "$ROOT/books" && : > "$ROOT/books/seforim.db"
mkdir -p "$ROOT/books-fake" && : > "$ROOT/books-fake/my-notes.docx"
mkdir -p "$ROOT/index" && : > "$ROOT/index/tantivy.lock"
mkdir -p "$ROOT/generic/books" "$ROOT/generic/index" "$ROOT/generic/databases" "$ROOT/generic/plugins"
mkdir -p "$ROOT/generic-real/books" && : > "$ROOT/generic-real/books/seforim.db"
mkdir -p "$ROOT/db" && : > "$ROOT/db/user_books.db"
mkdir -p "$ROOT/dict" && : > "$ROOT/dict/dictionary.json"

echo
echo "מבחני בעלות (Bash)"
assert "תיקיית התקנה מזוהה"            "$(check is_install_dir "$ROOT/install")" 1
assert "ריפו קוד המקור נפסל"            "$(check is_install_dir "$ROOT/repo")" 0
assert "שורש נתונים מזוהה"              "$(check is_data_root "$ROOT/data")" 1
assert "תיקיית עבודה של המשתמש נפסלת"   "$(check is_data_root "$ROOT/notdata")" 0
assert "תת-תיקיות גנריות ריקות אינן מספיקות" "$(check is_data_root "$ROOT/generic")" 0
assert "books עם seforim.db הופך לשורש נתונים" "$(check is_data_root "$ROOT/generic-real")" 1
assert "תיקיית ספרים מזוהה"             "$(check is_books_folder "$ROOT/books")" 1
assert "תיקיית books של המשתמש נפסלת"   "$(check is_books_folder "$ROOT/books-fake")" 0
assert "תיקיית אינדקס מזוהה"            "$(check is_index_folder "$ROOT/index")" 1
assert "תיקיית index גנרית נפסלת"       "$(check is_index_folder "$ROOT/books-fake")" 0
assert "מסדי נתונים לפי user_books.db"  "$(check is_databases_folder "$ROOT/db")" 1
assert "תיקיית מילונים לפי dictionary.json"  "$(check is_dictionaries_folder "$ROOT/dict")" 1
assert "תיקיית dictionaries גנרית נפסלת"    "$(check is_dictionaries_folder "$ROOT/books-fake")" 0
assert "Documents אינו שורש ספרייה חוקי"    "$(check is_well_known_folder "$HOME/Documents")" 1
assert "תיקייה רגילה כן יכולה להיות שורש"   "$(check is_well_known_folder "$ROOT/generic")" 0
assert "תיקיית databases גנרית נפסלת"   "$(check is_databases_folder "$ROOT/books-fake")" 0

echo
if [ "$FAILURES" -gt 0 ]; then
    echo "נכשלו $FAILURES מתוך $TOTAL בדיקות"
    exit 1
fi
echo "כל $TOTAL הבדיקות עברו"
