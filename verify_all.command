#!/bin/zsh
# ============================================================
#  MacSystemCleaner 验证脚本
#  强制运行所有 20 项检查，不过滤阈值，完整记录日志
#  仅诊断，不执行任何清理操作
#  最后输出分析：哪些项异常、为什么、怎么自己清理
# ============================================================

# 确保以 zsh 运行：若用户 `bash verify_all.command` 启动，bash 不解释 \033 颜色码
[ -z "$ZSH_VERSION" ] && exec zsh "$0" "$@"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 脚本目录若只读（如从 DMG 挂载点运行），log 降级到 ~/Downloads/ 或 $HOME
if [ -w "$SCRIPT_DIR" ]; then
    LOG_DIR="$SCRIPT_DIR"
else
    LOG_DIR="$HOME/Downloads"
    [ -d "$LOG_DIR" ] && [ -w "$LOG_DIR" ] || LOG_DIR="$HOME"
    echo "（脚本目录只读，日志将写入 $LOG_DIR/）"
fi
LOG_FILE="${LOG_DIR}/verify_$(date '+%Y%m%d_%H%M%S').log"

log() {
    local msg="[$(date '+%H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

# 不带时间戳的输出（用于最后的分析段落，读起来更自然）
say() {
    echo "$*" | tee -a "$LOG_FILE"
}

human_size_kb() {
    local kb=$1
    if [ "$kb" -ge 1048576 ]; then
        local gb_int=$((kb / 1048576))
        local gb_frac=$(( (kb % 1048576) * 10 / 1048576 ))
        echo "${gb_int}.${gb_frac} GB"
    elif [ "$kb" -ge 1024 ]; then
        local mb_int=$((kb / 1024))
        local mb_frac=$(( (kb % 1024) * 10 / 1024 ))
        echo "${mb_int}.${mb_frac} MB"
    else
        echo "${kb} KB"
    fi
}

# 将应用的 bundle id / 目录名翻译成中文/官方名（便于一眼识别）
# 覆盖常见国内外应用；未命中则返回原名
translate_app_name() {
    local name="$1"
    case "$name" in
        # ── 国内主流办公/协作 ──
        LarkShell|LarkShell-*|com.bytedance.lark|com.bytedance.lark.*|Lark|Lark\ Meetings) echo "飞书 (Lark)" ;;
        com.tencent.xinWeChat|com.tencent.xinWeChat.*|WeChat) echo "微信" ;;
        com.tencent.WeWorkMac) echo "企业微信" ;;
        com.tencent.qq|com.tencent.tim) echo "QQ" ;;
        com.tencent.meeting|wemeetapp.*) echo "腾讯会议" ;;
        com.alibaba.DingTalkMac|com.alibaba.DingTalk*) echo "钉钉" ;;
        com.netease.163music|com.netease.neteasemusic) echo "网易云音乐" ;;
        com.xiaohongshu.discover|com.xiaohongshu.*|xhs-*) echo "小红书 (RED)" ;;
        com.bytedance.douyin*|com.bytedance.Feishu*) echo "抖音/字节应用" ;;
        com.bilibili.bilibili*) echo "哔哩哔哩" ;;
        com.kwai.*) echo "快手" ;;

        # ── 开发工具 / IDE ──
        com.microsoft.VSCode|com.microsoft.VSCode.ShipIt) echo "VS Code" ;;
        com.todesktop.*|com.anthropic.*|claude-code) echo "Claude / Anthropic 工具" ;;
        com.cursor.Cursor|com.cursorhq.*) echo "Cursor" ;;
        Trae|Trae\ CN|com.bytedance.Trae*) echo "Trae (字节 AI IDE)" ;;
        JetBrains|com.jetbrains.*|JetBrains*|IntelliJIdea*|WebStorm*|PyCharm*|GoLand*|CLion*|RubyMine*) echo "JetBrains 系列 IDE" ;;
        com.apple.dt.Xcode|Xcode) echo "Xcode" ;;
        DerivedData) echo "Xcode 构建缓存 (DerivedData)" ;;
        CoreSimulator) echo "iOS 模拟器" ;;
        Homebrew) echo "Homebrew" ;;
        pip) echo "pip (Python 包缓存)" ;;
        go-build) echo "Go 编译缓存" ;;
        ms-playwright) echo "Playwright (浏览器测试)" ;;
        com.docker.docker|Docker|docker-desktop) echo "Docker Desktop" ;;
        dev.orbstack.*|OrbStack) echo "OrbStack" ;;
        com.github.GitHubClient|GitHub\ Desktop) echo "GitHub Desktop" ;;

        # ── 浏览器 ──
        com.google.Chrome|Google|Google\ Chrome) echo "Google Chrome" ;;
        com.microsoft.edgemac|Microsoft\ Edge) echo "Microsoft Edge" ;;
        org.mozilla.firefox|Firefox) echo "Firefox" ;;
        com.apple.Safari) echo "Safari" ;;
        com.operasoftware.Opera|Opera) echo "Opera" ;;
        com.brave.Browser) echo "Brave" ;;
        com.vivaldi.Vivaldi) echo "Vivaldi" ;;
        company.thebrowser.Browser|Arc) echo "Arc 浏览器" ;;

        # ── Microsoft 365 ──
        com.microsoft.Outlook) echo "Outlook" ;;
        com.microsoft.Word) echo "Word" ;;
        com.microsoft.Excel) echo "Excel" ;;
        com.microsoft.Powerpoint) echo "PowerPoint" ;;
        com.microsoft.onenote.mac) echo "OneNote" ;;
        com.microsoft.OneDrive) echo "OneDrive" ;;
        com.microsoft.teams|com.microsoft.teams2) echo "Microsoft Teams" ;;
        UBF8T346G9.Office|UBF8T346G9.OfficeOsfWebHost) echo "Microsoft Office 共享数据" ;;
        UBF8T346G9.OneDriveSyncClientSuite) echo "OneDrive 同步" ;;

        # ── Apple 自带 ──
        com.apple.mail) echo "Apple 邮件" ;;
        com.apple.photos|com.apple.Photos) echo "Apple 照片" ;;
        com.apple.Music|com.apple.music) echo "Apple Music" ;;
        com.apple.TV|com.apple.tv) echo "Apple TV" ;;
        com.apple.podcasts|243LU875E5.groups.com.apple.podcasts) echo "Apple Podcasts" ;;
        com.apple.MobileSync|MobileSync) echo "iOS 设备备份" ;;
        com.apple.iconservices.store) echo "图标缓存数据库（macOS bug 高发）" ;;
        com.apple.bird) echo "iCloud 文件守护进程 (bird)" ;;
        com.apple.cloudphotosd) echo "iCloud Photos 守护进程 (cloudphotosd)" ;;
        com.apple.mediaanalysisd) echo "Photos 分析 (mediaanalysisd, Sequoia bug 高发)" ;;
        CloudKit) echo "iCloud 数据缓存" ;;
        CloudDocs) echo "iCloud Drive 文档缓存" ;;
        com.apple.iWork.Pages) echo "Pages" ;;
        com.apple.iWork.Keynote) echo "Keynote" ;;
        com.apple.iWork.Numbers) echo "Numbers" ;;
        com.apple.FaceTime) echo "FaceTime" ;;
        Messages) echo "信息 (iMessage)" ;;

        # ── 聊天 / 社交 ──
        com.tinyspeck.slackmacgap|Slack) echo "Slack" ;;
        ru.keepcoder.Telegram|Telegram) echo "Telegram" ;;
        com.hnc.Discord|Discord) echo "Discord" ;;
        net.whatsapp.WhatsApp) echo "WhatsApp" ;;
        us.zoom.xos|ZoomUs) echo "Zoom" ;;
        com.spotify.client|Spotify) echo "Spotify" ;;

        # ── 笔记 / 知识库 ──
        md.obsidian|com.obsidian.Obsidian|Obsidian) echo "Obsidian" ;;
        com.notion.id|notion.id|Notion) echo "Notion" ;;
        com.logseq.*|Logseq) echo "Logseq" ;;

        # ── Adobe / 设计 ──
        Media\ Cache|Media\ Cache\ Files) echo "Adobe 媒体缓存（可安全清理）" ;;
        com.adobe.LightroomClassicCC|Adobe\ Lightroom\ Classic) echo "Lightroom Classic" ;;
        com.adobe.Photoshop|Adobe\ Photoshop*) echo "Photoshop" ;;
        com.adobe.Premiere*|Adobe\ Premiere*) echo "Premiere Pro" ;;
        com.adobe.AfterEffects|Adobe\ After\ Effects) echo "After Effects" ;;
        com.adobe.Illustrator) echo "Illustrator" ;;
        com.adobe.InDesign) echo "InDesign" ;;
        com.adobe.AdobeLightroom) echo "Lightroom CC" ;;
        com.figma.Desktop|Figma) echo "Figma" ;;
        com.bohemiancoding.sketch3|Sketch) echo "Sketch" ;;

        # ── 影音 / 剪辑 ──
        com.apple.FinalCut|FinalCut) echo "Final Cut Pro" ;;
        com.apple.LogicPro|Logic\ Pro) echo "Logic Pro" ;;
        com.apple.GarageBand*|GarageBand) echo "GarageBand" ;;
        org.videolan.vlc|VLC) echo "VLC" ;;
        com.colliderli.iina|IINA) echo "IINA" ;;

        # ── 游戏 / 其他常见大户 ──
        com.valvesoftware.steam|Steam) echo "Steam" ;;
        Epic|com.epicgames.EpicGamesLauncher) echo "Epic Games" ;;
        Battle.net|net.battle.*) echo "Battle.net" ;;

        # ── 系统基础 / 沙盒通用 ──
        group.com.apple.coreservices.useractivityd) echo "接力 / 通用剪贴板 (useractivityd)" ;;
        group.com.apple.*) echo "Apple 共享数据" ;;
        "Desktop Pictures") echo "桌面壁纸" ;;
        ColorSync) echo "色彩管理" ;;

        *) echo "$name" ;;
    esac
}

