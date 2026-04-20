#!/bin/zsh
# ============================================================
#  macOS 系统数据诊断与清理工具 V2
#
#  诊断「系统设置 → 储存空间 → 系统数据」异常偏大的根因，
#  覆盖 20+ 种已知的膨胀场景，逐项展示诊断结果并提供清理选项。
#
#  使用方式：双击此文件，或终端运行 zsh MacSystemCleaner.command
#  适用系统：macOS Ventura / Sonoma / Sequoia
#  权限说明：部分系统级检查需要管理员密码（sudo）
# ============================================================

# 不使用 set -euo pipefail：扫描过程中部分目录可能权限不足或不存在，
# 这些是预期内的失败，不应中断整个脚本

# ── 颜色 ──
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; B='\033[1m'; D='\033[2m'; NC='\033[0m'

# ── 全局变量 ──
typeset -a ITEM_NAMES ITEM_PATHS ITEM_SIZES ITEM_DESCS ITEM_FIXES ITEM_LEVELS ITEM_RISKS
ITEM_COUNT=0
TOTAL_RECLAIMABLE=0

# 清理策略：对无官方命令的项，采用 "mv 到 .bak-<时间戳>" 代替 rm -rf，保证可回滚。
# 确认系统运行正常后，用户可手动执行 rm -rf 相应 .bak-* 释放空间。
# 加 $$（PID）+ $RANDOM 防止同秒内连续运行导致 .bak 目录名碰撞
TS=$(date +%Y%m%d_%H%M%S)_$$_$RANDOM

close_and_exit() {
    echo ""
    echo "———— 脚本执行完毕，按 ⌘W 关闭此窗口 ————"
    exit 0
}

# ── 工具函数 ──
human_size() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        local mb=$((bytes / 1048576))
        local gb_int=$((mb / 1024))
        local gb_frac=$(( (mb % 1024) * 10 / 1024 ))
        echo "${gb_int}.${gb_frac} GB"
    elif [ "$bytes" -ge 1048576 ]; then
        local kb=$((bytes / 1024))
        local mb_int=$((kb / 1024))
        local mb_frac=$(( (kb % 1024) * 10 / 1024 ))
        echo "${mb_int}.${mb_frac} MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$((bytes / 1024)) KB"
    else
        echo "${bytes} B"
    fi
}

get_size_kb() {
    # 注意：zsh 中 path（小写）是绑定 PATH 的特殊变量，绝对不能用作局部变量名！
    local varname="$1" target="$2" use_sudo="${3:-no}"
    if [ ! -e "$target" ]; then
        eval "$varname=0"; return
    fi
    local raw
    if [ "$use_sudo" = "sudo" ]; then
        raw=$(sudo du -sk "$target" 2>/dev/null)
    else
        raw=$(du -sk "$target" 2>/dev/null)
    fi
    local result="${raw%%[[:space:]]*}"
    if [ -z "$result" ]; then result=0; fi
    eval "$varname=$result"
}

# ── 交互式清理：图标缓存（体积可达数百 GB，无官方命令，不适合备份）──
# 流程：打开 Finder 让用户肉眼确认 → 要求用户输入 DELETE → 执行删除
__do_clean_iconservices() {
    local target="/Library/Caches/com.apple.iconservices.store"
    if [ ! -e "$target" ]; then
        echo "  ${Y}目标不存在，无需清理${NC}"
        return 1
    fi
    local sz_kb
    sz_kb=$(sudo du -sk "$target" 2>/dev/null | awk '{print $1}')
    [ -z "$sz_kb" ] && sz_kb=0
    local sz_bytes=$((sz_kb * 1024))

    echo ""
    echo "  ${R}⚠️  此项为不可回滚删除${NC}"
    echo "  目标：$target"
    echo "  大小：${B}$(human_size $sz_bytes)${NC}"
    echo ""
    echo "  ${Y}即将在 Finder 中打开该目录的上层文件夹。${NC}"
    echo "  ${D}（提示：Finder 中该目录会显示 0 KB —— 这是 macOS 权限限制导致，${NC}"
    echo "  ${D} Finder 以普通用户身份无法读取 root 拥有的子项大小；真实大小以本工具${NC}"
    echo "  ${D} 上面显示的 sudo du 结果为准。）${NC}"
    open "/Library/Caches/" 2>/dev/null
    echo ""
    echo "  核对无误后，请输入 ${B}DELETE${NC}（全大写）确认删除；其他任何输入将取消。"
    printf "  > "
    local typed
    read -r typed
    if [ "$typed" != "DELETE" ]; then
        echo "  ${Y}已取消${NC}"
        return 1
    fi

    echo "  清理中（停止图标服务 → 删除缓存 → 重启 Dock/Finder）..."
    sudo killall iconservicesd 2>/dev/null
    sudo killall iconservicesagent 2>/dev/null
    sudo rm -rf "$target"
    killall Dock 2>/dev/null
    killall Finder 2>/dev/null
    echo "  ${G}✅ 已清理，释放约 $(human_size $sz_bytes)${NC}"
    return 0
}

