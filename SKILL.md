---
name: phone-media-transfer-android-app
display_name: "将手机的视频图片导出入操作无门的安卓APP"
display_name_en: "Import & Export Photos/Videos for Stubborn Android Apps"
description: "Import videos and images into hard-to-handle Android apps from a computer over ADB, or export them into a chosen folder. Handles hidden folders, deep nesting, .nomedia shielding, and apps with no external folder at all through UI automation."
description_zh: "用电脑的 ADB 操控手机，把视频/图片塞进那些「操作无门」的安卓 App，或从里面掏出来存到指定文件夹。操作无门包括找不到文件夹、文件夹被隐藏、藏了五六层、被 .nomedia 屏蔽、App 根本没有外部文件夹。当用户提到「把视频/图片放进某个 App 里」「从某个 App 导出照片/视频」「这个 App 的图片存哪了」「把 App 的缓存导出来」时使用。"
description_en: "Use ADB from a computer to push videos and images into hard-to-handle Android apps, or pull them out into a folder you choose. Hard to handle means no visible folder, hidden folder, five-level-deep nesting, .nomedia shielding, or no external folder at all. Use when the user asks to put media into an app, pull media out of an app, find where an app stores its photos, or export an app's cached videos."
category: "media"
version: "1.0.2"
author: "lilinshuei"
---

# 将手机的视频图片导出入操作无门的安卓APP

> 适用于你拥有或已获授权操作的设备与内容。ADB 是系统级工具，请先确认手机已开启「开发者选项 → USB 调试」，并只对授权 App 执行读写。

## 一、先明确能力边界（很重要）

ADB 能用的是 `shell`（uid 2000）身份，因此：

| 位置 | 可读 | 可写 | 说明 |
|---|---|---|---|
| `/sdcard/Android/data/<包名>/` | ✅ | ✅ | App 外部私有目录，**主要战场** |
| `/sdcard/Android/media/<包名>/` | ✅ | ✅ | 媒体私有目录 |
| `/sdcard/` 公共目录 | ✅ | ✅ | Download / Pictures / Movies / 各 App 自建目录 |
| `/data/data/<包名>/` | ❌ | ❌ | 内部存储，无 root 不可达；`run-as` 只对 debuggable 包有效 |
| 私密保险箱/加密区 | ❌ | ❌ | 系统级加密，列出也是密文 |

**结论**：只要 App 把内容放在外部存储（无论藏多深、是否 `.nomedia`、是否点开头），都能定位并导入导出；**只有纯内部存储 / 加密存储的 App，才必须走「界面自动化」或「App 自带功能」**。这是硬边界，任何工具都绕不过，遇到时如实告知用户，不要硬试。

## 二、四条路线（按顺序判断，命中即停）

| 路线 | 触发特征 | 做法 |
|---|---|---|
| **A. 目录扫描型** | 丢文件进去、重启 App 就出现 | 直接把文件放进它扫描的目录，不碰数据库 |
| **B. 数据库索引型** | 丢文件无效；目录里有 `.db` 或元数据文件（App 自己写的那种） | 用 App 自带「备份恢复 / 扫描导入 / 自定义目录(SAF)」；必要时按公开资料构造备份文件 |
| **C. 媒体库依赖型** | App 靠系统相册/媒体库读取 | 文件放公共目录 + `scripts/media_rescan.sh` 刷新媒体库 |
| **D. 界面驱动型** | 外部目录里没有媒体，或必须用 App 的导入按钮 | 用 `scripts/ui_auto.ps1` 操控界面：点按钮、选文件、确认 |

判型错了会浪费大量时间：A 类不需要任何 hack，B 类硬塞文件永远无效。

## 三、标准作业流程

### 第 1 步：确定是哪个 App

用户说「这个 App」时先问、或直接读前台窗口：

```bash
adb push scripts/app_identify.sh /data/local/tmp/
adb shell "sh /data/local/tmp/app_identify.sh"
```

