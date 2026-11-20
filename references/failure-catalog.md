# 失败路径四要素复盘

全部失败均来自 2026-11-20 实战，按「现象 / 根因 / 为什么犯 / 如何避免」记录。

## F1. 软链接导致游戏黑屏

- **现象**：原神容器内 `MihoyoDownload` 建 `ln -s` 指向外置 exFAT 目录后，启动窗口纯黑（单窗截图 29KB），无崩溃日志，进程存活 45 秒，`lsof` 无外置盘文件句柄。
- **根因**：macOS 沙盒 App 对容器内指向 `/Volumes` 的符号链接在启动阶段校验失败。官方 PlayCover #473 成员说明这是安全模型设计，若允许软链读任意路径将是严重安全漏洞。不是 exFAT 特例，也不是启动方式问题。
- **为什么犯**：文件系统层 `ls` 穿透和写入测试都通过，就把"目录可读"等同于"沙盒 App 可接受"；且 CSDN 有 `ln -s` 成功案例，未验证其对沙盒的适用性。
- **如何避免**：（1）沙盒场景禁用软链作为主方案；（2）判定必须做 A/B 单变量对照 + `lsof` 资源层验证，不靠进程存活；（3）先做 100M 探针 + 游戏启动实测再灌大数据。

## F2. APFS 映像挂载失败（Operation not permitted）

- **现象**：按文献建 60G APFS sparsebundle 成功（初始 30M），`hdiutil attach` 报「无可装载的文件系统」，`diskutil mount /dev/diskNsM` 报 failed，`mount_apfs` 报 `Operation not permitted`。
- **根因**：执行环境无免密 sudo（`sudo -n true` 返回 operation not permitted），APFS 卷挂载需要 root。非映像损坏（`imageinfo` / `attach -nomount` 均显示 APFS 容器和卷正常），非 exFAT 格式问题。
- **为什么犯**：照抄文献的 APFS 路径，未先验证本机提权能力；凭"有成功案例"直接动手。
- **如何避免**：（1）挂载类方案先跑 `sudo -n true` 探测提权；（2）无 root 时改用 HFS+ sparsebundle；（3）坚持"最小可行性探针先行"机制。

## F3. 沙盒容器内目录删除静默失效（TCC 保护）

- **现象**：`rm -rf <trash-path>` 返回 exit 0 但 31G 目录完好、1299 文件仍在；Finder delete 报权限违例 -10004；`chflags -R nouchg` 无效。此前绝区零容器（带 `com.apple.containermanager.*` 元数据）同款现象。
- **根因**：Sonoma+ 的 SIP/TCC 保护，容器元数据 plist 连 sudo rm 都难删。
- **为什么犯**：把 `rm -rf` 返回 0 当作删除成功，未立即验证落盘。
- **如何避免**：（1）删除后必须 `[ -e path ] && du -sh path` 复核；（2）遇到静默失效立即停止重试，交用户手动删或先授权"完全磁盘访问"；（3）移入废纸篓 ≠ 释放空间，需明确告知用户。

## F4. 废纸篓项重命名导致误判数据丢失

- **现象**：`du ~/.Trash/MihoyoDownload` 显示 0B，一度以为 31G 数据丢失；实际实体在 `~/.Trash/MihoyoDownload 15-39-29-765`（带时间戳后缀）。
- **根因**：`trash` 工具遇到同名项（此前软链测试遗留的同名符号链接）会自动加时间戳后缀；`~/.Trash/MihoyoDownload` 恰是指向外置备份的历史软链接，`du` 不跟随故为 0B。
- **为什么犯**：只按预期单一路径名查，未列出全部匹配项就下结论。
- **如何避免**：校验废纸篓项一律 `ls -lat ~/.Trash | grep -iE '<关键词>'` 全量列出再操作，不凭单一路径判断。

## F5. 跨盘 mv 报 EXDEV

- **现象**：`mv` 内置盘目录到外置盘报 EXDEV（exit 13），源目录未受影响。
- **根因**：跨文件系统不能 rename。
- **如何避免**：跨盘一律用 `cp -a` 或 `rsync -a`，复制后校验再删源。

## F6. exFAT AppleDouble 元数据导致文件数翻倍假象

- **现象**：`cp -a` 后源 6424 文件、目标 13012 文件，看似备份损坏。
- **根因**：exFAT 上 macOS 自动生成约 6588 个 `._*` AppleDouble 文件模拟 Unix 元数据。排除 `._*` 后 6424=6424，`rsync -an --delete` 差异为空。
- **如何避免**：所有 exFAT 往返校验都加 `--exclude='._*'` / `! -name '._*'`；不要仅凭 `find -type f` 总数判定完整性。