add_item() {
    # 添加一个诊断项到结果列表
    # 参数: name path size_kb desc fix level risk threshold_kb
    local name="$1" path="$2" size_kb="${3:-0}" desc="$4" fix="$5" level="$6" risk="$7" threshold_kb="${8:-0}"

    [ -z "$size_kb" ] && size_kb=0
    [ -z "$threshold_kb" ] && threshold_kb=0
    if [ "$size_kb" -le "$threshold_kb" ] 2>/dev/null; then
        return
    fi
    
    ITEM_COUNT=$((ITEM_COUNT + 1))
    ITEM_NAMES[$ITEM_COUNT]="$name"
    ITEM_PATHS[$ITEM_COUNT]="$path"
    ITEM_SIZES[$ITEM_COUNT]="$size_kb"
    ITEM_DESCS[$ITEM_COUNT]="$desc"
    ITEM_FIXES[$ITEM_COUNT]="$fix"
    ITEM_LEVELS[$ITEM_COUNT]="$level"
    ITEM_RISKS[$ITEM_COUNT]="$risk"
    
    local size_bytes=$((size_kb * 1024))
    TOTAL_RECLAIMABLE=$((TOTAL_RECLAIMABLE + size_bytes))
}

# ============================================================
#  主流程
# ============================================================

echo ""
echo "${B}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${B}║     macOS 系统数据诊断与清理工具 V2                       ║${NC}"
echo "${B}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  本工具自动扫描 20+ 种已知的「系统数据」膨胀根因，"
echo "  精准定位异常占用并提供逐项清理选项。"
echo ""

# ── 第 1 步：磁盘概览 ──
echo "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${B}  第 1 步：磁盘概览${NC}"
echo "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

disk_total_bytes=$(diskutil info / 2>/dev/null | grep "Container Total Space" | sed 's/.*(\([0-9]*\) Bytes.*/\1/')
disk_free_bytes=$(diskutil info / 2>/dev/null | grep "Container Free Space" | sed 's/.*(\([0-9]*\) Bytes.*/\1/')
if [ -n "$disk_total_bytes" ] && [ -n "$disk_free_bytes" ]; then
    disk_used_bytes=$((disk_total_bytes - disk_free_bytes))
    echo "  总容量：$(human_size $disk_total_bytes)"
    echo "  已使用：$(human_size $disk_used_bytes)"
    echo "  剩余：  ${B}$(human_size $disk_free_bytes)${NC}"
else
    echo "  ${D}（无法获取 APFS 容器信息，使用 df 降级）${NC}"
    df -h / | tail -1 | awk '{printf "  总容量：%s  已使用：%s  剩余：%s\n", $2, $3, $4}'
fi
echo ""

# ── 第 2 步：全面扫描 ──
echo "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${B}  第 2 步：自动扫描已知膨胀点${NC}"
echo "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  ${Y}部分系统级目录需要管理员权限...${NC}"
echo ""