输出 `mCurrentFocus=Window{... u0 com.xxx.yyy/...}`，`com.xxx.yyy` 即包名。也可用 `adb shell pm list packages -3` 列出所有第三方包名。

### 第 2 步：彻底探测

```bash
adb push scripts/app_probe.sh /data/local/tmp/
adb shell "sh /data/local/tmp/app_probe.sh <包名> [关键词]"
```

会输出：版本与存储权限、`Android/data/<包名>` 全目录（深度 5、含隐藏）、`Android/media/<包名>`、`.nomedia` 标记位置、视频/图片数量与样本、`/sdcard` 下自建目录模糊匹配、**从 `.db` 里挖出的真实存储路径**、总体积。

关键词建议填 App 中文名或品牌词，用于在公共存储里模糊命中。

### 第 3 步：按探测结果选路线并执行

**导出（所有路线通用，最简单）**

```bash
adb push scripts/app_export.sh /data/local/tmp/
adb shell "sh /data/local/tmp/app_export.sh <包名> '/sdcard/导出目录' [关键词] [video|image|all]"
```

原理：`shell` 对 `Android/data|media/<包名>` 有读权限，直接 `cp`。**是复制不是移动**——App 的数据库条目仍指向原路径，删原文件会让条目失效。同名文件自动加序号，不会互相覆盖。

**导入**

- A 类：定位它扫描的目录（探测结果的目录树里，媒体文件所在的父目录），把文件放进去。
- B 类：查 App 设置里有没有「导入 / 备份恢复 / 选择下载目录」。有备份机制就导出原备份 → 改内容 → 导入；不同 App 的备份格式差异很大，按它自己的导出文件结构来改，不要凭空构造。
- C 类：文件放公共目录后执行
  ```bash
  adb shell "sh /data/local/tmp/media_rescan.sh /sdcard/Pictures"
  ```
- D 类：见下一节。

### 第 4 步：界面驱动（文件系统不可达时）

```powershell
# 看当前界面有哪些可点元素（返回 坐标 x,y、文字、描述）
powershell -File scripts/ui_auto.ps1 -Adb <adb路径> -Action dump

# 按文字/描述点击（先精确匹配，再模糊匹配）
powershell -File scripts/ui_auto.ps1 -Adb <adb路径> -Action tap -Label "导入"

# 找不到就滚动找（最多 8 屏）
powershell -File scripts/ui_auto.ps1 -Adb <adb路径> -Action scrollfind -Label "相册"

# 等某个界面元素出现
powershell -File scripts/ui_auto.ps1 -Adb <adb路径> -Action wait -Label "完成" -TimeoutSec 30

# 输入文本 / 返回 / 回桌面
powershell -File scripts/ui_auto.ps1 -Adb <adb路径> -Action type -Text "关键词"
powershell -File scripts/ui_auto.ps1 -Adb <adb路径> -Action back
```

配合 `adb shell input tap x y` 可以完成「打开 App → 点导入 → 选文件 → 确认」。

注意：部分国产系统的「USB 调试(安全设置)」若关闭，`input` 注入可能被拦截，此时只能让用户手动点。

## 四、高频坑

1. **CRLF 污染文件名**：宿主机生成的清单若为 CRLF，设备端 `read` 只去 `\n`，`\r` 粘进文件名 → App 报 `ENOENT`。诊断：`ls | od -An -tx1`，行末出现 `0d`。修：`tr -d '\r'`。
2. **中文路径经命令行传递会乱码**：Windows PowerShell → adb → sh 这条链上，含中文的操作要写进设备端脚本文件执行，别直接拼参数。
3. **PowerShell 5.1 的 BOM**：含中文的 `.ps1` 必须存 UTF-8 **with BOM**，否则按 ANSI 解析、语法错乱。
4. **文件选择器按 MIME 过滤**：`.json` 常从「文档」分类消失，改 `.txt` 即可被选中。
5. **备份导入多为整表替换**：`deleteAll` + `insertAll`，导入前必须先导出。
6. **`.nomedia` 不阻碍访问**：它只让媒体库不收录，`find`/`cp` 照常，别被吓住。
7. **App 无存储权限**：只能读自己的 `Android/data`，公共目录的文件它读不到——导入必须放进它的私有目录。
8. **元数据文件不要凭空手写**：B 类 App 常在下载目录里放自己的索引/播放元数据。先看一份 App 真实生成的样本，再按同样结构改；字段留空或格式不对，表现常常是「条目在，但打不开」。

