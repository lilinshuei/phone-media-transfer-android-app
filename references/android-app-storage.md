# Android 存储模型与 App 媒体导入导出通用方法

## 1. 三个存储位置

| 位置 | 路径 | 谁能读 | 用途 |
|---|---|---|---|
| 应用内部私有 | `/data/data/<包名>/` | 只有该 App（+ root） | 数据库、SharedPreferences |
| 应用外部私有 | `/sdcard/Android/data/<包名>/` | 该 App；`shell` 经 ADB 也可读写 | 大文件、下载内容、缓存 |
| 公共存储 | `/sdcard/Download`、`/sdcard/Movies` 等 | 有存储权限的 App；`shell` 可读写 | 用户可见文件 |

关键点：

- `adb shell`（uid 2000）对 `Android/data/<包名>/` 有读写权限，**这是所有外部注入/导出的基础**。
- App 若未申请 `READ_MEDIA_VIDEO` / `MANAGE_EXTERNAL_STORAGE`，则**只能访问自己的 `Android/data` 目录**，读不到公共存储里的文件。把视频放 `/sdcard/Download` 再让 App 打开 `file://` 路径，会得到 `EACCES` 或 `ENOENT`。
- `/data/data/<包名>/databases/` 无 root 不可写；`run-as` 只对 `android:debuggable=true` 的包有效，正式包一律 `package not debuggable`。
- 用 `adb shell` 创建的目录/文件，属主是 `shell`。稳妥做法：目录 `chmod 0777`、文件 `chmod 0666`。

## 2. App 如何"看见"本地媒体

分三类，决定导入策略：

### A. 目录扫描型
启动或进入页面时遍历某个目录，把发现的文件列出来。
- 特征：丢一个文件进去、重启就出现。
- 典型：本地播放器（VLC、MX Player 的自定义文件夹）、部分阅读/漫画 App。
- 策略：找到它扫描的根目录（多在 `Android/data/<包名>/files/` 下或用户自选的 SAF 目录），文件放进去即可。

### B. 数据库索引型
列表来自 SQLite/Room 查询，文件只是"附件"。
- 特征：丢文件进去、重启也不出现；目录里常见 `info.json` 之类的元数据文件。
- 典型：下载管理器、离线阅读器、媒体库类 App。
- 策略，按成本从低到高：
  1. App 自带**备份/恢复**（多为 JSON，导入时整表替换，无校验）——最优突破口；
  2. App 自带**扫描导入**（常要求先设置 SAF 自定义目录）；
  3. 逆向社会工程：读源码拿 schema，离线构造备份文件；
  4. 直接改数据库——需要 root，通常不可行。

### C. 无外部目录型
内容全在云端或内部存储。
- 特征：`Android/data/<包名>` 不存在或只有 cache。
- 策略：不要改造 App，改用系统媒体库 + 通用播放器。

## 3. 判断手法

```bash
# 有没有外部目录、里面有什么
adb shell "ls -la /sdcard/Android/data/<包名>/"

# 有没有数据库/索引
adb shell "find /sdcard/Android/data/<包名> -name '*.db' -o -name '*.json' | head"

# 授权了哪些存储权限（决定它能不能读公共目录）
adb shell "dumpsys package <包名> | grep -E 'READ_MEDIA|MANAGE_EXTERNAL|READ_EXTERNAL'"

# 是否可调试（决定能否 run-as）
adb shell "dumpsys package <包名> | grep -i debuggable"
```

## 4. SAF（存储访问框架）路线

App 若允许用户"选择下载目录"，它会通过 `ACTION_OPEN_DOCUMENT_TREE` 拿到一个 tree URI，并持久化授权。此时：

- App 通过 `content://com.android.externalstorage.documents/...` 访问文件，**不受 scoped storage 限制**；
- 记录里存的路径是 `content://` 而非 `file://`；
- 同一个 App 的 `file://` 与 `content://` 两套路径**不能混用**，切换存储模式后旧条目可能失效。

判断依据：App 设置里是否有"选择目录/自定义下载路径"，且 `SharedPreferences` 里存在 tree URI 字符串。

## 5. 导出方向为什么简单

App 的 `Android/data` 目录对 `shell` 开放读权限，导出就是 `cp`。实际执行请直接调用 `scripts/app_export.sh`；若要手写，等价的安全写法是管道 + 循环，**不要用 `find -exec`**（`-exec` 允许把匹配到的路径直接当命令执行，路径中一旦含特殊字符就会被解释）：

```bash
SRC="/sdcard/Android/data/com.example.app"
DST="/sdcard/导出"
mkdir -p "$DST"
find "$SRC" -type f -name '*.mp4' | while IFS= read -r f; do
  cp "$f" "$DST/$(basename "$f")"
done
```

要点：`find` 的结果**只作为数据流**交给循环读取，所有路径在使用前都加了双引号，不存在路径被当作命令解释的可能。

注意：**复制不移动**。App 的数据库条目仍指向原路径，删原文件会让条目失效（表现为「条目在，但打不开」）。

## 6. 通用坑位

1. **行尾 CRLF 进文件名**：宿主机脚本生成的清单若为 CRLF，设备端 `read` 只去掉 `\n`，`\r` 会粘在文件名末尾，导致 App 按"干净路径"找不到文件，报 `ENOENT`。诊断：`ls | od -An -tx1`，行末出现 `0d 0a` 即是。
2. **中文路径经多层传递易乱码**：Windows PowerShell → adb → sh 这条链上，尽量把含中文的操作写进设备端脚本文件执行，而不是直接拼命令行参数。
3. **PowerShell 5.1 的 UTF-8 BOM**：含中文的 `.ps1` 若保存为无 BOM 的 UTF-8，会被按 ANSI 解析导致语法错乱。必须存 UTF-8 with BOM。
4. **文件选择器按 MIME 过滤**：`.json` 常被归为未知类型从"文档"分类里消失，改 `.txt` 即可被选中。
5. **备份导入多为整表替换**：`deleteAll()` + `insertAll()`，不做任何合并。导入前先导出原数据。