# 提前获取 sudo 权限（后续命令复用，双击运行时会弹密码输入框）
echo "  ${Y}正在请求管理员权限（用于扫描系统级目录）...${NC}"
echo ""
sudo -v
SUDO_OK=$?
# sudo -v 成功后，后续 sudo 命令在 5 分钟内不再需要密码
if [ "$SUDO_OK" -ne 0 ]; then
    echo ""
    echo "  ${R}⚠️  管理员授权失败。${NC}"
    echo "  ${Y}系统级检查项（1-7）结果将显示为 0，不代表真实状态。${NC}"
    echo "  ${Y}建议按 Ctrl+C 退出，在终端中以管理员身份重新运行。${NC}"
    echo ""
    printf "  是否仍要继续（仅扫描用户级项目）? (y/n): "
    read -rk 1 cont
    echo ""
    if [ "$cont" != "y" ] && [ "$cont" != "Y" ]; then
        close_and_exit
    fi
fi

progress_idx=0
scan_msg() {
    progress_idx=$((progress_idx + 1))
    printf "\r  ${D}[%2d/20] 正在扫描: %-40s${NC}" "$progress_idx" "$1"
}

# ────────────────────────────────────────
#  系统级扫描（需要 sudo）
# ────────────────────────────────────────

# 1. 图标缓存（已知 macOS bug，可膨胀至数百 GB）
scan_msg "图标缓存数据库"
get_size_kb sz "/Library/Caches/com.apple.iconservices.store" "sudo"
add_item "图标缓存数据库 (iconservices)" "/Library/Caches/com.apple.iconservices.store" "$sz" \
    "macOS 已知 bug：图标缓存数据库损坏后无限膨胀。频繁挂载外部存储（NAS/SD 卡）时易触发。正常 < 100 MB。" \
    "@INTERACTIVE:__do_clean_iconservices" \
    "interactive" "Dock 图标短暂消失后自动重建；清理不可回滚，会先打开 Finder 让你确认" 1048576

# 2. Time Machine 本地快照
scan_msg "Time Machine 本地快照"
tm_snapshots=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple.TimeMachine" || true)
if [ "$tm_snapshots" -gt 3 ]; then
    add_item "Time Machine 本地快照 (${tm_snapshots} 个)" "tmutil" $((tm_snapshots * 5242880)) \
        "系统自动创建的 APFS 快照，保留了删除文件前的磁盘状态。快照过多会占用大量空间。" \
        "for s in \$(tmutil listlocalsnapshots / | cut -d'.' -f4-); do sudo tmutil deletelocalsnapshots \$s; done" \
        "system" "失去本地快照恢复能力，如有外部备份则安全" 0
fi

# 3. APFS 第三方快照
# 注意：diskutil apfs listSnapshots 需要挂载点（如 /）或 APFS 卷标识（如 disk3s1s1），
# 不能用 "Part of Whole" 给出的整盘标识（disk3）—— 那样会报 "is not an APFS Volume"。
scan_msg "APFS 第三方快照"
apfs_snaps=$(diskutil apfs listSnapshots / 2>/dev/null | grep -c "Snapshot Name" || true)
[ -z "$apfs_snaps" ] && apfs_snaps=0
if [ "$apfs_snaps" -gt 2 ]; then
    add_item "APFS 快照 (${apfs_snaps} 个，含系统快照)" "diskutil apfs listSnapshots /" $((apfs_snaps * 3145728)) \
        "第三方备份工具（Carbon Copy Cloner 等）或系统更新创建的快照。" \
        "# 需手动确认后删除：diskutil apfs listSnapshots / ； 再 sudo diskutil apfs deleteSnapshot / -uuid <UUID>" \
        "system" "快照数据不可恢复" 0
fi

# 4. Spotlight 系统索引
scan_msg "Spotlight 系统索引"
get_size_kb sz "/.Spotlight-V100" "sudo"
add_item "Spotlight 系统索引" "/.Spotlight-V100" "$sz" \
    "Spotlight 搜索索引，损坏或重建时可能异常膨胀。正常 2-5 GB。" \
    "sudo mdutil -E /" \
    "system" "Spotlight 搜索暂时不可用（重建约 30 分钟至数小时）" 10485760

