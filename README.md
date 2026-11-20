# macOS Sandbox App → External Drive / macOS 沙盒应用数据迁移到外置硬盘

**PlayCover 原神/绝区零软链接黑屏解决 · HFS+ 稀疏映像真挂载方案**
**Fix PlayCover Genshin Impact symlink black screen via HFS+ sparse bundle mount**

把沙盒 App 的几十 GB 数据搬到外置硬盘、释放内置盘空间。
**中文**：软链接（`ln -s`）在 macOS 沙盒内会导致启动黑屏；唯一稳定可靠的做法是建 HFS+ 稀疏磁盘映像，用 `hdiutil attach -mountpoint` 真挂载到容器内的数据子目录。存档留在本地，**无需 root、无需关闭 SIP、无需完全磁盘访问**。
**EN**: Symlinks fail inside the macOS sandbox (black screen on launch). This project mounts an HFS+ sparse bundle into the app's container data subdirectory with `hdiutil attach -mountpoint` — no root, no SIP disable, no Full Disk Access.

**关键词 / Keywords**：`macOS 沙盒应用迁移` `PlayCover 原神外置硬盘` `原神软链接黑屏` `macOS 内置盘爆满` `外置硬盘 游戏数据` `sandbox symlink black screen` `Genshin Impact external drive` `HFS+ sparsebundle mount` `mount_apfs Operation not permitted` `PlayCover game data migration`

## 核心结论 / TL;DR

| 方案 / Approach | 结果 / Result |
| --- | --- |
| `ln -s` 容器子目录 → 外置盘 | ❌ 启动黑屏（窗口截图仅 29KB 纯色），无崩溃日志；A/B 对照实测证伪 |
| `mount_apfs` 挂 APFS 卷 | ❌ 无免密 sudo 报 `Operation not permitted`；关 SIP 又会导致 iOS App 不可用 |
| **HFS+ sparsebundle + `hdiutil attach -mountpoint`** | ✅ 画面正常，`lsof` 证实游戏读取外置 `AssetBundles/*.blk` 资源 |

**方法论 / Method**：容器根保持真实目录；只挂载内层数据大头（原神为 `Data/Library/MihoyoDownload`，约 31G），存档 `Documents` 留本机。非空挂载点会遮蔽原内容、卸载即完整恢复，因此可零风险 A/B 测试。
**Method**: keep the container root real; mount only the inner data-heavy subdirectory; saves stay local. Non-empty mountpoints are shadowed and fully restored on detach — enabling zero-risk A/B testing.

## 为什么 / Why

**中文**：PlayCover 安装的 iOS 游戏把资源包放在沙盒容器里，原神/绝区零单个游戏可达 30G+。网传的 `ln -s` 软链方案看似能腾空间，但 macOS 沙盒 App 在启动阶段会校验容器内路径，指向 `/Volumes` 的符号链接校验失败 → 黑屏、不崩溃、进程还在，极难排查。官方讨论明确这是安全模型设计：若允许软链读任意路径将是严重漏洞。正解是**挂载而非软链**。

**EN**: PlayCover games store asset bundles inside sandbox containers (30G+ each). The popular `ln -s` trick seems to free space, but sandboxed apps validate container paths at launch; a symlink pointing to `/Volumes` fails validation → black screen, no crash log, process alive. Maintainers confirm this is by security design. The fix is **mounting, not symlinking**.

## 适用场景 / Use Cases

- PlayCover 版原神、绝区零、崩铁等 iOS 游戏数据迁外置盘 / Move PlayCover iOS game data to an external disk
- 任何沙盒 App 的大体积数据子目录外迁（容器根不可软链）/ Any sandboxed app with a large data subdirectory
- 内置盘爆满但外置盘是 exFAT、不想重格 / Internal disk full, external disk is exFAT and you don't want to reformat

## 快速开始 / Quick Start

前置：替换 `scripts/*.sh` 中所有 `***占位符***`。核心步骤（详见 `SKILL.md`）：