# 把名字包装成"中文 (原名)"或原名本身（用于 top 列表显示）
display_name() {
    local folder="$1"
    local translated
    translated=$(translate_app_name "$folder")
    if [ "$translated" = "$folder" ]; then
        echo "$folder"
    else
        echo "$translated  $(echo "[$folder]")"
    fi
}

get_size_kb() {
    local varname="$1" target="$2" use_sudo="${3:-no}"
    if [ ! -e "$target" ]; then
        eval "$varname=0"
        log "  路径不存在: $target"
        return
    fi
    local raw
    if [ "$use_sudo" = "sudo" ]; then
        raw=$(sudo du -sk "$target" 2>/dev/null)
    else
        raw=$(du -sk "$target" 2>/dev/null)
    fi
    local result="${raw%%[[:space:]]*}"
    # 防御：result 必须是纯数字，否则 eval 赋值可能执行任意代码
    [[ "$result" =~ ^[0-9]+$ ]] || result=0
    eval "$varname=\"\$result\""
    log "  $target → $(human_size_kb $result)"
}

# ── 持久化每项大小，供结尾分析使用 ──
SZ_ICON=0
CNT_TM=0
CNT_APFS=0
SZ_SPOTLIGHT=0
SZ_SYSLOG=0
SZ_UPDATES=0
SZ_AUDIO=0
SZ_ICLOUD=0
SZ_CORESP=0
SZ_IOSBAK=0
SZ_XCODE=0
SZ_DOCKER=0
SZ_OUTLOOK=0
SZ_ONEDRIVE=0
SZ_USERCACHE=0
SZ_MAIL=0
SZ_PODCAST=0
SZ_DEVTOOLS=0
SZ_VSCODE=0
SZ_QUICKLOOK=0
SZ_HANDOFF=0
SZ_ASITOP=0
# v0.6 新增
SZ_ICLOUD_BIRD=0
SZ_ICLOUD_PHOTOS=0
SZ_ICLOUD_CK=0
SZ_MEDIAANALYSISD=0
SZ_BIOME=0
SZ_XCODE_RUNTIME=0
SZ_ADOBE=0

# 合成信号（额外诊断时填充）
SZ_CONTAINERS=0
SZ_APPSUPPORT=0
SZ_GROUPCONT=0

echo ""
echo "MacSystemCleaner 验证脚本 — 完整诊断（仅检查，不清理）"
echo "日志文件：$LOG_FILE"
echo ""

log "=== 验证开始 ==="
log "系统: $(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null)"
log "用户: $(whoami)"
log ""

# 获取 sudo
log "请求管理员权限..."
sudo -v
SUDO_OK=$?
log "sudo -v exit=$SUDO_OK"
if [ "$SUDO_OK" -ne 0 ]; then
    log "⚠️  sudo 授权失败：系统级检查（1-7）结果将失真（路径读不到会显示 0 或路径不存在）"
fi
log ""

# ────────────────────────────────────────
log "========== 系统级检查（sudo） =========="
log ""

log "[1/28] 图标缓存数据库"
get_size_kb SZ_ICON "/Library/Caches/com.apple.iconservices.store" "sudo"
log ""

log "[2/28] Time Machine 本地快照"
tm_output=$(tmutil listlocalsnapshots / 2>/dev/null)
CNT_TM=$(echo "$tm_output" | grep -c "com.apple.TimeMachine")
[ -z "$CNT_TM" ] && CNT_TM=0
log "  快照数量: $CNT_TM"
if [ "$CNT_TM" -gt 0 ]; then
    log "  快照列表:"
    echo "$tm_output" >> "$LOG_FILE"
fi
log ""

log "[3/28] APFS 第三方快照"
# 直接用挂载点 / 而不是 "Part of Whole" 的整盘 ID（那个不是 APFS Volume，会失败）
snap_output=$(diskutil apfs listSnapshots / 2>/dev/null)
CNT_APFS=$(echo "$snap_output" | grep -c "Snapshot Name" || true)
[ -z "$CNT_APFS" ] && CNT_APFS=0
log "  挂载点 /, 快照数: $CNT_APFS"
if [ "$CNT_APFS" -gt 0 ]; then
    echo "$snap_output" >> "$LOG_FILE"
fi
log ""

log "[4/28] Spotlight 系统索引"
get_size_kb sz1 "/.Spotlight-V100" "sudo"
get_size_kb sz2 "/System/Volumes/Data/.Spotlight-V100" "sudo"
SZ_SPOTLIGHT=$((sz1 + sz2))
log "  合计: $(human_size_kb $SZ_SPOTLIGHT)"
log ""

log "[5/28] 系统日志与诊断"
get_size_kb sz_log "/private/var/log" "sudo"
get_size_kb sz_diag "/private/var/db/diagnostics" "sudo"
get_size_kb sz_uuid "/private/var/db/uuidtext" "sudo"
SZ_SYSLOG=$((sz_log + sz_diag + sz_uuid))
log "  合计: $(human_size_kb $SZ_SYSLOG)"
log ""