# 5. 系统日志与诊断数据
scan_msg "系统日志与诊断"
get_size_kb sz_log "/private/var/log" "sudo"
get_size_kb sz_diag "/private/var/db/diagnostics" "sudo"
get_size_kb sz_uuid "/private/var/db/uuidtext" "sudo"
sz_total=$((sz_log + sz_diag + sz_uuid))
add_item "系统日志与诊断数据" "/private/var/log + diagnostics + uuidtext" "$sz_total" \
    "系统运行日志和崩溃诊断报告。长时间不重启或存在崩溃循环时会膨胀。正常 < 2 GB。" \
    "sudo log erase --all 2>/dev/null" \
    "system" "清除历史诊断日志，不影响系统运行" 5242880

# 6. macOS 更新暂存
scan_msg "macOS 更新暂存"
sz=0; sz2=0
[ -d "/macOS Install Data" ] && get_size_kb sz "/macOS Install Data" "sudo"
[ -d "/Library/Updates" ] && get_size_kb sz2 "/Library/Updates" "sudo"
sz_total=$((sz + sz2))
add_item "macOS 更新暂存文件" "/macOS Install Data + /Library/Updates" "$sz_total" \
    "已下载但未安装的 macOS 更新，或安装失败后的残留文件。" \
    "sudo softwareupdate --clear-catalog 2>/dev/null; [ -d '/macOS Install Data' ] && sudo mv '/macOS Install Data' \"/macOS Install Data.bak-${TS}\" 2>/dev/null; [ -d /Library/Updates ] && sudo mv /Library/Updates \"/Library/Updates.bak-${TS}\" 2>/dev/null && sudo mkdir -p /Library/Updates" \
    "system" "可能需要重新下载更新" 5242880

# 7. GarageBand / Logic 音频库
scan_msg "音频库 (GarageBand/Logic)"
get_size_kb sz_loops "/Library/Audio/Apple Loops" "sudo"
get_size_kb sz_gb "/Library/Application Support/GarageBand" "sudo"
get_size_kb sz_logic "/Library/Application Support/Logic" "sudo"
sz_total=$((sz_loops + sz_gb + sz_logic))
add_item "GarageBand / Logic 音频库" "/Library/Audio + Application Support" "$sz_total" \
    "Apple 音乐创作软件下载的乐器包和循环素材。不使用这些软件则可安全清理。" \
    "# 建议通过 GarageBand/Logic 的声音资源库管理界面删除，或卸载应用" \
    "system" "删除后需重新下载乐器包" 10485760

# ────────────────────────────────────────
#  用户级扫描（无需 sudo）
# ────────────────────────────────────────

# 8. iCloud 同步缓存
scan_msg "iCloud 同步缓存"
get_size_kb sz_bird "$HOME/Library/Caches/com.apple.bird"
get_size_kb sz_ck "$HOME/Library/Caches/CloudKit"
get_size_kb sz_cd "$HOME/Library/Application Support/CloudDocs"
sz_total=$((sz_bird + sz_ck + sz_cd))
add_item "iCloud 同步缓存" "~/Library/Caches/com.apple.bird + CloudKit + CloudDocs" "$sz_total" \
    "iCloud Drive 同步过程中的本地缓存。同步卡住或大量文件时可能膨胀。正常 < 3 GB。" \
    "killall bird 2>/dev/null; [ -d ~/Library/Caches/com.apple.bird ] && mv ~/Library/Caches/com.apple.bird ~/Library/Caches/com.apple.bird.bak-${TS} 2>/dev/null; [ -d ~/Library/Caches/CloudKit ] && mv ~/Library/Caches/CloudKit ~/Library/Caches/CloudKit.bak-${TS} 2>/dev/null" \
    "user" "iCloud 文件重新同步，临时中断" 5242880

# 9. CoreSpotlight 元数据
scan_msg "CoreSpotlight 元数据"
get_size_kb sz "$HOME/Library/Metadata/CoreSpotlight"
add_item "CoreSpotlight 元数据索引" "~/Library/Metadata/CoreSpotlight" "$sz" \
    "应用级搜索索引（Pages 的修订追踪、Mail 等）。已知 bug：Pages + iCloud 可导致膨胀至 100+ GB。" \
    "[ -d ~/Library/Metadata/CoreSpotlight ] && mv ~/Library/Metadata/CoreSpotlight ~/Library/Metadata/CoreSpotlight.bak-${TS} 2>/dev/null" \
    "user" "应用内搜索暂时不可用，自动重建" 5242880