```bash
# 0. 只读取证：找真正的大头，确认外置盘空间与格式、无进程占用
du -sh "$HOME/Library/Containers/<bundle-id>/Data/Library/"* | sort -h | tail
df -h /Volumes/<external> && diskutil info /Volumes/<external> | grep -i "File System Personality"

# 1. 备份大头目录到外置盘（排除 exFAT 的 ._ 元数据）
rsync -a --exclude='._*' "<source-dir>/" "<backup-dir>/"

# 2. 最小可行性探针：100M HFS+ 映像挂到非空目录，验证可挂载 + 卸载后数据完整恢复
hdiutil create -size 100m -type SPARSEBUNDLE -fs HFS+ -volname Probe "/Volumes/<external>/probe.sparsebundle"
hdiutil attach -mountpoint "$HOME/Library/Containers/<bundle-id>/<data-subdir>" "/Volumes/<external>/probe.sparsebundle"
hdiutil detach "$HOME/Library/Containers/<bundle-id>/<data-subdir>"

# 3. 建正式映像 → 灌数据 → 挂载到容器子目录
hdiutil create -size 60g -type SPARSEBUNDLE -fs HFS+ -volname AppData "/Volumes/<external>/AppDataHFS.sparsebundle"
hdiutil attach -nobrowse -mountpoint /tmp/stage "/Volumes/<external>/AppDataHFS.sparsebundle"
rsync -a --exclude='._*' "<backup-dir>/" /tmp/stage/ && hdiutil detach /tmp/stage
hdiutil attach -nobrowse -mountpoint "$HOME/Library/Containers/<bundle-id>/<data-subdir>" "/Volumes/<external>/AppDataHFS.sparsebundle"
```

重启或拔插外置盘后只需重挂：`scripts/mount_external.sh`。To remount after reboot: run `scripts/mount_external.sh`.

## 验收判据 / Verification Checklist

六条缺一不可（Six checks, all required）：

| # | 判据 / Check | 命令 / Evidence | 通过 / Pass |
| --- | --- | --- | --- |
| 1 | 挂载生效 / mounted | `mount \| grep <target>` | hfs 记录 / hfs entry |
| 2 | 穿透可读 / readable | `du -sh <target>` + `find <target> -type f \| wc -l` | 大小、文件数一致 / matches source |
| 3 | 画面正常 / non-black screen | `screencapture -x -o -l <window-id>` | 截图远大于 30KB / screenshot ≫ 30KB |
| 4 | **资源真被读取 / assets really read** | `lsof -p <pid> \| grep <target>` | 出现 `*.blk` 句柄 / `*.blk` handles |
| 5 | 无崩溃 / no crash | `ls ~/Library/Logs/DiagnosticReports \| grep -i <app>` | 无新增 / none |
| 6 | 可回滚 / reversible | `hdiutil detach <target>` 后 `du -sh <target>` | 原数据恢复 / restored |

进程存活 + 截图正常 = 必要但不充分，必须到第 4 条。Process alive + normal screenshot is necessary but not sufficient — check #4.

## 踩坑实录 / Failure Catalog

| # | 坑 / Pitfall | 规避 / Avoidance |
| --- | --- | --- |
| F1 | 软链黑屏 / symlink → black screen | 禁用软链，A/B 对照 + lsof 判据 / no symlink; A/B + lsof |
| F2 | APFS 挂载需 root / APFS mount needs root | 先用 `sudo -n true` 探测，无 root 改 HFS+ / probe sudo, use HFS+ |
| F3 | `rm -rf` 静默失效（TCC 保护）/ silent delete failure | 删后必复核，交用户手删 / verify after delete; ask user |
| F4 | 废纸篓项自动加时间戳导致误判 / trash auto-renames | `ls -lat ~/.Trash \| grep -i <kw>` 全量列 / list all matches |
| F5 | 跨盘 `mv` 报 EXDEV | 用 `cp -a` / `rsync -a` |
| F6 | exFAT `._*` AppleDouble 使文件数翻倍 | 校验加 `--exclude='._*'` |

四要素完整复盘见 `references/failure-catalog.md`。Full 4-element postmortems: `references/failure-catalog.md`.

## 目录结构 / Structure

```
SKILL.md                       决策树 + 铁律 + 4 阶段流程 + 6 项判据
references/probe-and-verify.md  探针、窗口取证、lsof 判据的可复制命令
references/failure-catalog.md   6 条失败的四要素复盘
references/sources.md           官方讨论 / 视频 / 文章原文与链接
scripts/migrate_to_external.sh  迁移流程骨架（占位符版）
scripts/mount_external.sh       重启后重新挂载模板
```

## 来源 / Sources

- PlayCover 官方 #473（为何软链不行）：https://github.com/PlayCover/PlayCover/discussions/473
- PlayCover 官方 #1712（挂载迁移教程）：https://github.com/PlayCover/PlayCover/discussions/1712
- B 站实测视频：https://www.bilibili.com/video/BV1i4mKYiEtt/
- 软链 vs 挂载独立佐证：https://www.panwenbin.com/mac-softwares/运行ios-app
- exFAT 上建映像挂到数据目录：https://egeek.me/2025/01/05/snapshots-for-ios-backups
- 现成自动挂载工具：https://github.com/PhiLiaO93/auto-mount-Playcover

## License

MIT — 见 `LICENSE`。
