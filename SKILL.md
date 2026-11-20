---
name: macos-sandbox-app-external-drive
description: 把 macOS 沙盒应用（尤其 PlayCover 版的原神/绝区零等 iOS 游戏）的大体积数据迁到外置硬盘以释放内置盘空间。当用户想把 PlayCover 游戏数据/沙盒容器移出内置盘、抱怨内置盘爆满、或询问外置盘软链接方案是否有效时使用。核心结论：沙盒内软链接会导致黑屏/崩溃，必须用 HFS+ 稀疏映像真挂载到容器内的数据子目录。
agent_created: true
---

# macOS 沙盒应用数据迁外置盘

## Overview

把 macOS 沙盒 App（PlayCover 游戏为典型）的大体积数据从内置盘迁到外置盘，同时保持 App 正常启动、存档不丢。经实战验证的唯一可靠路径是：**在外置盘建 HFS+ 稀疏磁盘映像，用 `hdiutil attach -mountpoint` 真挂载到容器内的数据子目录**；软链接（`ln -s`）方案在沙盒内会导致黑屏，禁止作为主方案。

## 核心决策树

```
用户要把游戏/App 数据移到外置盘？
├─ 先只读盘点：du 找真正的大头目录（常是资源包，不是 app 本体）
│   └─ PlayCover 例：~/Library/Containers/<bundle-id>/Data/Library/MihoyoDownload 31G
│      存档 Documents 仅几十 M，务必留在本地、不要迁
├─ 选目标粒度：只迁「内层数据子目录」，绝不软链容器根目录
├─ 选技术方案：
│   ├─ ✗ ln -s 软链 → 沙盒启动期校验失败 → 黑屏（已 A/B 实测证伪）
│   ├─ ✗ mount_apfs → 需 root，无免密 sudo 时 Operation not permitted
│   └─ ✓ HFS+ sparsebundle + hdiutil attach -mountpoint（本文主方案）
└─ 迁移后必须验证「资源真被读取」，不能只看进程存活
```

## 铁律（违反即失败）

1. **软链必败**：macOS 沙盒 App 对容器内指向 `/Volumes` 的符号链接在启动阶段校验失败，表现为黑屏（无崩溃日志、进程可能在）。官方 #473 明确这是安全模型设计：*"If it was really possible, it would be a serious security flaw"*。不要因"文件系统层 ls/写入测试通过"就认为可用。
2. **HFS+ 而非 APFS**：若执行环境无免密 sudo，APFS 卷挂载（`mount_apfs` / `diskutil mount`）会因缺 root 失败；HFS+ 稀疏映像用 `hdiutil attach` 无需 sudo、无需关 SIP、无需完全磁盘访问。
3. **先探针后投入**：正式复制几十 G 之前，先用 100M 小映像挂到非空目标目录，验证"能挂载 + 卸载后原数据完整恢复"，再动真数据。
4. **验证要下到资源层**：判据必须包含 `lsof` 看到游戏进程打开外置资源文件（如 `*.blk`）。进程存活 + 截图正常 + 无崩溃 = 必要但不充分；只有在登录/加载阶段才真正读资源。
5. **exFAT 上的 `._*` 元数据**：从 exFAT 备份恢复时用 `rsync -a --exclude='._*'` 排除 AppleDouble 文件，否则文件数看似翻倍、校验误报。
6. **跨盘不用 mv**：`mv` 跨文件系统报 EXDEV，改用 `cp -a` 或 `rsync -a`。
7. **废纸篓删除不可靠**：沙盒容器内子目录移入废纸篓后，`rm -rf` 可能静默失效（返回 0 但不删）、Finder 报 -10004（TCC/containermanager 保护）。停止盲目重试，交用户手动删或先给终端完全磁盘访问。
8. **挂载点非空是特性不是 bug**：`hdiutil attach -mountpoint` 到非空目录时原内容被遮蔽、卸载后完整恢复——这是零风险 A/B 测试的基础。