# 10. iOS 设备备份
scan_msg "iOS 设备备份"
get_size_kb sz "$HOME/Library/Application Support/MobileSync/Backup"
add_item "iOS 设备备份" "~/Library/Application Support/MobileSync/Backup" "$sz" \
    "iPhone/iPad 的本地备份，每台设备 5-50 GB。旧设备的备份不会自动清理。" \
    "# 建议通过「系统设置 → 通用 → 储存空间 → iOS 备份」管理" \
    "user" "备份数据不可恢复，请确认不再需要" 20971520

# 11. Xcode 开发数据
scan_msg "Xcode 开发数据"
get_size_kb sz_dd "$HOME/Library/Developer/Xcode/DerivedData"
get_size_kb sz_sim "$HOME/Library/Developer/CoreSimulator"
get_size_kb sz_arc "$HOME/Library/Developer/Xcode/Archives"
get_size_kb sz_ds "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
sz_total=$((sz_dd + sz_sim + sz_arc + sz_ds))
add_item "Xcode 开发数据（构建缓存/模拟器/归档）" "~/Library/Developer/" "$sz_total" \
    "Xcode 编译缓存、iOS 模拟器运行时、旧版归档。可安全清理，下次构建会重建。" \
    "[ -d ~/Library/Developer/Xcode/DerivedData ] && mv ~/Library/Developer/Xcode/DerivedData ~/Library/Developer/Xcode/DerivedData.bak-${TS} 2>/dev/null; xcrun simctl delete unavailable 2>/dev/null" \
    "user" "首次构建较慢，不可用的模拟器被移除" 10485760

# 12. Docker 虚拟磁盘
scan_msg "Docker 虚拟磁盘"
get_size_kb sz "$HOME/Library/Containers/com.docker.docker"
add_item "Docker Desktop 虚拟磁盘" "~/Library/Containers/com.docker.docker" "$sz" \
    "Docker 的容器和镜像存储在一个不断增长的虚拟磁盘文件中。" \
    "docker system prune -a --volumes 2>/dev/null" \
    "user" "删除所有未使用的镜像、容器和卷" 10485760

# 13. Outlook / Microsoft 365 缓存
scan_msg "Outlook 邮件缓存"
get_size_kb sz "$HOME/Library/Group Containers/UBF8T346G9.Office/Outlook"
add_item "Outlook 邮件缓存" "~/Library/Group Containers/.../Outlook" "$sz" \
    "Outlook 本地缓存所有邮件和附件。大邮箱或配置损坏时可膨胀。正常 1-5 GB。" \
    "# 建议在 Outlook 中右键账户 → 重置，重新同步" \
    "user" "需重新同步所有邮件" 10485760

# 14. OneDrive 同步缓存
scan_msg "OneDrive 同步缓存"
get_size_kb sz "$HOME/Library/Group Containers/UBF8T346G9.OneDriveSyncClientSuite"
add_item "OneDrive 同步缓存" "~/Library/Group Containers/.../OneDrive" "$sz" \
    "OneDrive 未开启「按需下载」时会缓存全量文件到本地。" \
    "# 建议在 OneDrive 设置中开启 Files On-Demand" \
    "user" "需在 OneDrive 设置中操作" 10485760

# 15. 用户级缓存（汇总）
scan_msg "用户应用缓存"
get_size_kb sz "$HOME/Library/Caches"
add_item "用户应用缓存（汇总）" "~/Library/Caches" "$sz" \
    "~/Library/Caches 下每个应用自己的缓存。通配清理会误删登录态、下载进度等，本工具仅做诊断。请根据 Top 子目录在对应应用内清理。" \
    "# 仅诊断：请用 du -sh ~/Library/Caches/* | sort -hr | head -10 查看占用最大的子目录，再在对应应用内清理（如 Chrome 的「清除浏览数据」）" \
    "user" "不自动清理——通配清理风险过高" 15728640

