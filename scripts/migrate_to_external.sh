#!/bin/bash
# 迁移流程骨架：把沙盒 App 数据子目录迁到外置盘 HFS+ 稀疏映像
# 使用前替换所有 *** 占位符；按顺序逐段执行，每段验证后再继续。
# 完整判据见 SKILL.md 阶段 3，命令细节见 references/probe-and-verify.md

set -e

BUNDLE_ID="***com.miHoYo.Yuanshen***"          # 沙盒容器 bundle id
DATA_SUBDIR="***Data/Library/MihoyoDownload***" # 容器内要迁的大头子目录（相对容器根）
EXTERNAL_VOL="***/Volumes/<your-disk>***"       # 外置盘挂载点
IMAGE_NAME="***AppDataHFS.sparsebundle***"      # 映像文件名
VOL_NAME="***AppDataHFS***"                     # 映像卷名

CONTAINER="$HOME/Library/Containers/$BUNDLE_ID"
TARGET="$CONTAINER/$DATA_SUBDIR"
IMG="$EXTERNAL_VOL/PlayCover迁移备份/$IMAGE_NAME"
BACKUP="$EXTERNAL_VOL/PlayCover迁移备份/${BUNDLE_ID}-$(basename "$DATA_SUBDIR")"

echo "=== 0. 只读取证 ==="
du -sh "$TARGET"
find "$TARGET" -type f | wc -l
df -h "$EXTERNAL_VOL"
pgrep -fl "***app-keyword***" && { echo "请先退出 App"; exit 1; } || true

echo "=== 1. 备份并校验（排除 exFAT 元数据）==="
mkdir -p "$(dirname "$BACKUP")"
rsync -a --exclude='._*' "$TARGET/" "$BACKUP/"
echo "源文件数=$(find "$TARGET" -type f ! -name '._*' | wc -l) 备份文件数=$(find "$BACKUP" -type f ! -name '._*' | wc -l)"
rsync -an --delete --exclude='._*' "$TARGET/" "$BACKUP/"   # 应无输出

echo "=== 2. 最小可行性探针（100M）==="
# 见 references/probe-and-verify.md 第 1 节；探针通过后再继续

echo "=== 3. 建 HFS+ 映像并灌数据 ==="
[ -e "$IMG" ] && { echo "映像已存在，中止以免覆盖"; exit 1; }
hdiutil create -size 60g -type SPARSEBUNDLE -fs HFS+ -volname "$VOL_NAME" "$IMG"
hdiutil attach -nobrowse -mountpoint /tmp/stage "$IMG"
rsync -a --exclude='._*' "$BACKUP/" /tmp/stage/
echo "映像内文件数=$(find /tmp/stage -type f ! -name '._*' | wc -l)"
hdiutil detach /tmp/stage

echo "=== 4. 挂载到容器子目录（原内容被遮蔽，可回滚）==="
mkdir -p "$TARGET"
hdiutil attach -nobrowse -mountpoint "$TARGET" "$IMG"
mount | grep "$TARGET"
du -sh "$TARGET"

echo "=== 5. 启动 App 并逐条验收（见 SKILL.md 阶段 3 表格）==="
echo "open <app-path> 后用 lsof/screencapture 验证；不要只看进程存活。"

echo "=== 6. 确认无误后才释放本机空间（需用户显式授权）==="
# 退出 App → detach → 移走/删除原目录 → 重建挂载点 → 重挂 → 重跑阶段 3