log "[6/28] macOS 更新暂存"
get_size_kb sz1 "/macOS Install Data" "sudo"
get_size_kb sz2 "/Library/Updates" "sudo"
SZ_UPDATES=$((sz1 + sz2))
log "  合计: $(human_size_kb $SZ_UPDATES)"
log ""

log "[7/28] GarageBand / Logic 音频库"
get_size_kb sz_loops "/Library/Audio/Apple Loops" "sudo"
get_size_kb sz_gb "/Library/Application Support/GarageBand" "sudo"
get_size_kb sz_logic "/Library/Application Support/Logic" "sudo"
SZ_AUDIO=$((sz_loops + sz_gb + sz_logic))
log "  合计: $(human_size_kb $SZ_AUDIO)"
log ""

log "========== 用户级检查 =========="
log ""

log "[8/28] iCloud Drive 缓存 (bird)"
get_size_kb sz_bird "$HOME/Library/Caches/com.apple.bird"
get_size_kb sz_cd "$HOME/Library/Application Support/CloudDocs"
SZ_ICLOUD_BIRD=$((sz_bird + sz_cd))
log "  合计: $(human_size_kb $SZ_ICLOUD_BIRD)"
log ""

log "[9/28] iCloud Photos 缓存 (cloudphotosd)"
get_size_kb SZ_ICLOUD_PHOTOS "$HOME/Library/Containers/com.apple.cloudphotosd"
log ""

log "[10/28] CloudKit 通用缓存"
get_size_kb SZ_ICLOUD_CK "$HOME/Library/Caches/CloudKit"
log ""

log "[11/28] CoreSpotlight 元数据"
get_size_kb SZ_CORESP "$HOME/Library/Metadata/CoreSpotlight"
log ""

log "[12/28] iOS 设备备份"
get_size_kb SZ_IOSBAK "$HOME/Library/Application Support/MobileSync/Backup"
log ""

log "[13/28] Xcode 开发数据（用户域）"
get_size_kb sz_dd "$HOME/Library/Developer/Xcode/DerivedData"
get_size_kb sz_sim "$HOME/Library/Developer/CoreSimulator"
get_size_kb sz_arc "$HOME/Library/Developer/Xcode/Archives"
get_size_kb sz_ds "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
SZ_XCODE=$((sz_dd + sz_sim + sz_arc + sz_ds))
log "  合计: $(human_size_kb $SZ_XCODE)"
log ""

log "[14/28] Docker 虚拟磁盘"
get_size_kb SZ_DOCKER "$HOME/Library/Containers/com.docker.docker"
log ""

log "[15/28] Outlook 邮件缓存"
get_size_kb SZ_OUTLOOK "$HOME/Library/Group Containers/UBF8T346G9.Office/Outlook"
log ""

log "[16/28] OneDrive 同步缓存"
get_size_kb SZ_ONEDRIVE "$HOME/Library/Group Containers/UBF8T346G9.OneDriveSyncClientSuite"
log ""

log "[17/28] 用户应用缓存"
get_size_kb SZ_USERCACHE "$HOME/Library/Caches"
log "  Top 5 子目录:"
du -sk "$HOME/Library/Caches/"* 2>/dev/null | sort -rn | head -5 | while read -r kb dir; do
    log "    $(human_size_kb $kb) — $(display_name "$(basename "$dir")")"
done
log ""

log "[18/28] Mail 附件缓存"
get_size_kb sz1 "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
get_size_kb sz2 "$HOME/Library/Mail"
SZ_MAIL=$((sz1 + sz2))
log "  合计: $(human_size_kb $SZ_MAIL)"
log ""

log "[19/28] Podcast 下载"
get_size_kb SZ_PODCAST "$HOME/Library/Group Containers/243LU875E5.groups.com.apple.podcasts"
log ""

log "[20/28] 开发工具缓存"
sz_brew=0; sz_npm=0; sz_pip=0; sz_cargo=0
[ -d "$HOME/Library/Caches/Homebrew" ] && get_size_kb sz_brew "$HOME/Library/Caches/Homebrew"
[ -d "$HOME/.npm" ] && get_size_kb sz_npm "$HOME/.npm"
[ -d "$HOME/Library/Caches/pip" ] && get_size_kb sz_pip "$HOME/Library/Caches/pip"
[ -d "$HOME/.cargo/registry" ] && get_size_kb sz_cargo "$HOME/.cargo/registry"
SZ_DEVTOOLS=$((sz_brew + sz_npm + sz_pip + sz_cargo))
log "  合计: $(human_size_kb $SZ_DEVTOOLS)"
log ""

log "[21/28] VS Code 缓存"
get_size_kb sz1 "$HOME/Library/Application Support/Code/Cache"
get_size_kb sz2 "$HOME/Library/Application Support/Code/CachedData"
SZ_VSCODE=$((sz1 + sz2))
log "  合计: $(human_size_kb $SZ_VSCODE)"
log ""

log "[22/28] QuickLook 缩略图"
if [ -n "$TMPDIR" ] && [ -d "${TMPDIR%/}/../C" ]; then
    ql_dir="${TMPDIR%/}/../C/com.apple.QuickLook.thumbnailcache"
else
    ql_dir="$HOME/Library/Caches/com.apple.QuickLook.thumbnailcache"
fi
get_size_kb SZ_QUICKLOOK "$ql_dir"
log ""

log "[23/28] Handoff 剪贴板存档 (useractivityd/shared-pasteboard)"
# 注意：此目录受 macOS TCC 保护，普通权限连 ls 都不行，必须用 sudo 读取大小
get_size_kb SZ_HANDOFF "$HOME/Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard/archives" "sudo"
log ""

log "[24/28] asitop 功耗采样日志 (/tmp/asitop_powermetrics*)"
sz_asitop_b=$(ls -l /tmp/asitop_powermetrics*(N) 2>/dev/null | awk '{s+=$5} END {print s+0}')
SZ_ASITOP=$((sz_asitop_b / 1024))
if [ "$SZ_ASITOP" -gt 0 ]; then
    log "  /tmp/asitop_powermetrics* → $(human_size_kb $SZ_ASITOP)"
else
    log "  /tmp/asitop_powermetrics* → 未找到（非 asitop 用户正常）"
fi
log ""

log "[25/28] mediaanalysisd 缓存 (Sequoia 15.1 引入的 Photos 分析 daemon)"
get_size_kb SZ_MEDIAANALYSISD "$HOME/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches"
log ""

log "[26/28] Biome 行为数据库 (Siri 建议 / Spotlight 个性化)"
get_size_kb SZ_BIOME "$HOME/Library/Biome/streams/restricted"
log ""

log "[27/28] Xcode Simulator Runtime (系统域)"
get_size_kb SZ_XCODE_RUNTIME "/Library/Developer/CoreSimulator" "sudo"
log ""

log "[28/28] Adobe Media Cache (Premiere / AE / Bridge)"
get_size_kb sz_adobe1 "$HOME/Library/Application Support/Adobe/Common/Media Cache Files"
get_size_kb sz_adobe2 "$HOME/Library/Application Support/Adobe/Common/Media Cache"
SZ_ADOBE=$((sz_adobe1 + sz_adobe2))
log "  合计: $(human_size_kb $SZ_ADOBE)"
log ""

# ────────────────────────────────────────
log "========== 额外诊断 =========="
log ""

log "~/Library 一级目录 Top 10:"
du -sk "$HOME/Library/"* 2>/dev/null | sort -rn | head -10 | while read -r kb dir; do
    log "  $(human_size_kb $kb) — $(display_name "$(basename "$dir")")"
