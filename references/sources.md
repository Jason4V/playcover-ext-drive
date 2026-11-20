# 来源溯源（原文关键段照抄）

本 skill 的方法论来源。以下均为原文摘录，非转述；结论与限定语同句保留。

## 1. PlayCover 官方讨论 #473 — 为何软链不行

链接：https://github.com/PlayCover/PlayCover/discussions/473

- 成员 Candygoblen123（2022-10-31）原文：
  > "Basically no. While we could technically move the .app bundle off the boot drive, genshin impact will always look in its container folder for the downloaded assets. You can't move that to any other drive."

- 成员 Candygoblen123 谈 symlink 原文：
  > "I haven't confirmed this myself, but I think I remember someone trying that and genshin just crashes. Feel free to try it yourself though."

- 成员 ohaiibuzzle（2022-11-01）原文：
  > "WIth the current system, would be very likely that you straight up cannot. By default a macOS application can only read: At the specific direction of the user (so, TCC) / By using entitlements for specific file-system locations / When the file system location is in certain directories that are world readable when sandboxed by the OS. If it was really possible, it would be a serious security flaw (as an app can just make a symlink and reads anything it wants)"

## 2. PlayCover 官方讨论 #1712 — 挂载迁移教程

链接：https://github.com/PlayCover/PlayCover/discussions/1712
标题：Tutorial: Moving applications to external drive（作者 LXY113，2024-10-10，label: documentation）

原文关键段：
> 「首先来移动PlayCover本体……使用「diskutil list」命令，查询外接硬盘的APFS容器编号……使用命令「sudo umount -f /Volumes/PlayCover」卸载PlayCover容器，然后使用命令「sudo mount_apfs /dev/disk5s2 /Users/abc/Library/Containers/_io.playcover.PlayCover_」将创建的PlayCover的APFS容器装载到Containers的文件夹中（如果提示mount apfs: volume could not be mounted: Operation not permitted，请尝试关闭SIP）」

> 「3.游戏的移动，例子是崩坏星穹铁道……「sudo mount_apfs /dev/disk5s3 /Users/abc/Library/Containers/_com.miHoYo.hkrpg_」」

> 「4.其他说明，每次插入移动硬盘都需要进行以上操作，大家可以编写一个.sh文件自动执行……本方法对于游戏更新，覆盖安装等都可以，亲测「原神」更新正常。」

评论（BlueSkyXN，2025-06-09）：
> 「关闭SIP会导致iOS App无法使用，两头堵了啊」
> 「试了下只能用子目录挂载绕开SIP」+ 视频 https://www.bilibili.com/video/BV1i4mKYiEtt/

评论（KarimAkra，2025-10-04）风险案例：macOS 15.7.1 后从 /Volumes 启动 app 崩溃，堆栈 `libsystem_secinit.dylib _libsecinit_appsandbox.cold.6`。注意该案例是移动 app 本体到外置卷，非本 skill 的容器子目录挂载场景。

## 3. B 站视频 BV1i4mKYiEtt — 子目录挂载实测

链接：https://www.bilibili.com/video/BV1i4mKYiEtt/ （2024-10-16）

视频简介原文（原神部分）：
> 「每次接入移动硬盘的操作 以原神为例
> 1、卸载要装载的盘符
> sudo umount -f /Volumes/yuanshen
> 2、装载磁盘到对应的文件夹上面
> sudo mount_apfs /dev/disk5s2 /Users/$USER/Library/Containers/com.miHoYo.Yuanshen/Data/Library/MihoyoDownload」

> 「原神 /Users/$USER/Library/Containers/com.miHoYo.Yuanshen/Data/Library/MihoyoDownload」

AI 字幕原文：
> 「我试过直接将date放到根目录还是不能运行，所以这次找的是这一个文件夹，米哈游的download」
> 「首先需要打开系统设置安全与隐私，这个地方有一个完全磁盘访问，将这个终端勾上」

## 4. 潘文斌文档馆 — 软链 vs 挂载的独立佐证

链接：https://www.panwenbin.com/mac-softwares/运行ios-app

原文：
> 「先尝试做软链接，发现不行，因为是在沙盒里面。但是从B站看到直接挂载到目录是可以的。测试了一下果然可以，就是一个分区只能用来挂载一个游戏，不太舒服。因为上层目录是所有应用的目录，不适合用来挂载上层目录。尝试把原神放在了sd卡里，效果还不错，读取速度有40MB/s左右，游戏加载速度看不到明显差别。」

## 5. egeek.me — exFAT 上建 APFS 映像挂到应用数据目录（免重格路径）

链接：https://egeek.me/2025/01/05/snapshots-for-ios-backups

原文命令：
> `hdiutil create -megabytes $((1024*128)) -type SPARSEBUNDLE -fs apfs -volname MobileSync /Volumes/external/MobileSync.sparsebundle`
> `hdiutil attach /Volumes/external/MobileSync.sparsebundle -mountpoint ~/Library/Application\ Support/MobileSync -noautoopen`

原文限定语：
> "Even if it's not empty at mount time, the files there are not removed, they are only hidden until you unmount the image."

注：本 skill 实战中 APFS 路径因无 root 失败，改用 HFS+；但"映像挂到应用数据目录 + 非空挂载点遮蔽可回滚"的思路来自此文。

## 6. 现成自动化工具

链接：https://github.com/PhiLiaO93/auto-mount-Playcover

功能原文：使用 Hammerspoon 自动管理并挂载移动到外部硬盘的 PlayCover 游戏目录；前提"外置卷格式为 APFS"、"已安装并配置 Hammerspoon"、"已知目标卷的 Partition UUID 及期望挂载路径"。本 skill 的 HFS+ 方案需自行改脚本。
