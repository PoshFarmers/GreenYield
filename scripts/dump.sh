#!/usr/bin/env bash
#
# dump_codebase.sh
#
# Dumps the content of all relevant source code files under:
#   - lib/          (Dart + any other code files)
#   - supabase/     (edge function code only, e.g. .ts/.js/.sql — configs skipped)
#
# Excludes config/build/pubspec files. Output is a single txt file with
# each file's relative path as a header and a clear separator between files.
#
# Usage:
#   ./dump_codebase.sh [output_file]
#
# This script can be run from any working directory.
# It determines the GreenYield project root from its own location.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

OUTPUT_FILE="${1:-"$PROJECT_ROOT/codebase_dump.txt"}"

# Brief project description shown at the top of the dump.
# Edit this to keep it accurate as the project evolves.
PROJECT_DESCRIPTION="GreenYield is a Flutter (Dart) mobile/desktop/web app with a Supabase backend.
It is structured around a farm-to-buyer marketplace, with feature modules for
marketplace listings, orders, delivery, and an in-app wallet (see lib/features/).
Shared app infrastructure (auth, local db, messaging, notifications, Supabase
client, theming, shared widgets) lives in lib/core/. Backend logic that runs on
Supabase (e.g. edge functions) lives in supabase/."

# Extensions considered "code" — adjust as needed.
CODE_EXTENSIONS=(
    "dart"
    "ts" "tsx" "js" "jsx"
    "sql"
    "py"
    "sh"
)

# Directories to scan (relative to project root)
SCAN_DIRS=("lib" "supabase")

# Specific files/dirs to always exclude even if they match an extension above
EXCLUDE_PATTERNS=(
    "*/config.toml"
    "*.g.dart"
    "*.freezed.dart"
    "*.mocks.dart"
)

# Build the `find` name expression for extensions
build_name_expr() {
    local expr=()
    for ext in "${CODE_EXTENSIONS[@]}"; do
        if [ ${#expr[@]} -gt 0 ]; then
            expr+=("-o")
        fi
        expr+=("-iname" "*.${ext}")
    done
    echo "${expr[@]}"
}

# Check scan dirs exist
for d in "${SCAN_DIRS[@]}"; do
    if [ ! -d "$PROJECT_ROOT/$d" ]; then
        echo "Warning: directory '$d' not found — skipping." >&2
    fi
done

: > "$OUTPUT_FILE"

# ---- Header: project description + how-to-read instructions + tree ----
{
    echo "========================================================"
    echo "PROJECT: GreenYield"
    echo "========================================================"
    echo ""
    echo "$PROJECT_DESCRIPTION"
    echo ""
    echo "--------------------------------------------------------"
    echo "HOW TO READ THIS DUMP"
    echo "--------------------------------------------------------"
    echo "1. This file starts with the project directory tree (via 'tree -I build'),"
    echo "   so you can see the overall structure before reading any code."
    echo "2. After the tree, each source file is dumped in full, one after another."
    echo "3. Every file's dump is wrapped like this:"
    echo "     ========================================================"
    echo "     FILE: <path relative to project root>"
    echo "     ========================================================"
    echo "     <full file content>"
    echo "4. Only hand-written code files are included: everything under lib/"
    echo "   (Dart, plus any other code files) and code files under supabase/"
    echo "   (e.g. edge functions). Config files, build output, pubspec files,"
    echo "   and generated Dart files (*.g.dart, *.freezed.dart, *.mocks.dart)"
    echo "   are intentionally excluded — refer to the tree above for those."
    echo "5. To jump to a specific file, search for 'FILE: <path>'."
    echo ""
    echo "--------------------------------------------------------"
    echo "PROJECT TREE (tree -I build)"
    echo "--------------------------------------------------------"
    if command -v tree >/dev/null 2>&1; then
        tree -I build "$PROJECT_ROOT"
    else
        echo "(tree command not found — install it, e.g. 'sudo dnf install tree', to include this section)"
    fi
    echo ""
} >> "$OUTPUT_FILE"

file_count=0

for d in "${SCAN_DIRS[@]}"; do
    [ -d "$PROJECT_ROOT/$d" ] || continue

    # shellcheck disable=SC2046
    while IFS= read -r -d '' file; do
        rel_path="${file#"$PROJECT_ROOT"/}"

        # Apply exclude patterns
        skip=false
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            case "$rel_path" in
                $pattern) skip=true ;;
            esac
        done
        $skip && continue

        {
            echo "========================================================"
            echo "FILE: $rel_path"
            echo "========================================================"
            cat "$file"
            echo ""
            echo ""
        } >> "$OUTPUT_FILE"

        file_count=$((file_count + 1))
    done < <(find "$PROJECT_ROOT/$d" -type f \( $(build_name_expr) \) -print0 | sort -z)
done

echo "Done. Dumped $file_count files into '$OUTPUT_FILE'."