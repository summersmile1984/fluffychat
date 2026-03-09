#!/bin/bash
#
# apply-brand.sh - Apply a brand configuration to the entire Flutter project
#
# Usage:
#   ./scripts/apply-brand.sh <brand_name> [--dry-run]
#
# Examples:
#   ./scripts/apply-brand.sh turning_agent
#   ./scripts/apply-brand.sh another_brand --dry-run
#
# Prerequisites:
#   - jq (brew install jq)
#

set -euo pipefail

# ─── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Project root ─────────────────────────────────────────────────────────────
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ─── Parse arguments ──────────────────────────────────────────────────────────
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: Missing brand name${NC}"
    echo ""
    echo "Usage: $0 <brand_name> [--dry-run]"
    echo ""
    echo "Available brands:"
    for d in "$PROJECT_ROOT"/brands/*/; do
        name=$(basename "$d")
        [ "$name" = "_template" ] && continue
        echo "  - $name"
    done
    exit 1
fi

BRAND_NAME="$1"
DRY_RUN=false
SKIP_REGEN=false

shift
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --skip-regen) SKIP_REGEN=true ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
    esac
    shift
done

BRAND_DIR="$PROJECT_ROOT/brands/$BRAND_NAME"
BRAND_JSON="$BRAND_DIR/brand.json"

if [ ! -f "$BRAND_JSON" ]; then
    echo -e "${RED}Error: Brand '$BRAND_NAME' not found at $BRAND_DIR${NC}"
    exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed.${NC}"
    echo "  Install with: brew install jq"
    exit 1
fi

# ─── Load brand config ────────────────────────────────────────────────────────
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Brand Applicator${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

BRAND_DISPLAY_NAME=$(jq -r '.brand_name' "$BRAND_JSON")
BRAND_DESC=$(jq -r '.brand_description' "$BRAND_JSON")

echo -e "  Brand:       ${GREEN}$BRAND_DISPLAY_NAME${NC}"
echo -e "  Description: ${BLUE}$BRAND_DESC${NC}"
echo -e "  Project:     ${BLUE}$PROJECT_ROOT${NC}"
if $DRY_RUN; then
    echo -e "  Mode:        ${YELLOW}DRY RUN (no changes will be made)${NC}"
fi
echo ""

# ─── Helper: Read JSON field ──────────────────────────────────────────────────
jval() {
    jq -r "$1" "$BRAND_JSON"
}

# ─── Helper: Replace value after @brand: marker ──────────────────────────────
# Usage: replace_brand_marker <file> <marker_name> <new_value_line>
# Finds "// @brand:<marker_name>" and replaces the NEXT line with <new_value_line>
CHANGE_COUNT=0

replace_brand_marker() {
    local file="$1"
    local marker="$2"
    local new_line="$3"
    local rel_path="${file#$PROJECT_ROOT/}"

    if [ ! -f "$file" ]; then
        echo -e "  ${YELLOW}⚠ File not found: $rel_path${NC}"
        return
    fi

    # Find the line number of the marker
    local marker_line
    marker_line=$(grep -n "// @brand:${marker}$" "$file" 2>/dev/null | head -1 | cut -d: -f1)

    if [ -z "$marker_line" ]; then
        echo -e "  ${YELLOW}⚠ Marker @brand:${marker} not found in $rel_path${NC}"
        return
    fi

    local target_line=$((marker_line + 1))
    local old_line
    old_line=$(sed -n "${target_line}p" "$file")

    if [ "$old_line" = "$new_line" ]; then
        echo -e "  ${BLUE}— $rel_path${NC} @brand:${marker} ${BLUE}(unchanged)${NC}"
        return
    fi

    CHANGE_COUNT=$((CHANGE_COUNT + 1))
    echo -e "  ${GREEN}✓ $rel_path${NC} @brand:${marker}"
    echo -e "    ${RED}- ${old_line}${NC}"
    echo -e "    ${GREEN}+ ${new_line}${NC}"

    if ! $DRY_RUN; then
        # Replace line N+1 in place
        sed -i '' "${target_line}s|.*|${new_line}|" "$file"
    fi
}

# ─── Helper: Replace multi-line value after @brand: marker ───────────────────
# Usage: replace_brand_marker_multi <file> <marker_name> <num_lines> <new_lines>
replace_brand_marker_multi() {
    local file="$1"
    local marker="$2"
    local num_lines="$3"  # number of old lines to replace
    shift 3
    local new_lines="$*"
    local rel_path="${file#$PROJECT_ROOT/}"

    if [ ! -f "$file" ]; then
        echo -e "  ${YELLOW}⚠ File not found: $rel_path${NC}"
        return
    fi

    local marker_line
    marker_line=$(grep -n "// @brand:${marker}$" "$file" 2>/dev/null | head -1 | cut -d: -f1)

    if [ -z "$marker_line" ]; then
        echo -e "  ${YELLOW}⚠ Marker @brand:${marker} not found in $rel_path${NC}"
        return
    fi

    local start_line=$((marker_line + 1))
    local end_line=$((marker_line + num_lines))

    CHANGE_COUNT=$((CHANGE_COUNT + 1))
    echo -e "  ${GREEN}✓ $rel_path${NC} @brand:${marker} (multi-line)"

    if ! $DRY_RUN; then
        # Delete old lines and insert new ones
        sed -i '' "${start_line},${end_line}d" "$file"
        # Insert new lines at the position
        local insert_line=$((start_line - 1))
        echo "$new_lines" | while IFS= read -r line; do
            sed -i '' "${insert_line}a\\
${line}" "$file"
            insert_line=$((insert_line + 1))
        done
    fi
}

# ─── Helper: Simple sed replacement ──────────────────────────────────────────
replace_in_file() {
    local file="$1"
    local old_text="$2"
    local new_text="$3"
    local rel_path="${file#$PROJECT_ROOT/}"

    if [ ! -f "$file" ]; then
        echo -e "  ${YELLOW}⚠ File not found: $rel_path${NC}"
        return
    fi

    local count
    count=$(grep -c "$old_text" "$file" 2>/dev/null || true)

    if [ "$count" -eq 0 ]; then
        return
    fi

    if [ "$old_text" = "$new_text" ]; then
        echo -e "  ${BLUE}— $rel_path${NC} ${BLUE}(unchanged, ${count} occurrences)${NC}"
        return
    fi

    CHANGE_COUNT=$((CHANGE_COUNT + count))
    echo -e "  ${GREEN}✓ $rel_path${NC} ${BLUE}(${count} replacements)${NC}"

    if ! $DRY_RUN; then
        # Escape sed special characters
        local old_escaped new_escaped
        old_escaped=$(printf '%s\n' "$old_text" | sed 's/[&/\]/\\&/g')
        new_escaped=$(printf '%s\n' "$new_text" | sed 's/[&/\]/\\&/g')
        sed -i '' "s|${old_escaped}|${new_escaped}|g" "$file"
    fi
}

# ─── Load brand values ────────────────────────────────────────────────────────
B_NAME=$(jval '.brand_name')
B_DESC=$(jval '.brand_description')

# Identifiers
B_ANDROID_APP_ID=$(jval '.identifiers.android_application_id')
B_ANDROID_NS=$(jval '.identifiers.android_namespace')
B_IOS_BUNDLE=$(jval '.identifiers.ios_bundle_id')
B_IOS_SHARE_BUNDLE=$(jval '.identifiers.ios_share_bundle_id')
B_MACOS_BUNDLE=$(jval '.identifiers.macos_bundle_id')
B_LINUX_APP_ID=$(jval '.identifiers.linux_application_id')
B_LINUX_BIN=$(jval '.identifiers.linux_binary_name')
B_WIN_BIN=$(jval '.identifiers.windows_binary_name')
B_SNAP_NAME=$(jval '.identifiers.snap_name')
B_URL_SCHEME=$(jval '.identifiers.url_scheme')
B_DEEP_LINK=$(jval '.identifiers.deep_link_prefix')
B_PUSH_CHANNEL=$(jval '.identifiers.push_channel_id')
B_PUSH_APP_ID=$(jval '.identifiers.push_app_id')
B_APP_ID=$(jval '.identifiers.app_id')
B_APP_URL_SCHEME=$(jval '.identifiers.app_open_url_scheme')
B_CLIENT_NS=$(jval '.identifiers.client_namespace')
B_DBUS=$(jval '.identifiers.dbus_name')

# URLs
B_WEBSITE=$(jval '.urls.website')
B_PRIVACY_SCHEME=$(jval '.urls.privacy_url_scheme')
B_PRIVACY_HOST=$(jval '.urls.privacy_url_host')
B_PRIVACY_PATH=$(jval '.urls.privacy_url_path')
B_SOURCE_URL=$(jval '.urls.source_code_url')
B_SUPPORT_URL=$(jval '.urls.support_url')
B_CHANGELOG_URL=$(jval '.urls.changelog_url')
B_DONATION_URL=$(jval '.urls.donation_url')
B_PUSH_TUTORIAL=$(jval '.urls.push_tutorial_url')
B_ENCRYPT_TUTORIAL=$(jval '.urls.encryption_tutorial_url')
B_CHAT_TUTORIAL=$(jval '.urls.start_chat_tutorial_url')
B_STICKER_TUTORIAL=$(jval '.urls.stickers_tutorial_url')
B_PUSH_GW=$(jval '.urls.push_gateway_url')
B_HS_LIST_URL=$(jval '.urls.homeserver_list_url')
B_ISSUE_HOST=$(jval '.urls.new_issue_url_host')
B_ISSUE_PATH=$(jval '.urls.new_issue_url_path')

# Theme
B_PRIMARY=$(jval '.theme.primary_color')
B_PRIMARY_LIGHT=$(jval '.theme.primary_color_light')
B_SECONDARY=$(jval '.theme.secondary_color')
B_COLOR_SEED=$(jval '.theme.color_scheme_seed')
B_ADAPTIVE_BG=$(jval '.theme.adaptive_icon_background')
B_WEB_THEME=$(jval '.theme.web_theme_color')
B_WEB_BG=$(jval '.theme.web_background_color')

# Defaults
B_DEFAULT_HS=$(jval '.defaults.default_homeserver')

# Legal
B_COPYRIGHT=$(jval '.legal.copyright')
B_COMPANY=$(jval '.legal.company_name')

# iOS Extensions
B_IOS_NOTIF_BUNDLE=$(jval '.identifiers.ios_notification_bundle_id')
B_ASSOCIATED_DOMAIN=$(jval '.identifiers.associated_domain')


# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: Dart Configuration
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── Dart Configuration ───────────────────${NC}"

APP_CONFIG="$PROJECT_ROOT/lib/config/app_config.dart"

replace_brand_marker "$APP_CONFIG" "primary_color" \
    "  static const Color primaryColor = Color(${B_PRIMARY});"

replace_brand_marker "$APP_CONFIG" "primary_color_light" \
    "  static const Color primaryColorLight = Color(${B_PRIMARY_LIGHT});"

replace_brand_marker "$APP_CONFIG" "secondary_color" \
    "  static const Color secondaryColor = Color(${B_SECONDARY});"

replace_brand_marker "$APP_CONFIG" "deep_link_prefix" \
    "  static const String deepLinkPrefix = '${B_DEEP_LINK}';"

replace_brand_marker "$APP_CONFIG" "push_channel_id" \
    "  static const String pushNotificationsChannelId = '${B_PUSH_CHANNEL}';"

replace_brand_marker "$APP_CONFIG" "push_app_id" \
    "  static const String pushNotificationsAppId = '${B_PUSH_APP_ID}';"

replace_brand_marker "$APP_CONFIG" "website" \
    "  static const String website = '${B_WEBSITE}';"

replace_brand_marker "$APP_CONFIG" "push_tutorial_url" \
    "  static const String enablePushTutorial = '${B_PUSH_TUTORIAL}';"

replace_brand_marker "$APP_CONFIG" "app_id" \
    "  static const String appId = '${B_APP_ID}';"

replace_brand_marker "$APP_CONFIG" "app_open_url_scheme" \
    "  static const String appOpenUrlScheme = '${B_APP_URL_SCHEME}';"

replace_brand_marker "$APP_CONFIG" "source_code_url" \
    "  static const String sourceCodeUrl = '${B_SOURCE_URL}';"

replace_brand_marker "$APP_CONFIG" "support_url" \
    "  static const String supportUrl = '${B_SUPPORT_URL}';"

replace_brand_marker "$APP_CONFIG" "changelog_url" \
    "  static const String changelogUrl = '${B_CHANGELOG_URL}';"

replace_brand_marker "$APP_CONFIG" "donation_url" \
    "  static const String donationUrl = '${B_DONATION_URL}';"

echo ""

# setting_keys.dart
SETTING_KEYS="$PROJECT_ROOT/lib/config/setting_keys.dart"

replace_brand_marker "$SETTING_KEYS" "push_gateway_url" \
    "  pushNotificationsGatewayUrl<String>("

replace_brand_marker "$SETTING_KEYS" "application_name" \
    "  applicationName<String>('chat.fluffy.application_name', '${B_NAME}'),"

replace_brand_marker "$SETTING_KEYS" "default_homeserver" \
    "  defaultHomeserver<String>('chat.fluffy.default_homeserver', '${B_DEFAULT_HS}'),"

replace_brand_marker "$SETTING_KEYS" "color_scheme_seed" \
    "  // colorSchemeSeed stored as ARGB int"

echo ""

# client_manager.dart
CLIENT_MGR="$PROJECT_ROOT/lib/utils/client_manager.dart"

replace_brand_marker "$CLIENT_MGR" "client_namespace" \
    "  static const String clientNamespace = '${B_CLIENT_NS}';"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: Android Platform
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── Android ──────────────────────────────${NC}"

ANDROID_MANIFEST="$PROJECT_ROOT/android/app/src/main/AndroidManifest.xml"
ANDROID_GRADLE="$PROJECT_ROOT/android/app/build.gradle.kts"

# AndroidManifest.xml — URL scheme
replace_in_file "$ANDROID_MANIFEST" "android:scheme=\"im.fluffychat\"" "android:scheme=\"${B_URL_SCHEME}\""

# build.gradle.kts — namespace and applicationId
replace_in_file "$ANDROID_GRADLE" 'namespace = "chat.fluffy.fluffychat"' "namespace = \"${B_ANDROID_NS}\""
replace_in_file "$ANDROID_GRADLE" 'applicationId = "chat.fluffy.fluffychat"' "applicationId = \"${B_ANDROID_APP_ID}\""

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: iOS Platform
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── iOS ──────────────────────────────────${NC}"

IOS_INFO="$PROJECT_ROOT/ios/Runner/Info.plist"
IOS_PBXPROJ="$PROJECT_ROOT/ios/Runner.xcodeproj/project.pbxproj"
IOS_ENTITLEMENTS="$PROJECT_ROOT/ios/Runner/Runner.entitlements"

# URL scheme
replace_in_file "$IOS_INFO" "<string>im.fluffychat</string>" "<string>${B_URL_SCHEME}</string>"

# CFBundleName
replace_in_file "$IOS_INFO" "<string>fluffychat</string>" "<string>${B_NAME}</string>"

# Permission descriptions: replace FluffyChat with brand name
replace_in_file "$IOS_INFO" "FluffyChat" "${B_NAME}"
replace_in_file "$IOS_INFO" "Fluffychat" "${B_NAME}"
replace_in_file "$IOS_INFO" "fluffychat.im" "${B_WEBSITE#https://}"

# Share extension
IOS_SHARE_INFO="$PROJECT_ROOT/ios/FluffyChat Share/Info.plist"
replace_in_file "$IOS_SHARE_INFO" "FluffyChat Share" "${B_NAME} Share"

# Share extension bundle ID in pbxproj
replace_in_file "$IOS_PBXPROJ" 'com.aotsea.im.FluffyChat-Share' "${B_IOS_SHARE_BUNDLE}"
# Also handle original FluffyChat share bundle ID pattern
replace_in_file "$IOS_PBXPROJ" 'chat.fluffy.fluffychat.FluffyChat-Share' "${B_IOS_SHARE_BUNDLE}"

# Associated domains in entitlements
replace_in_file "$IOS_ENTITLEMENTS" 'applinks:example.com' "applinks:${B_ASSOCIATED_DOMAIN}"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: macOS Platform
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── macOS ────────────────────────────────${NC}"

MACOS_CONFIG="$PROJECT_ROOT/macos/Runner/Configs/AppInfo.xcconfig"

replace_in_file "$MACOS_CONFIG" "PRODUCT_NAME = FluffyChat" "PRODUCT_NAME = ${B_NAME}"
replace_in_file "$MACOS_CONFIG" "im.fluffychat.fluffychat.testdev" "${B_MACOS_BUNDLE}"
replace_in_file "$MACOS_CONFIG" 'Copyright © 2023 FluffyChat authors. All rights reserved.' "${B_COPYRIGHT}"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: Linux Platform
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── Linux ────────────────────────────────${NC}"

LINUX_CMAKE="$PROJECT_ROOT/linux/CMakeLists.txt"
LINUX_APP="$PROJECT_ROOT/linux/my_application.cc"

replace_in_file "$LINUX_CMAKE" '"chat.fluffy.fluffychat"' "\"${B_LINUX_APP_ID}\""

# Binary name
replace_in_file "$LINUX_CMAKE" 'set(BINARY_NAME "fluffychat")' "set(BINARY_NAME \"${B_LINUX_BIN}\")"

# Window titles
replace_in_file "$LINUX_APP" '"FluffyChat"' "\"${B_NAME}\""

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: Windows Platform
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── Windows ──────────────────────────────${NC}"

WIN_CMAKE="$PROJECT_ROOT/windows/CMakeLists.txt"
WIN_MAIN="$PROJECT_ROOT/windows/runner/main.cpp"
WIN_RC="$PROJECT_ROOT/windows/runner/Runner.rc"

replace_in_file "$WIN_MAIN" 'L"FluffyChat"' "L\"${B_NAME}\""

# Runner.rc - replace display strings but preserve file structure
replace_in_file "$WIN_RC" '"fluffychat"' "\"${B_WIN_BIN}\""

# Runner.rc - company name, copyright, original filename
replace_in_file "$WIN_RC" '"chat.fluffy"' "\"${B_COMPANY}\""
replace_in_file "$WIN_RC" 'Copyright (C) 2022 chat.fluffy. All rights reserved.' "${B_COPYRIGHT}"
replace_in_file "$WIN_RC" '"fluffychat.exe"' "\"${B_WIN_BIN}.exe\""

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7: Web Platform
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── Web ──────────────────────────────────${NC}"

WEB_INDEX="$PROJECT_ROOT/web/index.html"
WEB_MANIFEST="$PROJECT_ROOT/web/manifest.json"

replace_in_file "$WEB_INDEX" 'content="The cutest messenger in the Matrix network"' "content=\"${B_DESC}\""
replace_in_file "$WEB_INDEX" 'content="The cutest messenger in the Matrix network."' "content=\"${B_DESC}\""
replace_in_file "$WEB_INDEX" 'content="FluffyChat"' "content=\"${B_NAME}\""

replace_in_file "$WEB_MANIFEST" '"FluffyChat"' "\"${B_NAME}\""
replace_in_file "$WEB_MANIFEST" '"The cutest messenger in the Matrix network"' "\"${B_DESC}\""

# Web manifest theme colors (use jq for JSON-safe replacement)
if [ -f "$WEB_MANIFEST" ] && [ -n "$B_WEB_BG" ] && [ "$B_WEB_BG" != "null" ]; then
    old_bg=$(jq -r '.background_color' "$WEB_MANIFEST")
    old_theme=$(jq -r '.theme_color' "$WEB_MANIFEST")
    if [ "$old_bg" != "$B_WEB_BG" ] || [ "$old_theme" != "$B_WEB_THEME" ]; then
        CHANGE_COUNT=$((CHANGE_COUNT + 1))
        echo -e "  ${GREEN}✓ web/manifest.json${NC} (theme colors)"
        if ! $DRY_RUN; then
            jq --arg bg "$B_WEB_BG" --arg tc "$B_WEB_THEME" \
              '.background_color = $bg | .theme_color = $tc' \
              "$WEB_MANIFEST" > "$WEB_MANIFEST.tmp" && mv "$WEB_MANIFEST.tmp" "$WEB_MANIFEST"
        fi
    else
        echo -e "  ${BLUE}— web/manifest.json${NC} (theme colors) ${BLUE}(unchanged)${NC}"
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 8: Localization
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── Localization ─────────────────────────${NC}"

find "$PROJECT_ROOT/lib/l10n" -name "intl_*.arb" -type f | while read -r arb_file; do
    # Only try to replace if the string exists to speed things up
    if grep -q -E "FluffyChat|Fluffychat|fluffychat\.im|https://matrix\.org|\[matrix\]" "$arb_file"; then
        replace_in_file "$arb_file" "FluffyChat" "${B_NAME}"
        replace_in_file "$arb_file" "Fluffychat" "${B_NAME}"
        replace_in_file "$arb_file" "fluffychat.im" "${B_WEBSITE#https://}"
        replace_in_file "$arb_file" "https://matrix.org" "${B_WEBSITE}"
        
        # Direct replacement for literal [matrix] 
        if grep -Fq "[matrix]" "$arb_file"; then
            sed -i '' "s|\[matrix\]|[${B_NAME}]|g" "$arb_file"
        fi
    fi
done

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 9: Copy Assets
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}── Assets ───────────────────────────────${NC}"

ASSETS_SRC="$BRAND_DIR/assets"
ASSETS_DST="$PROJECT_ROOT/assets"

copy_asset() {
    local src="$ASSETS_SRC/$1"
    local dst="$ASSETS_DST/$2"

    if [ ! -f "$src" ]; then
        echo -e "  ${YELLOW}⚠ Source asset not found: $1${NC}"
        return
    fi

    if cmp -s "$src" "$dst" 2>/dev/null; then
        echo -e "  ${BLUE}— $2${NC} ${BLUE}(unchanged)${NC}"
        return
    fi

    CHANGE_COUNT=$((CHANGE_COUNT + 1))
    echo -e "  ${GREEN}✓ $1 → $2${NC}"

    if ! $DRY_RUN; then
        cp "$src" "$dst"
    fi
}

copy_asset "icon.png" "app_icon.png"
copy_asset "logo.png" "logo.png"
copy_asset "banner.png" "banner_transparent.png"
copy_asset "favicon.png" "favicon.png"

# Also copy favicon to web/
if [ -f "$ASSETS_SRC/favicon.png" ]; then
    if ! cmp -s "$ASSETS_SRC/favicon.png" "$PROJECT_ROOT/web/favicon.png" 2>/dev/null; then
        CHANGE_COUNT=$((CHANGE_COUNT + 1))
        echo -e "  ${GREEN}✓ favicon.png → web/favicon.png${NC}"
        if ! $DRY_RUN; then
            cp "$ASSETS_SRC/favicon.png" "$PROJECT_ROOT/web/favicon.png"
        fi
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 10: Record current brand
# ═══════════════════════════════════════════════════════════════════════════════
if ! $DRY_RUN; then
    echo "$BRAND_NAME" > "$PROJECT_ROOT/.current_brand"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 11: Post-apply regeneration
# ═══════════════════════════════════════════════════════════════════════════════
if ! $DRY_RUN && ! $SKIP_REGEN; then
    echo -e "${CYAN}── Regenerating Platform Assets ─────────${NC}"
    echo -e "  Running flutter pub get..."
    (cd "$PROJECT_ROOT" && flutter pub get) > /dev/null 2>&1

    echo -e "  Regenerating launcher icons..."
    (cd "$PROJECT_ROOT" && dart run flutter_launcher_icons) > /dev/null 2>&1 || \
        echo -e "  ${YELLOW}⚠ flutter_launcher_icons failed (run manually)${NC}"

    echo -e "  Regenerating splash screen..."
    (cd "$PROJECT_ROOT" && dart run flutter_native_splash:create) > /dev/null 2>&1 || \
        echo -e "  ${YELLOW}⚠ flutter_native_splash failed (run manually)${NC}"

    echo -e "  Regenerating l10n..."
    (cd "$PROJECT_ROOT" && flutter gen-l10n) > /dev/null 2>&1 || \
        echo -e "  ${YELLOW}⚠ flutter gen-l10n failed (run manually)${NC}"

    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}========================================${NC}"
if $DRY_RUN; then
    echo -e "${YELLOW}DRY RUN COMPLETE${NC}"
    echo ""
    echo -e "  Would make: ${BLUE}${CHANGE_COUNT}${NC} changes"
    echo ""
    echo -e "  Run without ${YELLOW}--dry-run${NC} to apply changes."
else
    echo -e "${GREEN}BRAND APPLIED SUCCESSFULLY${NC}"
    echo ""
    echo -e "  Brand:   ${GREEN}$BRAND_DISPLAY_NAME${NC}"
    echo -e "  Changes: ${BLUE}${CHANGE_COUNT}${NC}"
    echo -e "  Saved:   ${BLUE}.current_brand${NC}"
fi
echo -e "${CYAN}========================================${NC}"

# ═══════════════════════════════════════════════════════════════════════════════
# Verification: check for remaining FluffyChat references
# ═══════════════════════════════════════════════════════════════════════════════
if ! $DRY_RUN; then
    echo ""
    echo -e "${CYAN}── Verification ─────────────────────────${NC}"

    remaining=$(grep -r "FluffyChat" "$PROJECT_ROOT" \
        --include="*.dart" --include="*.xml" --include="*.plist" \
        --include="*.json" --include="*.html" --include="*.cc" \
        --include="*.cpp" --include="*.rc" --include="*.xcconfig" \
        --include="*.yaml" --include="*.kts" \
        -l 2>/dev/null \
        | grep -v "package:fluffychat" \
        | grep -v "FluffyChat Share" \
        | grep -v "brands/" \
        | grep -v ".dart_tool" \
        | grep -v "l10n/l10n_" \
        | wc -l | tr -d ' ')

    if [ "$remaining" -eq 0 ]; then
        echo -e "  ${GREEN}✓ No remaining FluffyChat references found${NC}"
    else
        echo -e "  ${YELLOW}⚠ Files still containing 'FluffyChat':${NC}"
        grep -r "FluffyChat" "$PROJECT_ROOT" \
            --include="*.dart" --include="*.xml" --include="*.plist" \
            --include="*.json" --include="*.html" --include="*.cc" \
            --include="*.cpp" --include="*.rc" --include="*.xcconfig" \
            --include="*.yaml" --include="*.kts" \
            -l 2>/dev/null \
            | grep -v "package:fluffychat" \
            | grep -v "FluffyChat Share" \
            | grep -v "brands/" \
            | grep -v ".dart_tool" \
            | grep -v "l10n/l10n_" \
            | while IFS= read -r file; do
                echo -e "    ${YELLOW}${file#$PROJECT_ROOT/}${NC}"
            done
        echo ""
        echo -e "  ${BLUE}Note: Some references (like iOS Share Extension directory name,${NC}"
        echo -e "  ${BLUE}Dart package imports) are expected and can be ignored.${NC}"
    fi
fi
