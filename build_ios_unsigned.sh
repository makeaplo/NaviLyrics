#!/bin/bash
# ============================================================
# NaviLyrics - LiveContainer IPA 构建脚本（Mac 上运行）
# 用法: ./build_ios_unsigned.sh
# 产物: build/NaviLyrics-iOS18-LiveContainer.ipa
# 原理: 关闭开发者签名构建，再补 ad-hoc 签名供 LiveContainer 重签
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${BUILD_DIR:-$ROOT/build}"
PROJECT="$ROOT/NaviLyrics.xcodeproj"
SCHEME="NaviLyrics"
APP_NAME="NaviLyrics"
DERIVED_DATA="$BUILD/DerivedData-iOS"
TEST_DERIVED_DATA="$BUILD/DerivedData-Tests"
STAGING="$BUILD/IPA"
IPA_PATH="$BUILD/NaviLyrics-iOS18-LiveContainer.ipa"
XCODEBUILD_BIN="${XCODEBUILD_BIN:-xcodebuild}"

resolve_test_destination() {
  if [[ -n "${TEST_DESTINATION:-}" ]]; then
    printf '%s\n' "$TEST_DESTINATION"
    return
  fi

  local simulator_id
  local simulator_ids
  simulator_ids="$("$XCODEBUILD_BIN" \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -showdestinations 2>/dev/null \
    | sed -nE \
      's/.*platform:iOS Simulator,.*id:([0-9A-Fa-f-]{36}),.*/\1/p')"
  simulator_id="${simulator_ids%%$'\n'*}"

  if [[ -z "$simulator_id" ]]; then
    echo "❌ 没有与当前 Xcode 匹配的 iOS Simulator" >&2
    echo "   请安装匹配 Runtime，或通过 TEST_DESTINATION 指定测试目标" >&2
    exit 1
  fi

  printf 'platform=iOS Simulator,id=%s\n' "$simulator_id"
}

TEST_DESTINATION_RESOLVED="$(resolve_test_destination)"

rm -rf "$TEST_DERIVED_DATA" "$DERIVED_DATA" "$STAGING"
rm -f "$IPA_PATH"
mkdir -p "$BUILD"

echo "========== 运行单元测试 =========="

"$XCODEBUILD_BIN" test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "$TEST_DESTINATION_RESOLVED" \
  -derivedDataPath "$TEST_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO

echo "========== 构建 iOS Release（无签名） =========="

"$XCODEBUILD_BIN" clean build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE="" \
  PROVISIONING_PROFILE_SPECIFIER=""

APP_PATH="$(find "$DERIVED_DATA/Build/Products/Release-iphoneos" -maxdepth 2 -name "$APP_NAME.app" -type d -print -quit)"

if [[ -z "$APP_PATH" ]]; then
  echo "❌ 找不到构建产物：$APP_NAME.app"
  exit 1
fi

echo "========== 添加 LiveContainer 可重签的 ad-hoc 签名 =========="

mkdir -p "$STAGING/Payload"
ditto --norsrc "$APP_PATH" "$STAGING/Payload/$APP_NAME.app"
codesign --force --sign - --timestamp=none "$STAGING/Payload/$APP_NAME.app"
codesign --verify --deep --strict "$STAGING/Payload/$APP_NAME.app"

echo "========== 生成 IPA =========="

ditto -c -k --norsrc --keepParent "$STAGING/Payload" "$IPA_PATH"

if [[ ! -f "$IPA_PATH" ]]; then
  echo "❌ 生成 IPA 失败"
  exit 1
fi

unzip -tq "$IPA_PATH"
ls -lh "$IPA_PATH"
echo "✅ 已生成：$IPA_PATH"
echo "   传到 iPhone 后，用 LiveContainer 导入并强制重新签名"