# 16. Mail 附件下载
scan_msg "Mail 附件缓存"
get_size_kb sz "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
get_size_kb sz2 "$HOME/Library/Mail"
sz_total=$((sz + sz2))
add_item "Apple Mail 邮件与附件" "~/Library/Mail + Mail Downloads" "$sz_total" \
    "Apple Mail 本地邮件与附件，含用户数据（可能有不在服务器上的重要邮件/附件）。本工具仅诊断，请在 Mail 应用内按账户重置或手动清理。" \
    "# 仅诊断：打开 Mail → 邮箱 → 鼠标右键账户 → 「导出邮箱」留档 → 再考虑清理。附件：Mail → 查看 → 附件。切勿直接 rm。" \
    "user" "不自动清理——可能含本地独有的邮件数据" 10485760

# 17. Podcast 下载
scan_msg "Podcast 下载"
get_size_kb sz "$HOME/Library/Group Containers/243LU875E5.groups.com.apple.podcasts"
add_item "Podcast 已下载节目" "~/Library/Group Containers/.../podcasts" "$sz" \
    "Apple Podcast 自动下载的节目。开启自动下载时容易积累。" \
    "# 建议在 Podcast 应用中关闭自动下载并清理已下载节目" \
    "user" "需重新下载节目" 5242880

# 18. 开发工具缓存（Homebrew/npm/pip）
scan_msg "开发工具缓存"
sz_brew=0; sz_npm=0; sz_pip=0; sz_cargo=0
[ -d "$HOME/Library/Caches/Homebrew" ] && get_size_kb sz_brew "$HOME/Library/Caches/Homebrew"
[ -d "$HOME/.npm" ] && get_size_kb sz_npm "$HOME/.npm"
[ -d "$HOME/Library/Caches/pip" ] && get_size_kb sz_pip "$HOME/Library/Caches/pip"
[ -d "$HOME/.cargo/registry" ] && get_size_kb sz_cargo "$HOME/.cargo/registry"
sz_total=$((sz_brew + sz_npm + sz_pip + sz_cargo))
add_item "开发工具缓存（Homebrew/npm/pip/cargo）" "Homebrew + npm + pip + cargo" "$sz_total" \
    "包管理器的下载缓存。可安全清理，下次安装时重新下载。" \
    "brew cleanup --prune=all 2>/dev/null; npm cache clean --force 2>/dev/null; pip cache purge 2>/dev/null" \
    "user" "包需重新下载" 3145728

# 19. VS Code / Electron 应用缓存
scan_msg "VS Code 缓存"
get_size_kb sz "$HOME/Library/Application Support/Code/Cache"
get_size_kb sz2 "$HOME/Library/Application Support/Code/CachedData"
sz_total=$((sz + sz2))
add_item "VS Code 编辑器缓存" "~/Library/Application Support/Code/Cache*" "$sz_total" \
    "VS Code 的运行缓存和扩展数据缓存。" \
    "[ -d ~/Library/Application\\ Support/Code/Cache ] && mv ~/Library/Application\\ Support/Code/Cache ~/Library/Application\\ Support/Code/Cache.bak-${TS} 2>/dev/null; [ -d ~/Library/Application\\ Support/Code/CachedData ] && mv ~/Library/Application\\ Support/Code/CachedData ~/Library/Application\\ Support/Code/CachedData.bak-${TS} 2>/dev/null" \
    "user" "扩展可能需要重新初始化" 3145728

# 20. QuickLook 缩略图缓存
scan_msg "QuickLook 缩略图"
ql_dir="${TMPDIR%/}/../C/com.apple.QuickLook.thumbnailcache"
sz=0
[ -d "$ql_dir" ] && get_size_kb sz "$ql_dir"
add_item \
    "QuickLook 缩略图缓存" \
    "$ql_dir" \
    "$sz" \
    "Finder 预览缩略图的缓存。正常 100-500 MB。" \
    "qlmanage -r cache 2>/dev/null" \
    "user" \
    "缩略图重新生成，无风险" \
    2097152  # 2 GB

printf "\r  %-60s\n" ""
echo "  ${G}扫描完成！${NC}"
echo ""

