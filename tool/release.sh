#!/usr/bin/env bash
# 发布新版本到 GitHub Release，平板上的 App 会自动检查并更新。
#
# 用法：tool/release.sh <版本号> [更新说明]
#   例：tool/release.sh 1.0.1 "修复字幕方块；新增长按标记已看"
#
# 前提：gh 已登录且有本仓库写权限；工作区已提交干净
# 可选：.secrets/tmdb_api_key 放 TMDB v3 Key，会作为默认 Key 打包进 App（不进 git）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?用法: tool/release.sh <版本号如 1.0.1> [更新说明]}"
NOTES="${2:-ReelNest $VERSION}"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "版本号格式应为 1.2.3"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "工作区有未提交的改动，请先提交"; exit 1; }

OLD_BUILD=$(grep -E '^version:' pubspec.yaml | sed -E 's/.*\+([0-9]+).*/\1/')
BUILD=$((OLD_BUILD + 1))
TAG="v$VERSION+$BUILD"
echo "==> 发布 $TAG"

# 构建失败时还原版本号
trap 'git checkout -- pubspec.yaml 2>/dev/null || true' ERR
sed -i '' -E "s/^version: .*/version: $VERSION+$BUILD/" pubspec.yaml

export LANG=en_US.UTF-8
# 内置的默认 TMDB Key：只存在本机 .secrets/（git 已忽略），打包时编译进 App，源码里没有
DEFINES=()
if [[ -s .secrets/tmdb_api_key ]]; then
  DEFINES+=(--dart-define=TMDB_API_KEY="$(tr -d '[:space:]' < .secrets/tmdb_api_key)")
  echo "==> 内置 TMDB Key：是"
else
  echo "==> 内置 TMDB Key：否（.secrets/tmdb_api_key 不存在，用户需要自己在设置里填）"
fi
flutter build apk --release --split-per-abi "${DEFINES[@]}"

OUT=build/app/outputs/flutter-apk
mkdir -p dist
rm -f dist/ReelNest-"$VERSION"-*.apk
cp "$OUT/app-arm64-v8a-release.apk"   "dist/ReelNest-$VERSION-arm64.apk"
cp "$OUT/app-armeabi-v7a-release.apk" "dist/ReelNest-$VERSION-armv7.apk"
cp "$OUT/app-x86_64-release.apk"      "dist/ReelNest-$VERSION-x86_64.apk"
trap - ERR

git add pubspec.yaml
git commit -q -m "release $TAG"
git tag "$TAG"
git push -q origin HEAD "$TAG"
gh release create "$TAG" dist/ReelNest-"$VERSION"-*.apk --title "ReelNest $VERSION" --notes "$NOTES"
echo "==> 完成：$TAG"
