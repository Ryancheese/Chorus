#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "未找到 xcodegen。请先安装："
  echo "  brew install xcodegen"
  exit 1
fi

xcodegen generate
echo "已生成 Chorus.xcodeproj"
echo "用 Xcode 打开后："
echo "  1) 选 Host scheme → My Mac 运行"
echo "  2) 选 Speaker scheme → 真机 iPhone/iPad 运行（需同一 Wi-Fi）"