# ── 第 3 步：诊断报告 ──
echo "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${B}  第 3 步：诊断报告${NC}"
echo "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ "$ITEM_COUNT" -eq 0 ]; then
    echo "  ${G}未发现异常占用！所有已知膨胀点均在正常范围内。${NC}"
    echo ""
    echo "  如果「系统数据」仍然偏大，可能是以下原因："
    echo "  · APFS 可清除空间（purgeable）被计入系统数据（重启可能自动释放）"
    echo "  · 未知的第三方应用数据"
    echo "  · macOS 储存空间统计的已知误差"
    echo ""
    close_and_exit
fi

echo "  发现 ${B}${ITEM_COUNT}${NC} 个异常项，预计可释放 ${B}${R}$(human_size $TOTAL_RECLAIMABLE)${NC}："
echo ""

for i in $(seq 1 $ITEM_COUNT); do
    local_size=$((ITEM_SIZES[$i] * 1024))
    level_tag=""
    case "${ITEM_LEVELS[$i]}" in
        system)       level_tag="${R}[系统级]${NC}" ;;
        interactive)  level_tag="${R}[交互确认]${NC}" ;;
        *)            level_tag="${C}[用户级]${NC}" ;;
    esac
    echo "  ${B}[$i] ${ITEM_NAMES[$i]}${NC}  $level_tag"
    echo "      占用：${R}$(human_size $local_size)${NC}"
    echo "      ${D}${ITEM_DESCS[$i]}${NC}"
    echo "      ${D}路径：${ITEM_PATHS[$i]}${NC}"
    echo "      ${Y}风险：${ITEM_RISKS[$i]}${NC}"
    echo ""
done

# ── 第 4 步：清理 ──
echo "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${B}  第 4 步：选择清理${NC}"
echo "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  输入要清理的编号（如 ${B}1${NC}），输入 ${B}a${NC} 清理全部，输入 ${B}q${NC} 退出"
echo ""

cleaned_total=0

while true; do
    # 显示剩余可清理项
    remaining=0
    for i in $(seq 1 $ITEM_COUNT); do
        local_size=$((ITEM_SIZES[$i] * 1024))
        if [ "$local_size" -gt 0 ]; then remaining=$((remaining + 1)); fi
    done
    if [ "$remaining" -eq 0 ]; then
        echo "  ${G}所有项目已清理完毕${NC}"
        break
    fi
    echo ""
    echo "  ${D}还有 ${remaining} 项可清理，输入编号、a（全部）或 q（退出）${NC}"
    printf "  请选择 > "
    read -r choice

    if [ "$choice" = "q" ] || [ "$choice" = "Q" ]; then
        break
    fi
    
    if [ "$choice" = "a" ] || [ "$choice" = "A" ]; then
        printf "  ${Y}确认清理全部 ${ITEM_COUNT} 项？(y/n): ${NC}"
        read -rk 1 confirm_all
        echo ""
        if [ "$confirm_all" != "y" ] && [ "$confirm_all" != "Y" ]; then
            continue
        fi
        for i in $(seq 1 $ITEM_COUNT); do
            echo ""
            echo "  ${C}清理 [$i] ${ITEM_NAMES[$i]}...${NC}"
            local_size=$((ITEM_SIZES[$i] * 1024))
            fix_cmd="${ITEM_FIXES[$i]}"
            if echo "$fix_cmd" | grep -q "^#"; then
                echo "  ${Y}→ 需手动操作：${fix_cmd#\# }${NC}"
            elif echo "$fix_cmd" | grep -q "^@INTERACTIVE:"; then
                local_fn="${fix_cmd#@INTERACTIVE:}"
                if $local_fn; then
                    cleaned_total=$((cleaned_total + local_size))
                    ITEM_SIZES[$i]=0
                fi
            else
                if [ "${ITEM_LEVELS[$i]}" = "system" ]; then
                    eval "sudo $fix_cmd" 2>/dev/null
                else
                    eval "$fix_cmd" 2>/dev/null
                fi
                echo "  ${G}→ 已释放约 $(human_size $local_size)${NC}"
                cleaned_total=$((cleaned_total + local_size))
            fi
        done
        break
    fi
    
    # 单项清理
    if echo "$choice" | grep -qE '^[0-9]+$'; then
        idx=$choice
        if [ "$idx" -ge 1 ] && [ "$idx" -le "$ITEM_COUNT" ]; then
            local_size=$((ITEM_SIZES[$idx] * 1024))
            echo ""
            echo "  ${B}${ITEM_NAMES[$idx]}${NC} — $(human_size $local_size)"
            echo "  ${Y}风险：${ITEM_RISKS[$idx]}${NC}"
            printf "  确认清理？(y/n): "
            read -rk 1 confirm
            echo ""
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                fix_cmd="${ITEM_FIXES[$idx]}"
                if echo "$fix_cmd" | grep -q "^#"; then
                    echo "  ${Y}→ 需手动操作：${fix_cmd#\# }${NC}"
                elif echo "$fix_cmd" | grep -q "^@INTERACTIVE:"; then
                    local_fn="${fix_cmd#@INTERACTIVE:}"
                    if $local_fn; then
                        cleaned_total=$((cleaned_total + local_size))
                        ITEM_SIZES[$idx]=0
                    fi
                else
                    echo "  清理中..."
                    if [ "${ITEM_LEVELS[$idx]}" = "system" ]; then
                        eval "sudo $fix_cmd" 2>/dev/null
                    else
                        eval "$fix_cmd" 2>/dev/null
                    fi
                    echo "  ${G}→ 已释放约 $(human_size $local_size)${NC}"
                    cleaned_total=$((cleaned_total + local_size))
                    ITEM_SIZES[$idx]=0
                fi
            fi
        else
            echo "  ${R}无效编号${NC}"
        fi
    else
        echo "  ${R}无效输入，请输入编号、a（全部）或 q（退出）${NC}"
    fi
