#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/FolderPeek.xcodeproj"
APP_NAME="FolderPeek"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/FolderPeekDerivedData}"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_DIR="${TMPDIR:-/tmp}/FolderPeekPackage"
INSTALL_APP_PATH="/Applications/$APP_NAME.app"
APP_ENTITLEMENTS="$ROOT_DIR/FolderPeek/Resources/FolderPeek.entitlements"
EXTENSION_ENTITLEMENTS="$ROOT_DIR/FolderPeekQuickLookExtension/Resources/FolderPeekQuickLookExtension.entitlements"

sign_folderpeek_app() {
  local app_path="$1"
  local extension_path="$app_path/Contents/PlugIns/FolderPeekQuickLookExtension.appex"
  local sparkle_framework="$app_path/Contents/Frameworks/Sparkle.framework"

  codesign --force --sign - "$app_path/Contents/Frameworks/FolderPeekCore.framework"
  codesign --force --sign - "$extension_path/Contents/Frameworks/FolderPeekCore.framework"
  if [[ -d "$sparkle_framework" ]]; then
    if [[ -d "$sparkle_framework/Versions/Current/XPCServices/Downloader.xpc" ]]; then
      codesign --force --sign - "$sparkle_framework/Versions/Current/XPCServices/Downloader.xpc"
    fi
    if [[ -d "$sparkle_framework/Versions/Current/XPCServices/Installer.xpc" ]]; then
      codesign --force --sign - "$sparkle_framework/Versions/Current/XPCServices/Installer.xpc"
    fi
    if [[ -d "$sparkle_framework/Versions/Current/Updater.app" ]]; then
      codesign --force --sign - "$sparkle_framework/Versions/Current/Updater.app"
    fi
    codesign --force --sign - "$sparkle_framework"
  fi
  codesign --force --sign - --entitlements "$EXTENSION_ENTITLEMENTS" "$extension_path"
  codesign --force --sign - --entitlements "$APP_ENTITLEMENTS" "$app_path"
}

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  pkill -x "$APP_NAME" || true
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
DIST_APP_PATH="$DIST_DIR/$APP_NAME.app"
PACKAGE_APP_PATH="$PACKAGE_DIR/$APP_NAME.app"

mkdir -p "$DIST_DIR"
rm -rf "$PACKAGE_APP_PATH"
mkdir -p "$PACKAGE_DIR"
ditto --noextattr --noqtn "$APP_PATH" "$PACKAGE_APP_PATH"
xattr -cr "$PACKAGE_APP_PATH" || true
sign_folderpeek_app "$PACKAGE_APP_PATH"
codesign --verify --deep --strict --verbose=2 "$PACKAGE_APP_PATH"

rm -rf "$DIST_APP_PATH"
ditto --noextattr --noqtn "$PACKAGE_APP_PATH" "$DIST_APP_PATH"
APP_PATH="$DIST_APP_PATH"

case "${1:-}" in
  --dist-only)
    ;;
  *)
    rm -rf "$INSTALL_APP_PATH"
    ditto --noextattr --noqtn "$PACKAGE_APP_PATH" "$INSTALL_APP_PATH"
    xattr -cr "$INSTALL_APP_PATH" || true
    sign_folderpeek_app "$INSTALL_APP_PATH"
    codesign --verify --deep --strict --verbose=2 "$INSTALL_APP_PATH"
    pluginkit -a "$INSTALL_APP_PATH/Contents/PlugIns/FolderPeekQuickLookExtension.appex" || true
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$INSTALL_APP_PATH" || true
    APP_PATH="$INSTALL_APP_PATH"
    ;;
esac

qlmanage -r >/dev/null 2>&1 || true
echo "App available at: $APP_PATH"

case "${1:-}" in
  --verify)
    /usr/bin/open -n "$APP_PATH"
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME is running"
    ;;
  --logs)
    /usr/bin/open -n "$APP_PATH"
    /usr/bin/log stream --info --predicate "process == '$APP_NAME'"
    ;;
  *)
    /usr/bin/open -n "$APP_PATH"
    ;;
esac