## 标准工作流程

### 阶段 0：只读取证（动手前）

```bash
# 找真正的大头：容器占用 + 一级/二级目录排序
du -sh "$HOME"/Library/Containers/<bundle-id>
du -sh "$HOME"/Library/Containers/<bundle-id>/Data/Library/* 2>/dev/null | sort -h | tail
# 确认外置盘可用空间与格式
df -h /Volumes/<external>
diskutil info /Volumes/<external> | grep -i "File System Personality"
# 确认无相关进程
pgrep -fl "<app-keyword>"
```

向用户确认三件事再动手：① 哪些游戏/数据要迁（不玩的可直接清理）② 目标是"迁移后仍能玩"还是"只要腾空间"③ 是否接受每次重启后需重新挂载（或配套自动化脚本）。

### 阶段 1：备份 + 最小探针

```bash
# 备份大头目录到外置盘（排除 exFAT 元数据）
rsync -a --exclude='._*' "<source-dir>/" "<backup-dir>/"
# 校验：文件数一致 + rsync dry-run 差异为空
rsync -an --delete --exclude='._*' "<source-dir>/" "<backup-dir>/"
```

按 `references/probe-and-verify.md` 跑 100M 最小探针，确认 HFS+ 映像可挂载、可回滚。

### 阶段 2：建映像 + 灌数据 + 挂载

按 `scripts/migrate_to_external.sh` 的骨架执行（先替换占位符）。核心命令：

```bash
hdiutil create -size 60g -type SPARSEBUNDLE -fs HFS+ -volname <label> "<image-path>"
hdiutil attach -nobrowse -mountpoint /tmp/stage "<image-path>"
rsync -a --exclude='._*' "<backup-dir>/" /tmp/stage/
hdiutil detach /tmp/stage
hdiutil attach -nobrowse -mountpoint "<target-container-subdir>" "<image-path>"
```

### 阶段 3：验收（逐条判定，缺一不可）

| # | 判据 | 命令/证据 | 通过标准 |
|---|---|---|---|
| 1 | 挂载生效 | `mount \| grep <target>` | 出现 hfs 挂载记录 |
| 2 | 穿透可读 | `du -sh <target>` / `find <target> -type f \| wc -l` | 大小、文件数与源一致 |
| 3 | 画面正常 | `screencapture -x -o -l <window-id>` | 非纯黑（截图远大于 ~30KB），见启动/加载界面 |
| 4 | **资源真被读取** | `lsof -p <pid> \| grep <target>` | 出现 `AssetBundles/*.blk` 等资源文件句柄 |
| 5 | 无崩溃 | `ls ~/Library/Logs/DiagnosticReports \| grep -i <app>` | 无新增崩溃日志 |
| 6 | 可回滚 | `hdiutil detach <target>` 后 `du -sh <target>` | 原目录数据完整恢复 |

窗口 ID 获取用 `CGWindowListCopyWindowInfo`（swift），见 `references/probe-and-verify.md`。

### 阶段 4：释放本机空间（需用户显式确认）

删除是不可逆操作，必须先向用户展示"将删除路径 + 外置双保险仍在"并取得明确授权。流程：退出 App → 卸载映像 → 移走/删除本机原目录 → 重建空挂载点 → 重新挂载 → 再跑一遍阶段 3 验收。

每次重启或拔插外置盘后需重新挂载，可配套 `scripts/mount_external.sh`。

## 参考资料

- `references/probe-and-verify.md`：最小探针、窗口取证、lsof 判据的可复制命令与实战数据。
- `references/failure-catalog.md`：全部失败路径（软链黑屏、APFS 提权失败、TCC 删除静默失效、trash 重命名误判）的四要素复盘。
- `references/sources.md`：官方讨论、B 站视频、技术文章的原文关键段与链接（溯源用）。
- `scripts/migrate_to_external.sh`：迁移流程骨架（占位符版）。
- `scripts/mount_external.sh`：重启后重新挂载脚本模板。
