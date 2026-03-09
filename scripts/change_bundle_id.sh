#!/bin/bash
#
# change_bundle_id.sh - Replace Bundle ID across the entire Flutter project
#
# Usage:
#   ./scripts/change_bundle_id.sh <old_bundle_id> <new_bundle_id> [--dry-run]
#
# Examples:
#   ./scripts/change_bundle_id.sh im.fluffychat.app com.aotsea.im
#   ./scripts/change_bundle_id.sh com.aotsea.im com.example.myapp --dry-run
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Project root (script is in scripts/ directory)
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Parse arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}Error: Missing arguments${NC}"
    echo ""
    echo "Usage: $0 <old_bundle_id> <new_bundle_id> [--dry-run]"
    echo ""
    echo "Examples:"
    echo "  $0 im.fluffychat.app com.aotsea.im"
    echo "  $0 com.aotsea.im com.example.myapp --dry-run"
    exit 1
fi

OLD_ID="$1"
NEW_ID="$2"
DRY_RUN=false

if [ "${3:-}" = "--dry-run" ]; then
    DRY_RUN=true
fi

# Validate bundle ID format (reverse domain notation)
validate_bundle_id() {
    local id="$1"
    if [[ ! "$id" =~ ^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z0-9]+)+$ ]]; then
        echo -e "${YELLOW}Warning: '$id' may not be a valid bundle identifier format${NC}"
        echo -e "${YELLOW}Expected format: com.example.appname${NC}"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Flutter Bundle ID Changer${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "  Project:  ${BLUE}$PROJECT_ROOT${NC}"
echo -e "  Old ID:   ${RED}$OLD_ID${NC}"
echo -e "  New ID:   ${GREEN}$NEW_ID${NC}"
if $DRY_RUN; then
    echo -e "  Mode:     ${YELLOW}DRY RUN (no changes will be made)${NC}"
fi
echo ""

# Validate
validate_bundle_id "$NEW_ID"

# Escape dots for sed regex
OLD_ID_ESCAPED=$(echo "$OLD_ID" | sed 's/\./\\./g')

# Track changes
CHANGED_FILES=()
TOTAL_REPLACEMENTS=0

# Function to replace in a file
replace_in_file() {
    local file="$1"
    local rel_path="${file#$PROJECT_ROOT/}"

    if [ ! -f "$file" ]; then
        return
    fi

    # Count occurrences
    local count
    count=$(grep -c "$OLD_ID" "$file" 2>/dev/null || true)

    if [ "$count" -gt 0 ]; then
        CHANGED_FILES+=("$rel_path")
        TOTAL_REPLACEMENTS=$((TOTAL_REPLACEMENTS + count))

        echo -e "  ${GREEN}✓${NC} ${rel_path} ${BLUE}(${count} replacements)${NC}"

        if ! $DRY_RUN; then
            # Show what will change
            grep -n "$OLD_ID" "$file" | while IFS= read -r line; do
                local line_num=$(echo "$line" | cut -d: -f1)
                local content=$(echo "$line" | cut -d: -f2-)
                local new_content=$(echo "$content" | sed "s/$OLD_ID_ESCAPED/$NEW_ID/g")
                echo -e "    ${RED}- L${line_num}:${content}${NC}"
                echo -e "    ${GREEN}+ L${line_num}:${new_content}${NC}"
            done

            # Perform replacement
            sed -i '' "s/$OLD_ID_ESCAPED/$NEW_ID/g" "$file"
        else
            # Dry run - just show what would change
            grep -n "$OLD_ID" "$file" | while IFS= read -r line; do
                local line_num=$(echo "$line" | cut -d: -f1)
                local content=$(echo "$line" | cut -d: -f2-)
                local new_content=$(echo "$content" | sed "s/$OLD_ID_ESCAPED/$NEW_ID/g")
                echo -e "    ${RED}- L${line_num}:${content}${NC}"
                echo -e "    ${GREEN}+ L${line_num}:${new_content}${NC}"
            done
        fi
        echo ""
    fi
}

# Function to scan directory for matches
scan_and_replace() {
    local dir="$1"
    local label="$2"

    if [ ! -d "$dir" ]; then
        echo -e "  ${YELLOW}⚠ $label directory not found, skipping${NC}"
        echo ""
        return
    fi

    local found=false
    while IFS= read -r -d '' file; do
        found=true
        replace_in_file "$file"
    done < <(grep -rlZ "$OLD_ID" "$dir" 2>/dev/null || true)

    if ! $found; then
        echo -e "  ${YELLOW}— No matches found in $label${NC}"
        echo ""
    fi
}

# ─── iOS ───────────────────────────────────────────
echo -e "${CYAN}── iOS ──────────────────────────────────${NC}"
scan_and_replace "$PROJECT_ROOT/ios" "iOS"

# ─── macOS ─────────────────────────────────────────
echo -e "${CYAN}── macOS ────────────────────────────────${NC}"
scan_and_replace "$PROJECT_ROOT/macos" "macOS"

# ─── Android ───────────────────────────────────────
echo -e "${CYAN}── Android ──────────────────────────────${NC}"
scan_and_replace "$PROJECT_ROOT/android" "Android"

# ─── Web ───────────────────────────────────────────
echo -e "${CYAN}── Web ──────────────────────────────────${NC}"
scan_and_replace "$PROJECT_ROOT/web" "Web"

# ─── Linux ─────────────────────────────────────────
echo -e "${CYAN}── Linux ────────────────────────────────${NC}"
scan_and_replace "$PROJECT_ROOT/linux" "Linux"

# ─── Dart/lib ──────────────────────────────────────
echo -e "${CYAN}── Dart (lib/) ──────────────────────────${NC}"
scan_and_replace "$PROJECT_ROOT/lib" "Dart"

# ─── Root config files ─────────────────────────────
echo -e "${CYAN}── Root Config ──────────────────────────${NC}"
for config_file in "pubspec.yaml" "pubspec.lock" ".metadata"; do
    replace_in_file "$PROJECT_ROOT/$config_file"
done
# Check if any root files had matches
root_found=false
for config_file in "pubspec.yaml" "pubspec.lock" ".metadata"; do
    if [ -f "$PROJECT_ROOT/$config_file" ] && grep -q "$OLD_ID" "$PROJECT_ROOT/$config_file" 2>/dev/null; then
        root_found=true
    fi
done
if ! $root_found && [ ${#CHANGED_FILES[@]} -eq 0 ] || \
   ([ ${#CHANGED_FILES[@]} -gt 0 ] && ! printf '%s\n' "${CHANGED_FILES[@]}" | grep -qE "^(pubspec|\.metadata)"); then
    echo -e "  ${YELLOW}— No matches found in root configs${NC}"
fi
echo ""

# ─── Summary ───────────────────────────────────────
echo -e "${CYAN}========================================${NC}"
if $DRY_RUN; then
    echo -e "${YELLOW}DRY RUN COMPLETE${NC}"
    echo ""
    echo -e "  Would modify: ${BLUE}${#CHANGED_FILES[@]}${NC} files"
    echo -e "  Would replace: ${BLUE}${TOTAL_REPLACEMENTS}${NC} occurrences"
    echo ""
    echo -e "  Run without ${YELLOW}--dry-run${NC} to apply changes."
else
    echo -e "${GREEN}BUNDLE ID UPDATED SUCCESSFULLY${NC}"
    echo ""
    echo -e "  Modified: ${BLUE}${#CHANGED_FILES[@]}${NC} files"
    echo -e "  Replaced: ${BLUE}${TOTAL_REPLACEMENTS}${NC} occurrences"
    echo -e "  ${RED}$OLD_ID${NC} → ${GREEN}$NEW_ID${NC}"
fi
echo -e "${CYAN}========================================${NC}"

# Verification
if ! $DRY_RUN; then
    echo ""
    remaining=$(grep -r "$OLD_ID" "$PROJECT_ROOT" \
        --include="*.pbxproj" \
        --include="*.plist" \
        --include="*.entitlements" \
        --include="*.yaml" \
        --include="*.xml" \
        --include="*.gradle" \
        --include="*.json" \
        --include="*.dart" \
        --include="*.html" \
        --include="*.cmake" \
        --include="Appfile" \
        2>/dev/null | wc -l | tr -d ' ')

    if [ "$remaining" -eq 0 ]; then
        echo -e "  ${GREEN}✓ Verification passed: No remaining references to old Bundle ID${NC}"
    else
        echo -e "  ${RED}⚠ Warning: $remaining remaining references found:${NC}"
        grep -rn "$OLD_ID" "$PROJECT_ROOT" \
            --include="*.pbxproj" \
            --include="*.plist" \
            --include="*.entitlements" \
            --include="*.yaml" \
            --include="*.xml" \
            --include="*.gradle" \
            --include="*.json" \
            --include="*.dart" \
            --include="*.html" \
            --include="*.cmake" \
            --include="Appfile" \
            2>/dev/null | while IFS= read -r line; do
            echo -e "    ${RED}$line${NC}"
        done
    fi
fi