done
log ""

log "~/Library/Containers 子目录 Top 10 （沙盒应用数据，通常是大头）:"
if [ -d "$HOME/Library/Containers" ]; then
    SZ_CONTAINERS=$(du -sk "$HOME/Library/Containers" 2>/dev/null | awk '{print $1}')
    du -sk "$HOME/Library/Containers/"* 2>/dev/null | sort -rn | head -10 | while read -r kb dir; do
        log "  $(human_size_kb $kb) — $(display_name "$(basename "$dir")")"
    done
    log "  （Containers 合计: $(human_size_kb ${SZ_CONTAINERS:-0})）"
else
    log "  （目录不存在）"
fi
log ""

log "~/Library/Application Support 子目录 Top 10:"
if [ -d "$HOME/Library/Application Support" ]; then
    SZ_APPSUPPORT=$(du -sk "$HOME/Library/Application Support" 2>/dev/null | awk '{print $1}')
    du -sk "$HOME/Library/Application Support/"* 2>/dev/null | sort -rn | head -10 | while read -r kb dir; do
        log "  $(human_size_kb $kb) — $(display_name "$(basename "$dir")")"
    done
    log "  （Application Support 合计: $(human_size_kb ${SZ_APPSUPPORT:-0})）"
else
    log "  （目录不存在）"
fi
log ""

log "~/Library/Group Containers 子目录 Top 10:"
if [ -d "$HOME/Library/Group Containers" ]; then
    SZ_GROUPCONT=$(du -sk "$HOME/Library/Group Containers" 2>/dev/null | awk '{print $1}')
    du -sk "$HOME/Library/Group Containers/"* 2>/dev/null | sort -rn | head -10 | while read -r kb dir; do
        log "  $(human_size_kb $kb) — $(display_name "$(basename "$dir")")"
    done
    log "  （Group Containers 合计: $(human_size_kb ${SZ_GROUPCONT:-0})）"
else
    log "  （目录不存在）"
fi
log ""

