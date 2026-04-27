# macSystemCleaner

> macOS System Data bloat targeted diagnostic tool. "系统数据"异常占用的靶向诊断与清理工具

## 这个工具是怎么来的

某天我的 Mac 1TB 硬盘只剩不到 1 GB，打开「系统设置 → 储存空间」一看，**「系统数据」占了 576 GB**。

试了市面上一圈清理工具，它们声称"帮你清理 XX GB"，大多是告诉我"你下载文件夹很大"。谢谢，我自己也看得到。

后来我用 `sudo du` 一层层手动排查，最后定位到罪魁祸首：

```
/Library/Caches/com.apple.iconservices.store  →  502 GB
```

这是 macOS 的图标缓存数据库。正常应该 < 100 MB，但 **macOS 有个已知 bug**：在频繁挂载外部存储（SD 卡、NAS、移动硬盘、相机）时，这个数据库会损坏并开始无限膨胀。

我刚好是个经常插相机 SD 卡 + 运动相机 + NAS 的视频工作流用户，完美踩雷。

清掉之后，系统数据从 576 GB 降回 30 GB。

**这个脚本是我把定位过程里踩过的所有已知膨胀点整理出来，让下一个遇到类似问题的人不用从零排查。**

---

## 为什么现有的清理工具都找不到？

不是它们不努力，是 macOS 有三层限制，它们绕不过去：

### 第一层：需要 root 权限的系统目录

`/Library/Caches/` 下不少子目录是 `root:wheel` 所有，权限 `0700`。普通用户（包括 Finder）读不进去 —— 你在 Finder 里右键点 `com.apple.iconservices.store` 看"显示简介"，会看到 **0 KB**。

那不是它真的是空的，是 Finder 没权限。大部分清理工具跑在 App Store 的沙盒里，比 Finder 还受限，连门都摸不到。

本工具用 `sudo` 直接读，所以能看到真实的几百 GB。

### 第二层：沙盒应用数据（`~/Library/Containers`）

现代 App 的数据大头都在这里：微信的聊天记录、飞书的 workspace、Docker 的虚拟磁盘、Lightroom 的目录库、Xcode 的 iOS 模拟器运行时……

这一层不是权限问题，是**没人敢动**。

第三方清理工具最多只敢清每个 App `Data/Library/Caches/` 里的浅层缓存，那通常占不到大头的 20%。真正的 GB 级数据是用户的东西，删错一次就是"聊天记录不见了"这种级别的事故。

**本工具面对这层也不碰**，但会做两件事：
- 列出 Top 10 子目录，把文件夹名翻译成中文应用名（覆盖微信/飞书/钉钉/Lightroom/VS Code/Docker/Xcode 等 100+ 条映射）
- 告诉你每个 App 自己的清理入口在哪（"微信 → 设置 → 通用 → 清理缓存"这种）

### 第三层：系统级操作应该用官方命令

Spotlight 索引、Time Machine 快照、系统日志、Homebrew/npm/pip 缓存、Docker 镜像 —— 这些都有 Apple 或工具方自己提供的官方命令。盲目 `rm -rf` 会导致句柄不同步、元数据错乱、索引损坏。

本工具能用官方命令的就用官方命令：`mdutil -E` / `log erase` / `tmutil deletelocalsnapshots` / `brew cleanup` / `npm cache clean` / `pip cache purge` / `qlmanage -r cache` / `softwareupdate --clear-catalog` / `xcrun simctl delete unavailable` / `docker system prune`。

---

## 和其他清理工具是什么关系

Mac 上常见的清理 / 磁盘分析工具各自解决不同问题。基于各家官网描述 + 公开社区评测整理：

