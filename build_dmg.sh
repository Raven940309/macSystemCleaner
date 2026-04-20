#!/bin/zsh
# ============================================================
#  macSystemCleaner DMG 打包脚本
#
#  生成 dist/macSystemCleaner.dmg，用于百度网盘分发 / GitHub Release
#
#  用法：
#    zsh build_dmg.sh [版本号]
#    例：zsh build_dmg.sh 1.0
#  不传版本号时默认为 dev
# ============================================================

set -euo pipefail

VERSION="${1:-dev}"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${REPO_DIR}/dist/build"
STAGING="${BUILD_DIR}/macSystemCleaner"
DMG_OUT="${REPO_DIR}/dist/macSystemCleaner-${VERSION}.dmg"

echo "▶ 清理旧构建产物"
rm -rf "${BUILD_DIR}"
mkdir -p "${STAGING}"

echo "▶ 拷贝脚本（重命名为中文，保留执行位）"
cp "${REPO_DIR}/verify_all.command"        "${STAGING}/1-系统数据诊断.command"
cp "${REPO_DIR}/MacSystemCleaner.command"  "${STAGING}/2-系统数据清理.command"
chmod 755 "${STAGING}/1-系统数据诊断.command"
chmod 755 "${STAGING}/2-系统数据清理.command"

echo "▶ 拷贝 LICENSE"
cp "${REPO_DIR}/LICENSE" "${STAGING}/LICENSE.txt"

echo "▶ 生成 使用说明.txt"
cat > "${STAGING}/使用说明.txt" <<'EOF'
macSystemCleaner 使用说明
============================

这是一个 macOS「系统数据」异常占用的靶向诊断与清理工具。
起源于作者 Mac 的"系统数据"飙到 576 GB，追查到图标缓存数据库
（/Library/Caches/com.apple.iconservices.store）膨胀到 502 GB ——
这是 macOS 已知 bug，常规清理工具因沙盒限制扫不到。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
怎么用（两步）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

▶ 第一步（必做）：双击「1-系统数据诊断.command」

  这一步只扫描不改动，零风险。
  跑完会告诉你：哪些地方占用异常、为什么会这样、你可以怎么清。
  大多数人跑完这一步，知道问题在哪，就能在对应 App 里自己处理了。

▶ 第二步（可选）：双击「2-系统数据清理.command」

  只在第一步确认有异常占用、且想让工具帮你交互式清理时才跑。
  每一项都会逐项 (y/n) 确认，绝不会批量误删。

  清理策略（分 4 种）：
    • 官方命令 —— Spotlight / TM 快照 / brew / npm / pip 等
    • 移到 .bak 备份 —— iCloud / Xcode 缓存 / VS Code 缓存等，可回滚
    • 交互式二次确认 —— 图标缓存（几百 GB 那项），需要输入 DELETE 确认
    • 仅诊断不动 —— Mail / iOS 备份 / Outlook / Podcast / 微信飞书等 App 数据

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
第一次运行会遇到的提示
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

▶ "无法验证开发者"
  这是 macOS 对所有未签名脚本的常规拦截，不代表脚本有问题。
  右键点该文件 → 选「打开」→ 弹窗里再点「打开」，之后双击就能直接运行。

▶ "需要管理员密码"
  部分系统级目录（/Library 下的）需要管理员权限才能扫描。
  脚本只会读这些目录的大小；真正的清理操作，每一项都会二次让你确认。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
安全说明
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

• 本工具从不碰你的用户数据：Mail 邮件、iOS 备份、微信/飞书聊天记录、
  Outlook、Podcast、Lightroom 目录库等一律只给诊断信息，不会自动清理
• 几乎所有清理都是「移到 .bak 备份」而不是 rm，出问题可以回滚
• 仅图标缓存是不可回滚删除，但会先打开 Finder 让你核对，再要求输入
  DELETE（全大写）才会执行

建议：
  1. 重要数据先做一次 Time Machine 备份
  2. 先跑诊断，看清楚再决定是否清理
  3. 任何提示里不确定的操作，输入 n 跳过即可

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
更多信息
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

GitHub（源码可查 / 提 Issue）：
  https://github.com/Raven940309/macSystemCleaner

作者：Raven940309
License：MIT

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
免责声明
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

本工具按现状提供，作者不承担因使用本工具导致的数据丢失或系统
异常的责任。代码完全开源，建议跑之前在 GitHub 读一遍源码。

EOF

echo "▶ 生成 DMG: ${DMG_OUT}"
mkdir -p "${REPO_DIR}/dist"
rm -f "${DMG_OUT}"
hdiutil create \
    -volname "macSystemCleaner" \
    -srcfolder "${STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_OUT}" > /dev/null

echo "▶ 清理中间产物"
rm -rf "${BUILD_DIR}"

SIZE=$(du -h "${DMG_OUT}" | awk '{print $1}')
echo ""
echo "✅ 构建完成"
echo "   文件：${DMG_OUT}"
echo "   大小：${SIZE}"
echo ""
echo "验证执行位是否保留（挂载后查看）："
echo "   hdiutil attach '${DMG_OUT}' -nobrowse"
echo "   ls -la /Volumes/macSystemCleaner/"
echo "   hdiutil detach /Volumes/macSystemCleaner"
