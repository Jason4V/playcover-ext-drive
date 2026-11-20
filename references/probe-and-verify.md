# 探针、取证与验收命令手册

本文件提供 SKILL.md 阶段 1/3 引用的可复制命令与实战判据数据。

## 1. 最小可行性探针（100M，零风险）

正式复制几十 G 前必须做。目的：证明目标环境能挂载、且卸载后原数据完整恢复。

```bash
IMG="/Volumes/<external>/probe.sparsebundle"       # 外置盘上的探针映像
TARGET="$HOME/Library/Containers/<bundle-id>/<data-subdir>"  # 真实目标目录（非空）

# 建 100M HFS+ 探针
hdiutil create -size 100m -type SPARSEBUNDLE -fs HFS+ -volname Probe "$IMG"

# 先挂到临时点，确认能挂
hdiutil attach -mountpoint /tmp/probe "$IMG"
df -h /tmp/probe
hdiutil detach /tmp/probe

# 关键测试：挂到非空目标目录（模拟真实场景）
BEFORE=$(find "$TARGET" -type f | wc -l)
hdiutil attach -mountpoint "$TARGET" "$IMG"   # 原内容被遮蔽，属预期
df -h "$TARGET"
hdiutil detach "$TARGET"
AFTER=$(find "$TARGET" -type f | wc -l)

[ "$BEFORE" -eq "$AFTER" ] && echo "探针通过：原数据完整恢复"
```

实战结果（2026-11-20）：100M HFS+ 映像挂到含 1299 文件的 31G 目录，`attach` 成功、`detach` 后 1299 文件原样恢复 → 才继续灌 31G 真数据。

## 2. APFS 与 HFS+ 的提权差异（为何选 HFS+）

先探测本机提权能力，不要照抄教程直接建 APFS：

```bash
sudo -n true 2>&1 && echo "有免密 sudo" || echo "无免密 sudo"
```

- 无免密 sudo 时：APFS sparsebundle 虽能 `hdiutil create` 且 `imageinfo`/`attach -nomount` 正常，但 `hdiutil attach` 报「无可装载的文件系统」、`diskutil mount /dev/diskNsM` 报 failed、`mount_apfs` 报 `Operation not permitted`。根因是 APFS 卷挂载需 root，非映像损坏、非格式兼容问题。
- HFS+ sparsebundle：`hdiutil attach -mountpoint` 普通用户即可，无需 sudo / 无需关 SIP / 无需完全磁盘访问。

## 3. 窗口取证（判断"真黑屏"还是遮挡/防截屏）

整屏截图可能被前台窗口遮挡，必须单独截目标窗口。先用 swift 拿窗口属性：

```bash
cat > /tmp/win_probe.swift <<'EOF'
import CoreGraphics
let wins = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in wins {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    if owner.lowercased().contains("<app-keyword>") {
        print(w[kCGWindowNumber as String] as? Int ?? 0,
              w[kCGWindowIsOnscreen as String] as? Bool ?? false)
    }
}
EOF
swift /tmp/win_probe.swift
# 输出：窗口ID onscreen布尔值 → 取 onscreen=true 的 ID
screencapture -x -o -l <窗口ID> /tmp/window.png
ls -la /tmp/window.png   # 看文件体积
```

实战判据：软链黑屏窗口截图仅 29KB（纯色）；正常启动画面 1.8MB+（有场景/文字）。体积差异是快速判别信号，仍应目视确认内容。

## 4. A/B 对照实验（定位黑屏根因）

当出现"进程活着但画面异常"时，做单变量对照：

- A 组：目标目录为软链 → 启动 → 截图
- B 组：还原为原目录 → 同样方式启动 → 截图
- 唯一变量 = 目录形态，启动方式保持完全一致

实战结论：A 纯黑 29KB、B 正常 1.8MB → 证明黑屏由软链导致，而非启动方式/权限漂移。曾有一轮错误归因为"从沙箱 open 启动导致责任主体漂移"，被此对照证伪——**先做对照再下结论**。

## 5. lsof 决定性判据（资源是否真被读取）

```bash
PID=$(pgrep -f "Applications/<app>.app/<Binary>" | head -1)
lsof -p "$PID" 2>/dev/null | grep -iE "<target-subdir>|<volume-name>" | head -20
```

- 实战成功：进程打开 `MihoyoDownload/Persistent/AssetBundles/blocks/*.blk`，198 个文件句柄。
- 实战失败（软链）：进程开了 80 个文件但无外置盘路径 —— 仅证明"没崩"，不证明"资源可读"。
- 注意 atime 可能因 noatime 挂载不更新，不能作为判据。

## 6. 迁移后每次重新挂载

重启/拔盘后外置盘重新出现，用 `scripts/mount_external.sh`。若需开机自动：现成工具 `auto-mount-Playcover`（github.com/PhiLiaO93/auto-mount-Playcover）基于 Hammerspoon，但其前提为 APFS 卷；HFS+ 场景需自行改脚本或手动运行。