| 工具 | 主要能力 | 最适合的场景 |
|---|---|---|
| CleanMyMac | GUI 原生风格；综合磁盘清理 + 应用卸载 + 系统维护；付费订阅 | 想用一个 App 打包解决"Mac 越用越慢"的日常保养 |
| Mole | 免费开源命令行（`brew install mole`）；综合缓存清理 + 深度卸载 | 开发者想清 Xcode / Node.js / Docker / brew 等堆积 |
| OmniDiskSweeper | 免费；按大小排序的列视图，下钻浏览 | 快速定位"哪个具体的大文件 / 大目录"占掉了空间 |
| GrandPerspective | 免费开源；树状图（treemap）磁盘占用可视化 | 希望用视觉方式一眼看清楚磁盘被谁吃掉了 |
| Sensei | GUI；硬件监控（SSD / 电池 / CPU / GPU）+ 清理；付费 | 想在一个界面里同时关注硬件健康和磁盘占用 |
| **本工具** | 针对 macOS 本身已知 bug 的定点靶向诊断（20+ 具体路径 + 合成诊断信号） | 「系统数据」格子异常偏大、上面这些工具都找不出原因的时候 |

上面每一个都能解决它对应的问题。本工具做的是一个**很窄的切口**：针对 Apple 官方未修的系统级 bug（图标缓存数据库、Handoff 剪贴板存档、mediaanalysisd 反复重索引 等）做定点排查。这类路径要么在 SIP / root-owned 系统目录、要么在 App 沙盒内——各家工具侧重不同，场景不冲突。

## 这个工具故意不做的事

这是一个脚本工具，不是产品。以下事情**主动不做**，不是暂时没实现：

- **不做综合扫描和评分**：不会把"你有 47 GB 垃圾"这种泛化指标当结果。每一项都定位到具体路径 + 占用 + 清理后可能的影响，你自己判断清不清
- **不做 GUI**：保持 `.command` 双击即跑 + 纯 zsh 零依赖
- **不做 brew 分发 / Mac App Store 分发**：一个 `.command` 文件双击就能跑，没必要走包管理；MAS 沙盒会让工具失去访问系统级目录的能力
- **不做自动化闭眼清理**：每一项都要你确认。`~/Library/Containers` 和 `~/Library/Application Support` 下的数据（微信聊天记录、Obsidian 笔记、Lightroom 照片库等）**永远不自动清**，只展开明细让你自己决定
- **不做商业化**：免费 MIT 开源，没有 Pro 版，没有订阅

---

## 怎么用

### 下载（推荐方式）