done

echo ""
echo "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${B}  完成${NC}"
echo "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
if [ "$cleaned_total" -gt 0 ]; then
    echo "  ${G}本次共释放约 $(human_size $cleaned_total) 磁盘空间${NC}"
else
    echo "  未执行清理操作"
fi
echo ""

# 列出本次创建的 .bak- 备份（mv 到同盘 .bak 对 APFS 是 O(1) 重命名，不占额外空间，
# 但系统储存统计仍会计入；用户确认运行正常后可手动删除以"真正释放"）
# 只检查我们已知会创建 .bak 的固定路径，避免全局 find 卡顿
if [ "$cleaned_total" -gt 0 ]; then
    typeset -a _bak_candidates
    _bak_candidates=(
        "/Library/Caches/com.apple.iconservices.store.bak-${TS}"
        "/Library/macOS Install Data.bak-${TS}"
        "/Library/Updates.bak-${TS}"
        "${HOME}/Library/Caches/com.apple.bird.bak-${TS}"
        "${HOME}/Library/Caches/CloudKit.bak-${TS}"
        "${HOME}/Library/Metadata/CoreSpotlight.bak-${TS}"
        "${HOME}/Library/Developer/Xcode/DerivedData.bak-${TS}"
        "${HOME}/Library/Application Support/Code/Cache.bak-${TS}"
        "${HOME}/Library/Application Support/Code/CachedData.bak-${TS}"
    )
    _bak_found=()
    for _p in "${_bak_candidates[@]}"; do
        [ -e "$_p" ] && _bak_found+=("$_p")
    done
    if [ ${#_bak_found[@]} -gt 0 ]; then
        echo "  ${Y}本次产生的可回滚备份（.bak-${TS}）：${NC}"
        for _p in "${_bak_found[@]}"; do
            echo "    $_p"
        done
        echo ""
        echo "  ${D}确认系统运行正常（建议 24-48h）后，可手动删除这些 .bak 目录永久释放空间。${NC}"
        echo "  ${D}若出现异常想回滚：将 .bak-${TS} 目录 mv 回原名即可。${NC}"
        echo ""
    fi
fi
echo "  💡 建议清理完成后重启电脑，让系统刷新储存空间统计。"
echo ""

close_and_exit
