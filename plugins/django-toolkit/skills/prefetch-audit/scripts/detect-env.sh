#!/usr/bin/env bash
# detect-env.sh — emit Django + API-framework versions for the prefetch-audit skill.
#
# Pure shell. No Python interpreter invoked. Source of truth is whichever lock
# file is found first when walking up from $PWD (max 5 levels). Output is a
# stable structured block consumed by SKILL.md via shell injection.
#
# Output format (always emitted, even when nothing is found):
#   DJANGO=<version|unknown> [(<status>)]
#   FRAMEWORKS_INSTALLED=<name:ver,...>
#   FRAMEWORKS_DETECTED_BUT_NOT_COVERED=<name:ver,...>
#   LOCKFILE=<relative-path|none>

set -u

PACKAGES_COVERED="strawberry-graphql-django djangorestframework django-ninja"
PACKAGES_NOT_COVERED=""

find_lockfile() {
    local dir="$PWD"
    local depth=0
    while [ "$depth" -lt 5 ]; do
        for f in uv.lock poetry.lock Pipfile.lock; do
            if [ -f "$dir/$f" ]; then
                printf '%s\n' "$dir/$f"
                return 0
            fi
        done
        for f in "$dir"/requirements*.txt; do
            if [ -f "$f" ]; then
                printf '%s\n' "$f"
                return 0
            fi
        done
        if [ -f "$dir/pyproject.toml" ]; then
            printf '%s\n' "$dir/pyproject.toml"
            return 0
        fi
        if [ "$dir" = "/" ]; then
            return 1
        fi
        dir="$(dirname "$dir")"
        depth=$((depth + 1))
    done
    return 1
}

# Extract version of $1 from $2 (a lock-file path). Echoes the version or empty.
extract_version() {
    local pkg="$1"
    local file="$2"
    local base
    base="$(basename "$file")"

    case "$base" in
        uv.lock|poetry.lock)
            # TOML [[package]] blocks. Look for the block whose name = "<pkg>"
            # and grab the next "version = " line.
            awk -v pkg="$pkg" '
                /^\[\[package\]\]/ { in_block = 1; name = ""; next }
                in_block && /^name = / {
                    gsub(/"/, "", $3); name = $3
                }
                in_block && /^version = / && name == pkg {
                    gsub(/"/, "", $3); print $3; exit
                }
                # Stay inside the package block when poetry/uv emit sub-tables
                # like [package.dependencies] / [package.source]. Only exit on a
                # top-level header (i.e. neither another [[package]] start nor a
                # nested [package.*] sub-table).
                /^\[/ && !/^\[\[package\]\]/ && !/^\[package\./ { in_block = 0 }
            ' "$file" 2>/dev/null
            ;;
        Pipfile.lock)
            # JSON. The "version" key lives a few lines below "<pkg>":, after
            # "hashes" / "index" / "markers". Scan a 12-line window after the
            # package key and grab the first "==X.Y.Z". Portable (BSD/GNU grep+sed).
            grep -A12 "\"$pkg\":[[:space:]]*{" "$file" 2>/dev/null \
                | grep -m1 -oE '"version":[[:space:]]*"==[^"]+"' \
                | sed -E 's/.*"==([^"]+)".*/\1/'
            ;;
        requirements*.txt)
            # find_lockfile returns the first matching requirements*.txt, but a
            # project can split deps across requirements.txt / requirements-prod.txt
            # / requirements-dev.txt. Try all matches in the same directory.
            local dir
            dir="$(dirname "$file")"
            local r
            for r in "$dir"/requirements*.txt; do
                [ -f "$r" ] || continue
                local hit
                hit="$(grep -iE "^${pkg}==" "$r" 2>/dev/null \
                    | head -n1 \
                    | sed -E "s/^[^=]+==([^[:space:];#]+).*/\1/")"
                if [ -n "$hit" ]; then
                    printf '%s' "$hit"
                    return 0
                fi
            done
            ;;
        pyproject.toml)
            # Declared deps only — may be unpinned (^X.Y, ~=X.Y, etc.). Best-effort.
            # Three styles supported:
            #   1. Poetry/pdm table:           django = "^4.2"
            #   2. PEP 621 multi-line array:     "django >=4.2",
            #   3. PEP 621 single-line array:  dependencies = ["django >=4.2", ...]
            local v=""
            # Style 1: TOML key = "spec" on its own line
            v="$(grep -iE "^[[:space:]]*\"?${pkg}\"?[[:space:]]*=[[:space:]]*\"" "$file" 2>/dev/null \
                | head -n1 \
                | sed -E 's/.*=[[:space:]]*"[~^>=<! ]*([0-9][0-9A-Za-z.+-]*).*/\1/')"
            if [ -z "$v" ] || ! printf '%s' "$v" | grep -qE '^[0-9]'; then
                # Style 2 & 3: any "<pkg> <spec>" anywhere in the file (handles
                # both multi-line and single-line PEP 621 arrays).
                v="$(grep -ioE "\"${pkg}[[:space:]]*[=~^>< !]+[[:space:]]*[0-9][0-9A-Za-z.+-]*" "$file" 2>/dev/null \
                    | head -n1 \
                    | sed -E 's/.*[=~^>< !]+[[:space:]]*([0-9][0-9A-Za-z.+-]*).*/\1/')"
            fi
            if printf '%s' "$v" | grep -qE '^[0-9]'; then
                printf '%s' "$v"
            fi
            ;;
    esac
}