**最简单：从 [Releases](https://github.com/Raven940309/macSystemCleaner/releases/latest) 下载最新 DMG**

1. 打开 [Releases 页面](https://github.com/Raven940309/macSystemCleaner/releases/latest)，下载 `macSystemCleaner-x.y.dmg`
2. 双击 DMG 挂载 → 进入「macSystemCleaner」磁盘
3. 里面有两个中文命名的命令文件，**直接双击即可运行** —— 零终端、零 chmod

DMG 内部是 APFS 文件系统，执行位完整保留，最适合日常使用。

### 下载（给开发者的选项）

想看源码或自己改？`git clone` 保留执行位：

```bash
git clone https://github.com/Raven940309/macSystemCleaner.git
cd macSystemCleaner
```

⚠️ **不推荐 GitHub 网页 "Download ZIP"**：macOS 解压后文件会丢执行位，双击会报"没有正确的访问权限"。如果已经下了 ZIP，需要在终端跑一次 `chmod +x *.command` 才能双击；或改用 `zsh 脚本名` 这种不依赖执行位的跑法。

### 第一步：先诊断（强烈建议）

**用 DMG**：双击 `1-系统数据诊断.command`
**用 clone**：`zsh verify_all.command`

这个脚本**只看不动**。跑完会给你：

- 28 项已知膨胀点的扫描结果
- `~/Library/Containers` / `Application Support` / `Group Containers` 的 Top 10 应用占用（中文名）
- **结尾一段「系统数据异常占用分析」**：只列真正异常的项，每项告诉你是什么、为什么大、你自己手动清怎么做

**我的建议：大多数人跑完这个就够了**。看完知道问题在哪，在对应 App 里自己清最稳。

### 第二步：交互清理（可选）

**用 DMG**：双击 `2-系统数据清理.command`
**用 clone**：`zsh MacSystemCleaner.command`

逐项 `y/n` 确认，每一步显示：大小、原因、风险、清理后果。

对不同风险的项处理方式不一样：

- **图标缓存**（可能几百 GB，无官方回滚）：工具会先打开 Finder 让你肉眼核对，再要求你输入 `DELETE`（全大写）二次确认才删
- **小项**（iCloud / CoreSpotlight / Xcode DerivedData / macOS 更新 / VS Code 缓存）：用 `mv` 重命名成 `.bak-<时间戳>`（APFS 同卷 O(1) 操作，零成本），出问题可以重命名回去
- **系统项**（Spotlight / 日志 / TM 快照 / brew / npm / pip 等）：全走官方命令
- **用户数据类**（Mail / iOS 备份 / Outlook / Podcast / Containers 里的一切）：**一律只诊断，不碰**

清理结束后工具会列出所有 `.bak-<时间戳>` 路径。24-48 小时确认系统运行正常后，你再手动 `rm` 就真正释放了空间。

---

## 覆盖清单

**28 项扫描**：图标缓存 · Time Machine 快照 · APFS 快照 · Spotlight · 系统日志 · macOS 更新暂存 · GarageBand/Logic · iCloud Drive (bird) · iCloud Photos (cloudphotosd) · CloudKit 通用 · CoreSpotlight · iOS 备份 · Xcode 用户域 · Docker · Outlook · OneDrive · 用户应用缓存 · Mail · Podcast · 开发工具缓存（brew/npm/pip/cargo）· VS Code · QuickLook · Handoff 剪贴板存档 · asitop 功耗日志 · **mediaanalysisd（Sequoia 15.1 bug）** · **Biome 行为数据库** · **Xcode Simulator Runtime（系统域）** · **Adobe Media Cache**

**2 项合成信号**：`~/Library/Containers` > 50 GB 或 `~/Library/Application Support` > 30 GB 时触发，给分 App 处理指引。

---

## 说点实在的

**它可能帮不到你**。我朋友的 Mac 跑完，诊断结果是图标缓存才 40 MB，完全正常 —— 他的「系统数据」偏大不是本工具能解决的场景。

**如果诊断跑完说一切正常**，你的「系统数据」偏大大概率是 APFS 的可清除空间（purgeable），**重启一次**通常会重新统计。

**我不是专业 macOS 开发者**。脚本是我解决自己问题后整理出来的。所有涉及 `sudo` 和删除的命令都来自 Apple 或对应工具方的官方文档，没有偏门黑魔法。代码不长，**建议你跑之前自己读一遍**。

---

## 安全边界

- ✅ **已验证**：图标缓存清理（我自己从 502 GB → 30 MB）、所有官方命令、QuickLook
- ⚠️ **官方命令但未实测**：Spotlight 重建、系统日志清除、TM 快照删除（用的是 Apple 官方 CLI，理论安全）
- ❓ **未实测**：iCloud / CoreSpotlight / Xcode / VS Code 等的 `mv .bak` 流程（原理上可回滚）

所有未验证的项，工具不会"批量一键清"，必须逐项确认。

---

## 免责

本工具按现状提供，作者不承担任何因使用本工具导致的数据丢失或系统异常的责任。

**建议操作顺序**：
1. 跑清理前做一次 Time Machine 备份
2. 先跑 `verify_all.command` 诊断
3. 确认问题后再考虑跑 `MacSystemCleaner.command`
4. 任何一步不确定，就输入 `n` 跳过

---

## 兼容性

- 开发环境：macOS Sequoia (26.4) / Apple Silicon
- 理论兼容：macOS Ventura (13) 及以上，Intel / Apple Silicon 通用
- 在其他环境遇到问题，欢迎提 Issue

## License

[MIT](LICENSE)
