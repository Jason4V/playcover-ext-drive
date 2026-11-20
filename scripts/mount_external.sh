#!/bin/bash
# 重启/拔插外置盘后，重新挂载沙盒 App 数据映像
# 使用前替换所有 *** 占位符；无需 sudo / 无需关 SIP / 无需完全磁盘访问

IMG="***/Volumes/<your-disk>/PlayCover迁移备份/AppDataHFS.sparsebundle***"
MNT="$HOME/Library/Containers/***com.miHoYo.Yuanshen***/***Data/Library/MihoyoDownload***"
APP_KEYWORD="***Applications/com.miHoYo.Yuanshen.app/Yuanshen***"

echo "=== 外置数据挂载 ==="

# 已挂载则直接报告，不重复操作
if mount | grep -q "on $MNT "; then
  echo "已挂载，无需重复操作："
  df -h "$MNT" | tail -1
  exit 0
fi

# 未挂载时：先确认 App 未运行，避免挂载遮蔽正在读的资源
if pgrep -f "$APP_KEYWORD" >/dev/null 2>&1; then
  echo "警告：检测到目标 App 正在运行。请先退出 App 再挂载，避免资源读写冲突。"
  exit 1
fi

if [ ! -d "$IMG" ]; then
  echo "错误：外置盘或映像不存在：$IMG"
  echo "请确认外置盘已插入并挂载。"
  exit 1
fi

mkdir -p "$MNT"
echo "正在挂载..."
if hdiutil attach -nobrowse -mountpoint "$MNT" "$IMG" >/dev/null 2>&1; then
  echo "挂载成功 ✓"
  df -h "$MNT" | tail -1
  echo "资源文件数：$(find "$MNT" -type f ! -name '._*' | wc -l | tr -d ' ')"
  echo "现在可以启动 App 了。"
else
  echo "挂载失败 ✗ 可能原因：外置盘未插好、映像损坏、或挂载点被占用。"
  exit 1
fi