emit_block() {
    local lockfile="$1"
    local rel_lockfile="none"
    if [ -n "$lockfile" ]; then
        rel_lockfile="${lockfile#"$PWD/"}"
    fi

    local django_ver=""
    local django_status=""
    local source_kind="lock"
    if [ -n "$lockfile" ]; then
        django_ver="$(extract_version django "$lockfile")"
        case "$(basename "$lockfile")" in
            pyproject.toml) source_kind="declared" ;;
        esac
    fi
    if [ -z "$django_ver" ]; then
        printf 'DJANGO=unknown\n'
    elif [ "$source_kind" = "declared" ]; then
        # Version came from a pyproject.toml declaration (possibly unpinned like
        # ^4.2 or >=5.0). The actual installed minor/patch may differ — skip the
        # version-range LTS classification to avoid misleading guidance.
        printf 'DJANGO=%s (declared, may be unpinned)\n' "$django_ver"
    else
        case "$django_ver" in
            5.[1-9]*|[6-9].*)   django_status="recent" ;;
            5.0*)               django_status="supported" ;;
            4.2*)               django_status="LTS, supported" ;;
            4.1*|4.0*|3.*|2.*|1.*) django_status="EOL — upgrade strongly recommended" ;;
            *)                  django_status="" ;;
        esac
        if [ -n "$django_status" ]; then
            printf 'DJANGO=%s (%s)\n' "$django_ver" "$django_status"
        else
            printf 'DJANGO=%s\n' "$django_ver"
        fi
    fi

    local installed=""
    local not_covered=""
    if [ -n "$lockfile" ]; then
        for pkg in $PACKAGES_COVERED; do
            local v
            v="$(extract_version "$pkg" "$lockfile")"
            if [ -n "$v" ]; then
                if [ -z "$installed" ]; then
                    installed="$pkg:$v"
                else
                    installed="$installed,$pkg:$v"
                fi
            fi
        done
        for pkg in $PACKAGES_NOT_COVERED; do
            local v
            v="$(extract_version "$pkg" "$lockfile")"
            if [ -n "$v" ]; then
                if [ -z "$not_covered" ]; then
                    not_covered="$pkg:$v"
                else
                    not_covered="$not_covered,$pkg:$v"
                fi
            fi
        done
    fi

    printf 'FRAMEWORKS_INSTALLED=%s\n' "$installed"
    printf 'FRAMEWORKS_DETECTED_BUT_NOT_COVERED=%s\n' "$not_covered"
    printf 'LOCKFILE=%s\n' "$rel_lockfile"
}

lockfile="$(find_lockfile || true)"
emit_block "${lockfile:-}"