log "/Library 一级目录 Top 10:"
sudo du -sk /Library/* 2>/dev/null | sort -rn | head -10 | while read -r kb dir; do
    log "  $(human_size_kb $kb) — $(display_name "$(basename "$dir")")"
done
log ""

log "/Library/Caches 子目录 Top 10:"
sudo du -sk /Library/Caches/* 2>/dev/null | sort -rn | head -10 | while read -r kb dir; do
    log "  $(human_size_kb $kb) — $(display_name "$(basename "$dir")")"
done
log ""

log "=== 验证完成 ==="
log ""

# ============================================================
#  人话版分析：哪些项异常、为什么、怎么自己清理
# ============================================================

# 颜色（仅终端显示，日志里会带 ANSI 码不影响阅读）
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

# 收集异常项（阈值见 README；超过即列入）
PROBLEMS=()
add_problem() { PROBLEMS+=("$1"); }

# 1. 图标缓存：正常 < 100 MB，超过 1 GB 即异常
if [ "$SZ_ICON" -gt 1048576 ]; then
    add_problem "ICON|$SZ_ICON"
fi
# 2. TM 快照：超过 3 个即异常
if [ "$CNT_TM" -gt 3 ]; then
    add_problem "TM|$CNT_TM"
fi
# 3. APFS 快照：超过 2 个即异常
if [ "$CNT_APFS" -gt 2 ]; then
    add_problem "APFS|$CNT_APFS"
fi
# 4. Spotlight：超过 8 GB 异常
if [ "$SZ_SPOTLIGHT" -gt 8388608 ]; then
    add_problem "SPOTLIGHT|$SZ_SPOTLIGHT"
fi
# 5. 系统日志：超过 2 GB 异常
if [ "$SZ_SYSLOG" -gt 2097152 ]; then
    add_problem "SYSLOG|$SZ_SYSLOG"
fi
# 6. 更新暂存：超过 5 GB 异常
if [ "$SZ_UPDATES" -gt 5242880 ]; then
    add_problem "UPDATES|$SZ_UPDATES"
fi
# 7. 音频库：超过 10 GB 异常（且不使用 GarageBand/Logic 时）
if [ "$SZ_AUDIO" -gt 10485760 ]; then
    add_problem "AUDIO|$SZ_AUDIO"
fi
# 8. iCloud Drive (bird)：超过 3 GB 异常
if [ "$SZ_ICLOUD_BIRD" -gt 3145728 ]; then
    add_problem "ICLOUD_BIRD|$SZ_ICLOUD_BIRD"
fi
# 9. iCloud Photos (cloudphotosd)：超过 5 GB 异常
if [ "$SZ_ICLOUD_PHOTOS" -gt 5242880 ]; then
    add_problem "ICLOUD_PHOTOS|$SZ_ICLOUD_PHOTOS"
fi
# 10. CloudKit 通用：超过 2 GB 异常
if [ "$SZ_ICLOUD_CK" -gt 2097152 ]; then
    add_problem "ICLOUD_CK|$SZ_ICLOUD_CK"
fi
# 9. CoreSpotlight：超过 5 GB 异常
if [ "$SZ_CORESP" -gt 5242880 ]; then
    add_problem "CORESP|$SZ_CORESP"
fi
# 10. iOS 备份：超过 20 GB 提醒
if [ "$SZ_IOSBAK" -gt 20971520 ]; then
    add_problem "IOSBAK|$SZ_IOSBAK"
fi
# 11. Xcode：超过 10 GB 提醒
if [ "$SZ_XCODE" -gt 10485760 ]; then
    add_problem "XCODE|$SZ_XCODE"
fi
# 12. Docker：超过 10 GB 提醒
if [ "$SZ_DOCKER" -gt 10485760 ]; then
    add_problem "DOCKER|$SZ_DOCKER"
fi
# 13. Outlook：超过 10 GB 提醒
if [ "$SZ_OUTLOOK" -gt 10485760 ]; then
    add_problem "OUTLOOK|$SZ_OUTLOOK"
fi
# 14. OneDrive：超过 10 GB 提醒
if [ "$SZ_ONEDRIVE" -gt 10485760 ]; then
    add_problem "ONEDRIVE|$SZ_ONEDRIVE"
fi
# 15. 用户应用缓存：超过 15 GB 提醒
if [ "$SZ_USERCACHE" -gt 15728640 ]; then
    add_problem "USERCACHE|$SZ_USERCACHE"
fi
# 16. Mail：超过 10 GB 提醒
if [ "$SZ_MAIL" -gt 10485760 ]; then
    add_problem "MAIL|$SZ_MAIL"
fi
# 17. Podcast：超过 5 GB 提醒
if [ "$SZ_PODCAST" -gt 5242880 ]; then
    add_problem "PODCAST|$SZ_PODCAST"
fi
# 18. 开发工具缓存：超过 3 GB 提醒
if [ "$SZ_DEVTOOLS" -gt 3145728 ]; then
    add_problem "DEVTOOLS|$SZ_DEVTOOLS"
fi
# 19. VS Code：超过 3 GB 提醒
if [ "$SZ_VSCODE" -gt 3145728 ]; then
    add_problem "VSCODE|$SZ_VSCODE"
fi
# 20. QuickLook：超过 2 GB 提醒
if [ "$SZ_QUICKLOOK" -gt 2097152 ]; then
    add_problem "QUICKLOOK|$SZ_QUICKLOOK"
fi
# 21. Handoff 剪贴板：> 512 MB 提醒
if [ "$SZ_HANDOFF" -gt 524288 ]; then
    add_problem "HANDOFF|$SZ_HANDOFF"
fi
# 22. asitop 日志：> 100 MB 提醒
if [ "$SZ_ASITOP" -gt 102400 ]; then
    add_problem "ASITOP|$SZ_ASITOP"
fi
# 23. mediaanalysisd 缓存：> 5 GB 提醒
if [ "$SZ_MEDIAANALYSISD" -gt 5242880 ]; then
    add_problem "MEDIAANALYSISD|$SZ_MEDIAANALYSISD"
fi
# 24. Biome 行为数据库：> 2 GB 提醒
if [ "$SZ_BIOME" -gt 2097152 ]; then
    add_problem "BIOME|$SZ_BIOME"
fi
# 25. Xcode Simulator Runtime（系统域）：> 20 GB 提醒
if [ "$SZ_XCODE_RUNTIME" -gt 20971520 ]; then
    add_problem "XCODE_RUNTIME|$SZ_XCODE_RUNTIME"
fi
# 26. Adobe Media Cache：> 10 GB 提醒
if [ "$SZ_ADOBE" -gt 10485760 ]; then
    add_problem "ADOBE|$SZ_ADOBE"
fi

# 合成信号：沙盒/应用数据大头（本工具不清理，给方向）
# > 50 GB 触发提示，让用户对照 Top 10 自查
if [ "$SZ_CONTAINERS" -gt 52428800 ]; then
    add_problem "CONTAINERS|$SZ_CONTAINERS"
fi
if [ "$SZ_APPSUPPORT" -gt 31457280 ]; then
    add_problem "APPSUPPORT|$SZ_APPSUPPORT"
fi

say ""
say "${B}╔════════════════════════════════════════════════════════════╗${NC}"
say "${B}║           系统数据异常占用分析                             ║${NC}"
say "${B}╚════════════════════════════════════════════════════════════╝${NC}"
say ""

if [ "$SUDO_OK" -ne 0 ]; then
    say "${Y}⚠️  sudo 授权失败，下面的系统级分析（1-7 项）不可靠。建议用${NC}"
    say "${Y}   sudo zsh verify_all.command${NC} ${Y}在终端重新运行。${NC}"
    say ""
fi

if [ ${#PROBLEMS[@]} -eq 0 ]; then
    say "${G}✅ 你的 Mac 目前没有已知的「系统数据」异常占用。${NC}"
    say ""
    say "如果「系统设置 → 储存空间」里「系统数据」仍然偏大，可能是："
    say ""
    say "  · ${B}APFS 可清除空间（purgeable）${NC}被算进系统数据 —— 这是 macOS 的"
    say "    行为：本地快照、可重新下载的文件等在需要时才释放。通常${B}重启一次${NC}"
    say "    能让系统重新统计。"
    say "  · 某些第三方应用把数据存在本工具没覆盖的路径。可以查看额外诊断里的"
    say "    ${B}~/Library${NC} 和 ${B}/Library${NC} Top 10 目录，逐一判断。"
    say "  · macOS 储存统计本身有已知误差（特别是外接存储插拔后）。"
    say ""
else
    say "发现 ${B}${R}${#PROBLEMS[@]}${NC} 个异常占用项。按原因和清理方式说明如下："
    say ""

    pn=0
    for item in "${PROBLEMS[@]}"; do
        pn=$((pn + 1))
        key="${item%%|*}"
        val="${item#*|}"

        case "$key" in
        ICON)
            say "${B}[$pn] 图标缓存数据库异常膨胀${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：/Library/Caches/com.apple.iconservices.store${NC}"
            say "    ${Y}原因：macOS 已知 bug。图标缓存数据库在频繁挂载外部存储（SD 卡、${NC}"
            say "    ${Y}       NAS、移动硬盘、相机）或生成异常图标时会无限增长。正常应该${NC}"
            say "    ${Y}       < 100 MB。这通常是「系统数据」爆仓的头号元凶。${NC}"
            say "    ${G}如果您想要自己手动清理（不可回滚，但 macOS 会自动重建）：${NC}"
            say "      sudo killall iconservicesd iconservicesagent 2>/dev/null"
            say "      sudo rm -rf /Library/Caches/com.apple.iconservices.store"
            say "      killall Dock Finder"
            say "    ${D}清理后 Dock 图标会短暂消失（几秒~几十秒）后自动重建。${NC}"
            say ""
            ;;
        TM)
            say "${B}[$pn] Time Machine 本地快照过多${NC} —— $val 个"
            say "    ${Y}原因：系统自动保留的 APFS 快照，默认最多保留 24 小时。${NC}"
            say "    ${Y}       快照数 > 3 通常说明清理异常或磁盘空间紧张未触发自动回收。${NC}"
            say "    ${G}如果您想要自己手动清理（保留外部 TM 备份的前提下安全）：${NC}"
            say "      # 查看快照列表"
            say "      tmutil listlocalsnapshots /"
            say "      # 删除指定日期的快照（时间戳替换成真实值）"
            say "      sudo tmutil deletelocalsnapshots 2026-04-20-xxxxxx"
            say "      # 或一键删除所有本地快照："
            say "      for s in \$(tmutil listlocalsnapshots / | cut -d. -f4-); do sudo tmutil deletelocalsnapshots \$s; done"
            say ""
            ;;
        APFS)
            say "${B}[$pn] APFS 快照过多${NC} —— $val 个"
            say "    ${Y}原因：第三方备份工具（Carbon Copy Cloner、SuperDuper）或系统更新${NC}"
            say "    ${Y}       过程中创建的 APFS 快照，不会自动清理。${NC}"
            say "    ${G}如果您想要自己查看+清理：${NC}"
            say "      diskutil apfs listSnapshots /"
            say "      # 根据列表里的 UUID 手动删除："
            say "      sudo diskutil apfs deleteSnapshot / -uuid <UUID>"
            say "    ${D}注意：系统自带的 Sealed System 快照别删。${NC}"
            say ""
            ;;
        SPOTLIGHT)
            say "${B}[$pn] Spotlight 系统索引异常膨胀${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：/.Spotlight-V100 + /System/Volumes/Data/.Spotlight-V100${NC}"
            say "    ${Y}原因：索引数据库损坏或重建时可能异常膨胀。正常 2-5 GB。${NC}"
            say "    ${G}如果您想要自己手动清理（官方命令，会完全重建索引）：${NC}"
            say "      sudo mdutil -E /"
            say "    ${D}⚠️ 重建耗时 30 分钟到数小时，期间 Spotlight 搜索不可用。${NC}"
            say "    ${D}   建议睡前执行。${NC}"
            say ""
            ;;
        SYSLOG)
            say "${B}[$pn] 系统日志与诊断数据过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：/private/var/log + /private/var/db/diagnostics + uuidtext${NC}"
            say "    ${Y}原因：系统运行日志 + 崩溃诊断。长期不重启或存在崩溃循环会膨胀。${NC}"
            say "    ${G}如果您想要自己手动清理（官方命令）：${NC}"
            say "      sudo log erase --all"
            say "    ${D}清除历史诊断日志，不影响系统运行。${NC}"
            say ""
            ;;
        UPDATES)
            say "${B}[$pn] macOS 更新暂存文件过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：/macOS Install Data + /Library/Updates${NC}"
            say "    ${Y}原因：已下载但未安装的 macOS 更新，或安装失败后的残留。${NC}"
            say "    ${G}如果您想要自己手动清理：${NC}"
            say "      sudo softwareupdate --clear-catalog"
            say "      # 如果还有残留（保留一个 .bak 副本可回滚）："
            say "      TS=\$(date +%Y%m%d_%H%M%S)"
            say "      [ -d '/macOS Install Data' ] && sudo mv '/macOS Install Data' \"/macOS Install Data.bak-\$TS\""
            say "      [ -d /Library/Updates ] && sudo mv /Library/Updates \"/Library/Updates.bak-\$TS\" && sudo mkdir -p /Library/Updates"
            say ""
            ;;
        AUDIO)
            say "${B}[$pn] GarageBand / Logic 音频库过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：/Library/Audio/Apple Loops + /Library/Application Support/{GarageBand,Logic}${NC}"
            say "    ${Y}原因：Apple 音乐创作软件下载的乐器包和循环素材。${NC}"
            say "    ${G}如果您想要自己手动清理：${NC}"
            say "      # 如果不使用 GarageBand/Logic：直接卸载这两个 App 最彻底"
            say "      # 如果使用：在 App 内「音效资源库 → 管理音效资源库」选择性删除"
            say "    ${D}⚠️ 不要直接 rm /Library/Audio/Apple Loops，会让 App 异常。${NC}"
            say ""
            ;;
        ICLOUD_BIRD)
            say "${B}[$pn] iCloud Drive 缓存 (bird) 异常${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Caches/com.apple.bird + ~/Library/Application Support/CloudDocs${NC}"
            say "    ${Y}原因：bird 是 iCloud Drive 的同步守护进程，同步卡住或大文件上传中时会累积。${NC}"
            say "    ${G}如果您想要自己手动清理（可回滚备份，不影响已下载文件）：${NC}"
            say "      TS=\$(date +%Y%m%d_%H%M%S)"
            say "      killall bird 2>/dev/null"
            say "      [ -d ~/Library/Caches/com.apple.bird ] && mv ~/Library/Caches/com.apple.bird ~/Library/Caches/com.apple.bird.bak-\$TS"
            say "      [ -d ~/Library/Application\\ Support/CloudDocs ] && mv ~/Library/Application\\ Support/CloudDocs ~/Library/Application\\ Support/CloudDocs.bak-\$TS"
            say "    ${D}iCloud Drive 重新同步元数据，临时中断几分钟。${NC}"
            say ""
            ;;
        ICLOUD_PHOTOS)
            say "${B}[$pn] iCloud Photos 缓存 (cloudphotosd) 异常${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Containers/com.apple.cloudphotosd${NC}"
            say "    ${Y}原因：cloudphotosd 是 Photos 的 iCloud 同步守护进程。已知 bug：同步失败时${NC}"
            say "    ${Y}       此目录可一天内涨到几百 GB。但清理风险比 bird 高，共享相簿需重下。${NC}"
            say "    ${R}⚠️  必须手动操作，按以下顺序：${NC}"
            say "      1) 打开 Photos → 设置 → iCloud → 关闭「iCloud 照片」"
            say "      2) 完全退出 Photos 应用（⌘Q）"
            say "      3) 执行："
            say "         TS=\$(date +%Y%m%d_%H%M%S)"
            say "         mv ~/Library/Containers/com.apple.cloudphotosd ~/Library/Containers/com.apple.cloudphotosd.bak-\$TS"
            say "      4) 重新打开 Photos → 设置 → iCloud，重新勾选「iCloud 照片」"
            say "    ${D}Shared Albums 会全量重下；共享相簿多时不建议清。${NC}"
            say ""
            ;;
        ICLOUD_CK)
            say "${B}[$pn] CloudKit 通用缓存异常${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Caches/CloudKit${NC}"
            say "    ${Y}原因：各类使用 iCloud 同步的 App（Notes、Reminders、第三方 App 等）的 CloudKit${NC}"
            say "    ${Y}       缓存。Monterey 12.4 起有已知 bug 可导致无限增长。${NC}"
            say "    ${G}如果您想要自己手动清理（可回滚备份，不影响云端数据）：${NC}"
            say "      TS=\$(date +%Y%m%d_%H%M%S)"
            say "      killall cloudd 2>/dev/null"
            say "      mv ~/Library/Caches/CloudKit ~/Library/Caches/CloudKit.bak-\$TS"
            say "    ${D}各 iCloud App 重新同步元数据。${NC}"
            say ""
            ;;
        CORESP)
            say "${B}[$pn] CoreSpotlight 元数据异常膨胀${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Metadata/CoreSpotlight${NC}"
            say "    ${Y}原因：应用级搜索索引（Pages 修订追踪、Mail 等）。已知 bug：${NC}"
            say "    ${Y}       Pages + iCloud 组合可膨胀至 100+ GB。${NC}"
            say "    ${G}如果您想要自己手动清理（可回滚备份）：${NC}"
            say "      TS=\$(date +%Y%m%d_%H%M%S)"
            say "      mv ~/Library/Metadata/CoreSpotlight ~/Library/Metadata/CoreSpotlight.bak-\$TS"
            say "    ${D}应用内搜索暂时不可用，会自动重建。${NC}"
            say ""
            ;;
        IOSBAK)
            say "${B}[$pn] iOS 设备备份过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Application Support/MobileSync/Backup${NC}"
            say "    ${Y}原因：iPhone/iPad 本地备份，每台设备 5-50 GB。旧设备不会自动清理。${NC}"
            say "    ${G}如果您想要自己手动清理（必须通过 UI，切勿直接 rm）：${NC}"
            say "      「系统设置 → 通用 → 储存空间 → iOS 备份」 → 选择要删的备份"
            say "    ${D}⚠️ 备份删除后不可恢复。确认不再需要才删。${NC}"
            say ""
            ;;
        XCODE)
            say "${B}[$pn] Xcode 开发数据过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Developer/Xcode/{DerivedData,Archives,iOS DeviceSupport} + CoreSimulator${NC}"
            say "    ${Y}原因：编译缓存、iOS 模拟器、旧版归档。可安全清理，下次构建会重建。${NC}"
            say "    ${G}如果您想要自己手动清理（可回滚备份）：${NC}"
            say "      TS=\$(date +%Y%m%d_%H%M%S)"
            say "      [ -d ~/Library/Developer/Xcode/DerivedData ] && mv ~/Library/Developer/Xcode/DerivedData ~/Library/Developer/Xcode/DerivedData.bak-\$TS"
            say "      xcrun simctl delete unavailable"
            say "    ${D}首次构建会慢一些；不可用的模拟器会被移除。${NC}"
            say ""
            ;;
        DOCKER)
            say "${B}[$pn] Docker 虚拟磁盘过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Containers/com.docker.docker${NC}"
            say "    ${Y}原因：Docker 把容器和镜像存在一个不断增长的虚拟磁盘里。${NC}"
            say "    ${G}如果您想要自己手动清理（官方命令）：${NC}"
            say "      docker system prune -a --volumes"
            say "    ${D}⚠️ 删除所有未使用的镜像、容器和卷。确认无重要数据再执行。${NC}"
            say ""
            ;;
        OUTLOOK)
            say "${B}[$pn] Outlook 邮件缓存过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Group Containers/UBF8T346G9.Office/Outlook${NC}"
            say "    ${Y}原因：Outlook 本地缓存所有邮件和附件。大邮箱或配置损坏时易膨胀。${NC}"
            say "    ${G}如果您想要自己手动清理：${NC}"
            say "      打开 Outlook → 右键侧栏账户 → 「重置」或「删除缓存」"
            say "    ${D}⚠️ 切勿直接 rm，Outlook 恢复极其麻烦。重置后会重新下载全部邮件。${NC}"
            say ""
            ;;
        ONEDRIVE)
            say "${B}[$pn] OneDrive 同步缓存过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Group Containers/UBF8T346G9.OneDriveSyncClientSuite${NC}"
            say "    ${Y}原因：OneDrive 未开启「按需下载」时会缓存全量文件到本地。${NC}"
            say "    ${G}如果您想要自己手动处理：${NC}"
            say "      OneDrive 设置 → 「Files On-Demand」打开"
            say "    ${D}不要直接 rm，会破坏同步状态。${NC}"
            say ""
            ;;
        USERCACHE)
            say "${B}[$pn] 用户应用缓存过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Caches${NC}"
            say "    ${Y}原因：所有应用自己的缓存。${NC}"
            say "    ${G}如果您想要自己手动清理（必须逐个判断，不要通配 rm）：${NC}"
            say "      # 先看谁占用最大："
            say "      du -sh ~/Library/Caches/* 2>/dev/null | sort -hr | head -10"
            say "      # 根据结果在对应应用内清理（Chrome→「清除浏览数据」、"
            say "      # Edge→「清除浏览数据」、Spotify→设置→存储空间 等）"
            say "    ${D}⚠️ 直接 rm -rf ~/Library/Caches/* 会误删登录态、下载进度等。${NC}"
            say ""
            ;;
        MAIL)
            say "${B}[$pn] Apple Mail 邮件与附件过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Mail + ~/Library/Containers/com.apple.mail/...${NC}"
            say "    ${Y}原因：Mail 本地存储邮件和附件，可能含服务器上没有的本地独有数据。${NC}"
            say "    ${G}如果您想要自己手动处理（建议先备份再清理）：${NC}"
            say "      打开 Mail → 「邮箱 → 导出邮箱」先做备份"
            say "      然后：右键账户 → 「重建收件箱」 或 偏好设置 → 账户 → 「减少邮件存储」"
            say "    ${D}⚠️ 切勿直接 rm ~/Library/Mail，可能丢失本地独有邮件。${NC}"
            say ""
            ;;
        PODCAST)
            say "${B}[$pn] Podcast 已下载节目过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts${NC}"
            say "    ${Y}原因：Podcast 应用的自动下载累积。${NC}"
            say "    ${G}如果您想要自己手动处理：${NC}"
            say "      Podcast 应用 → 「设置 → 自动下载」关闭"
            say "      资料库 → 节目 → 左滑删除已下载集"
            say ""
            ;;
        DEVTOOLS)
            say "${B}[$pn] 开发工具缓存过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：Homebrew + npm + pip + cargo${NC}"
            say "    ${Y}原因：包管理器的下载缓存。${NC}"
            say "    ${G}如果您想要自己手动清理（全部用官方命令）：${NC}"
            say "      brew cleanup --prune=all"
            say "      npm cache clean --force"
            say "      pip cache purge"
            say "      cargo cache --autoclean  # 如装了 cargo-cache"
            say "    ${D}下次 install 会重新下载。${NC}"
            say ""
            ;;
        VSCODE)
            say "${B}[$pn] VS Code 编辑器缓存过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Application Support/Code/{Cache,CachedData}${NC}"
            say "    ${Y}原因：VS Code 运行缓存 + 扩展缓存。${NC}"
            say "    ${G}如果您想要自己手动清理（可回滚备份）：${NC}"
            say "      TS=\$(date +%Y%m%d_%H%M%S)"
            say "      [ -d ~/Library/Application\\ Support/Code/Cache ] && mv ~/Library/Application\\ Support/Code/Cache ~/Library/Application\\ Support/Code/Cache.bak-\$TS"
            say "      [ -d ~/Library/Application\\ Support/Code/CachedData ] && mv ~/Library/Application\\ Support/Code/CachedData ~/Library/Application\\ Support/Code/CachedData.bak-\$TS"
            say "    ${D}扩展可能需要重新初始化。${NC}"
            say ""
            ;;
        QUICKLOOK)
            say "${B}[$pn] QuickLook 缩略图缓存过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：\$TMPDIR/../C/com.apple.QuickLook.thumbnailcache${NC}"
            say "    ${Y}原因：Finder 预览缩略图的缓存。正常 100-500 MB。${NC}"
            say "    ${G}如果您想要自己手动清理（官方命令）：${NC}"
            say "      qlmanage -r cache"
            say "    ${D}缩略图会重新生成，无风险。${NC}"
            say ""
            ;;
        HANDOFF)
            say "${B}[$pn] Handoff 通用剪贴板存档过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard/archives${NC}"
            say "    ${Y}原因：已知 macOS bug。开启「隔空投送与接力」时，用 Cmd+C 复制大文件${NC}"
            say "    ${Y}       （Lightroom 目录库、视频素材等）会把整份副本写入此目录，不会自动${NC}"
            say "    ${Y}       清理。Reddit / Apple 社区上 Sonoma / Sequoia 大量同类报告，最高见${NC}"
            say "    ${Y}       到几百 GB。小红书案例：MacBook Air M4 系统数据 80 GB 就是这个锅。${NC}"
            say "    ${G}如果您想要自己手动清理（此目录受 TCC 保护，需要 sudo）：${NC}"
            say "      # 保留一个 .bak 副本可回滚："
            say "      TS=\$(date +%Y%m%d_%H%M%S)"
            say "      sudo mv ~/Library/Group\\ Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard/archives \\\\"
            say "              ~/Library/Group\\ Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard/archives.bak-\$TS"
            say ""
            say "    ${G}防止复发（二选一）：${NC}"
            say "      1. 「系统设置 → 通用 → 隔空投送与接力」关闭「允许在设备之间进行接力」"
            say "      2. 大文件改用拖拽传输，避免用 Cmd+C / Cmd+V"
            say "    ${D}跨设备剪贴板短暂中断后自动恢复，零风险。${NC}"
            say ""
            ;;
        ASITOP)
            say "${B}[$pn] asitop 功耗采样日志过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：/tmp/asitop_powermetrics*${NC}"
            say "    ${Y}原因：asitop（M 系列芯片 CPU/GPU 监控工具）的 powermetrics 采样日志${NC}"
            say "    ${Y}       不会自动清理（GitHub issue tlkh/asitop#18 至今未修）。长期运行可${NC}"
            say "    ${Y}       累积数十 GB。非 asitop 用户不会有这个问题。${NC}"
            say "    ${G}如果您想要自己手动清理（零风险，/tmp 重启就清）：${NC}"
            say "      rm -f /tmp/asitop_powermetrics*"
            say "    ${D}asitop 下次启动会重新生成新日志。${NC}"
            say ""
            ;;
        MEDIAANALYSISD)
            say "${B}[$pn] Photos 分析缓存 (mediaanalysisd) 异常${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches${NC}"
            say "    ${Y}原因：Sequoia 15.1 引入的 Photos 对象/人脸识别守护进程。已知 bug：从备份${NC}"
            say "    ${Y}       恢复或系统时间异常后会反复重索引，实测可膨胀至 140 GB。${NC}"
            say "    ${G}如果您想要自己手动清理（可回滚备份）：${NC}"
            say "      TS=\$(date +%Y%m%d_%H%M%S)"
            say "      osascript -e 'tell application \"Photos\" to quit' 2>/dev/null"
            say "      sleep 1"
            say "      mv ~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches \\\\"
            say "         ~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches.bak-\$TS"
            say "    ${D}下次打开 Photos 会重新扫描库（后台进行）。不要 killall daemon —— launchd 会立刻拉起。${NC}"
            say ""
            ;;
        BIOME)
            say "${B}[$pn] Biome 行为数据库异常${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Biome/streams/restricted${NC}"
            say "    ${Y}原因：macOS 13+ 的私有行为数据库（Siri 建议 / Spotlight 个性化 / 专注模式）。${NC}"
            say "    ${Y}       已知 bug：tombstone 文件不自动清理，实测可达 113 GB。${NC}"
            say "    ${G}如果您想要自己手动清理（biomesyncd 会自动重建）：${NC}"
            say "      TS=\$(date +%Y%m%d_%H%M%S)"
            say "      mv ~/Library/Biome/streams/restricted ~/Library/Biome/streams/restricted.bak-\$TS"
            say "    ${D}Siri 建议和 Spotlight 个性化会重置，几天内重新学习恢复。${NC}"
            say ""
            ;;
        XCODE_RUNTIME)
            say "${B}[$pn] Xcode Simulator Runtime (系统域) 过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：/Library/Developer/CoreSimulator (Volumes + Cryptex)${NC}"
            say "    ${Y}原因：Xcode iOS/tvOS/watchOS 模拟器运行时。每次 Xcode 升级会保留旧版本，不${NC}"
            say "    ${Y}       自动清理。这一项独立于 ~/Library/Developer，开发者 55-62 GB 的大头。${NC}"
            say "    ${G}如果您想要自己手动清理（Apple 官方 CLI，最安全）：${NC}"
            say "      osascript -e 'tell application \"Xcode\" to quit' 2>/dev/null"
            say "      xcrun simctl shutdown all"
            say "      xcrun simctl delete unavailable"
            say "      xcrun simctl runtime delete --notUsedSinceDays 180"
            say "    ${D}官方命令只删超过 180 天未使用的 runtime；Xcode 正在用的不会被删。${NC}"
            say ""
            ;;
        ADOBE)
            say "${B}[$pn] Adobe Media Cache 过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Application Support/Adobe/Common/Media Cache*${NC}"
            say "    ${Y}原因：Premiere / After Effects / Bridge 等 Adobe 应用的媒体索引缓存${NC}"
            say "    ${Y}       （peak/CFA/索引文件）。默认上限卷容量的 10%（500 GB 盘 = 50 GB 缓存）。${NC}"
            say "    ${G}推荐：在 Premiere 内通过 Settings → Media Cache → Delete 清理（Adobe 官方推荐）${NC}"
            say "    ${G}如果不想开 Premiere，可手动清（可回滚备份）：${NC}"
            say "      TS=\$(date +%Y%m%d_%H%M%S)"
            say "      for app in 'Adobe Premiere Pro' 'Adobe After Effects' 'Adobe Media Encoder' 'Adobe Bridge' 'Adobe Photoshop'; do"
            say "          osascript -e \"tell application \\\"\$app\\\" to quit\" 2>/dev/null"
            say "      done"
            say "      sleep 2"
            say "      mv ~/Library/Application\\ Support/Adobe/Common/Media\\ Cache\\ Files \\\\"
            say "         ~/Library/Application\\ Support/Adobe/Common/Media\\ Cache\\ Files.bak-\$TS"
            say "      mv ~/Library/Application\\ Support/Adobe/Common/Media\\ Cache \\\\"
            say "         ~/Library/Application\\ Support/Adobe/Common/Media\\ Cache.bak-\$TS"
            say "    ${D}下次打开老项目会重新生成 peak/CFA 索引（首次会慢但安全）。${NC}"
            say ""
            ;;
        CONTAINERS)
            say "${B}[$pn] 沙盒应用数据占用过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Containers${NC}"
            say "    ${Y}原因：macOS 现代应用的数据主要存在这里（每个 App 一个子目录），${NC}"
            say "    ${Y}       微信聊天记录、飞书/Lark 数据、Lightroom 预览、Docker.raw 等都在这里。${NC}"
            say "    ${Y}       本工具不能替你判断哪些能删（删错会丢数据），只能指方向。${NC}"
            say "    ${G}如果您想要自己手动处理：${NC}"
            say "      ${B}请对照上面「~/Library/Containers 子目录 Top 10」${NC}："
            say "      · ${B}微信${NC}：在微信里「设置 → 通用 → 清理缓存」或「迁移聊天记录」，不要直接 rm"
            say "      · ${B}飞书 (Lark)${NC}：在飞书里「设置 → 通用 → 清除缓存」"
            say "      · ${B}Docker${NC}：docker system prune -a --volumes"
            say "      · ${B}Lightroom${NC}：Lightroom 内「偏好设置 → 性能 → 清除缓存」或调整「Camera Raw 缓存大小」"
            say "      · ${B}Xcode/模拟器${NC}：xcrun simctl delete unavailable；或 Xcode 里删旧 iOS 模拟器"
            say "      · ${B}其他${NC}：先在对应 App 里找「清理缓存」选项；确实没用的 App 直接卸载最彻底"
            say "    ${D}⚠️ 切勿直接 rm ~/Library/Containers/某子目录，会导致对应 App 登录态、${NC}"
            say "    ${D}   聊天记录、配置等永久丢失。${NC}"
            say ""
            ;;
        APPSUPPORT)
            say "${B}[$pn] 应用支持数据占用过大${NC} —— $(human_size_kb $val)"
            say "    ${D}路径：~/Library/Application Support${NC}"
            say "    ${Y}原因：非沙盒应用的数据目录（开发工具、Adobe、Steam、各种 IDE 等）。${NC}"
            say "    ${G}如果您想要自己手动处理：${NC}"
            say "      ${B}请对照上面「~/Library/Application Support 子目录 Top 10」${NC}："
            say "      · ${B}Lightroom Classic${NC}：\"Catalogs\" 目录是你的照片数据库，${R}不要删${NC}；只能在 App 里「Purge Cache」"
            say "      · ${B}Steam${NC}：在 Steam 里「设置 → 下载 → 清理下载缓存」或卸载不玩的游戏"
            say "      · ${B}JetBrains (IntelliJ/WebStorm/PyCharm 等)${NC}：Help → Delete Leftover IDE Directories"
            say "      · ${B}Xcode${NC}：DerivedData 可删（本工具 [11] 已覆盖）；iOS DeviceSupport 过期版本可删"
            say "      · ${B}Obsidian/Notion/Logseq${NC}：子目录是你的笔记，${R}千万不要直接删${NC}"
            say "      · ${B}其他${NC}：优先看能否在对应 App 内找到清理选项"
            say "    ${D}⚠️ Application Support 里很多是用户数据（笔记、配置、授权信息），${NC}"
            say "    ${D}   不像缓存目录那样可以安全删除。除非你确定是缓存或不再用的 App。${NC}"
            say ""
            ;;
        esac
    done

    say "${D}────────────────────────────────────────────────────────────${NC}"
    say ""
    say "${B}下一步怎么办？${NC}"
    say ""
    say "  · 按上面的命令自己敲（最稳，清理自己看得见的那几项）"
    say "  · 或双击运行 ${B}MacSystemCleaner.command${NC}，交互式逐项清理"
    say "  · 清理完重启一次 Mac，让系统重新统计「系统数据」"
    say ""
fi

echo ""
echo "完整日志已保存到: $LOG_FILE"
echo ""
echo "———— 诊断完成，按 ⌘W 关闭此窗口 ————"
exit 0