## 五、技能包文件清单

```
SKILL.md                                  本文件：能力说明与执行流程
references/android-app-storage.md         Android 存储模型与各类 App 索引方式
scripts/app_identify.sh                   读前台窗口，确定当前是哪个 App
scripts/app_probe.sh                      彻底探测：私有/media/公共/隐藏/深目录、媒体统计、DB 路径挖掘
scripts/app_export.sh                     导出视频/图片，支持关键词与类型筛选
scripts/media_rescan.sh                   刷新媒体库，让公共目录文件被 App 看到
scripts/ui_auto.ps1                       界面自动化：dump / tap / scrollfind / wait / type / back / home
```

### 脚本用途速查

| 脚本 | 作用 | 运行位置 |
|---|---|---|
| `scripts/app_identify.sh` | 读前台窗口，确定当前是哪个 App | 设备端 |
| `scripts/app_probe.sh` | 彻底探测：私有/media/公共/隐藏/深目录、媒体统计、DB 路径挖掘 | 设备端 |
| `scripts/app_export.sh` | 导出视频/图片，支持关键词与类型筛选 | 设备端 |
| `scripts/media_rescan.sh` | 刷新媒体库，让公共目录文件被 App 看到 | 设备端 |
| `scripts/ui_auto.ps1` | 界面自动化：dump / tap / scrollfind / wait / type / back / home | 宿主侧 |

## 六、命令执行安全约定

1. 所有设备端脚本只通过 `adb push` 后以 `sh <脚本路径> <参数>` 调用；参数来自包名、关键词等受控输入。
2. **不使用 `find -exec`**：该写法会把匹配到的路径直接当命令执行，路径含特殊字符时会被解释。需要批量复制时用管道 + `while read` 循环，并对路径加双引号。
3. **用户输入进入 shell 前必须白名单过滤**：`scripts/ui_auto.ps1` 的 `type` 动作只允许字母、数字、空格、常见中文及 `- _ . , : @ + = / % # ?`，其余字符（含 `; & | \` $ ( ) < > \ " '` 与控制字符）一律剔除，并输出提示。
4. 界面自动化只对**坐标**做点击（坐标为整数，由界面解析结果计算），不把界面文本回灌进 shell 命令。
5. **禁止对用户给定路径做递归删除**：清理只能是「只删本脚本产物（按扩展名/前缀限定）+ 显式确认开关」，且删除前列出目标路径与数量。
6. **所有 `Join-Path` / 字符串拼接出的路径必须做包含校验**：结果必须以「输出根目录 + 分隔符」开头，否则拒绝执行，防止 `..` 逃逸。
7. **产物目录必须是专用目录**：拒绝盘符根、系统目录、用户主目录及其内部、层级过浅的路径。

## 七、脚本声明（静态审计用）

本技能包内共 5 个脚本，全部在正文声明用途与调用方式，**无未声明脚本**。

1. `scripts/app_identify.sh` —— 读前台窗口确定 App 包名。调用 `sh /data/local/tmp/app_identify.sh`
2. `scripts/app_probe.sh` —— 彻底探测存储位置。调用 `sh /data/local/tmp/app_probe.sh <包名> [关键词]`
3. `scripts/app_export.sh` —— 导出视频/图片。调用 `sh /data/local/tmp/app_export.sh <包名> <目标目录> [关键词] [video|image|all]`
4. `scripts/media_rescan.sh` —— 刷新媒体库。调用 `sh /data/local/tmp/media_rescan.sh [路径]`
5. `scripts/ui_auto.ps1` —— 界面自动化。调用 `powershell -File scripts/ui_auto.ps1 -Adb <adb> -Action dump`
