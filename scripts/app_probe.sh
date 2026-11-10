#!/system/bin/sh
# 彻底探测一个 App 的媒体存储位置：私有目录 / 媒体目录 / 公共目录 / 数据库内路径
# 用法: sh app_probe.sh <包名> [关键词]
# 关键词用于在公共存储里模糊匹配目录名（如 App 名、品牌词）

PKG="$1"
KW="$2"
[ -n "$PKG" ] || { echo "用法: sh app_probe.sh <包名> [关键词]"; exit 1; }

# 包名会被拼进路径并交给 dumpsys，先做白名单过滤，防止 ../ 与元字符
case "$PKG" in
  *[!A-Za-z0-9._]*) echo "非法包名: $PKG"; exit 2 ;;
esac

DATA="/sdcard/Android/data/$PKG"
MEDIA="/sdcard/Android/media/$PKG"

echo "########## 1. App 基本信息 ##########"
dumpsys package "$PKG" 2>/dev/null | grep -E 'versionName|versionCode|firstInstallTime' | head -3
echo "--- 存储权限 ---"
dumpsys package "$PKG" 2>/dev/null | grep -E 'READ_MEDIA_VIDEO|READ_MEDIA_IMAGES|MANAGE_EXTERNAL_STORAGE|READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE' | head -10
PERM=$(dumpsys package "$PKG" 2>/dev/null | grep -cE 'READ_MEDIA|MANAGE_EXTERNAL|READ_EXTERNAL')
if [ "$PERM" -eq 0 ]; then
  echo ">>> 结论：无存储权限 → 只能读自己的 Android/data 目录，公共目录里的文件它读不到"
else
  echo ">>> 结论：有存储权限 → 公共目录里的媒体它可能能扫到"
fi

echo
echo "########## 2. 外部私有目录 ##########"
if [ -d "$DATA" ]; then
  echo "[存在] $DATA"
  ls -la "$DATA"
  echo "--- 目录结构（深度 5，含隐藏）---"
  find "$DATA" -maxdepth 5 -type d 2>/dev/null | head -60
  echo "--- .nomedia 标记（被隐藏的媒体目录）---"
  find "$DATA" -name '.nomedia' 2>/dev/null | head -10
else
  echo "[不存在] $DATA —— 该 App 不使用外部私有目录"
fi

echo
echo "########## 3. 媒体目录 Android/media ##########"
if [ -d "$MEDIA" ]; then
  echo "[存在] $MEDIA"
  ls -la "$MEDIA"
else
  echo "[不存在] $MEDIA"
fi

echo
echo "########## 4. 媒体文件统计 ##########"
for root in "$DATA" "$MEDIA"; do
  [ -d "$root" ] || continue
  v=$(find "$root" -type f \( -name '*.mp4' -o -name '*.mkv' -o -name '*.avi' -o -name '*.mov' -o -name '*.webm' -o -name '*.flv' -o -name '*.3gp' \) 2>/dev/null | wc -l)
  i=$(find "$root" -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' -o -name '*.gif' -o -name '*.bmp' \) 2>/dev/null | wc -l)
  echo "$root : 视频 $v 个 / 图片 $i 个"
done
echo "--- 视频样本（前 5）---"
find "$DATA" "$MEDIA" -type f -name '*.mp4' 2>/dev/null | head -5
echo "--- 图片样本（前 5）---"
find "$DATA" "$MEDIA" -type f \( -name '*.jpg' -o -name '*.png' \) 2>/dev/null | head -5

echo
echo "########## 5. 公共存储候选目录 ##########"
echo "（App 有时把内容放在 /sdcard 下自建目录，或用户选的 SAF 目录）"
for d in /sdcard/*/; do
  name=$(basename "$d")
  hit=0
  if [ -n "$KW" ]; then
    case "$name" in *"$KW"*) hit=1 ;; esac
  fi
  case "$PKG" in *"$name"*) hit=1 ;; esac
  if [ "$hit" = "1" ]; then
    echo "[命中] $d"
    ls -la "$d" 2>/dev/null | head -8
  fi
done

echo
echo "########## 6. 从数据库里挖存储路径 ##########"
echo "（App 的 .db 里常存着它真实使用的目录）"
found=0
for db in $(find "$DATA" -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.json' \) 2>/dev/null | head -10); do
  paths=$(tr -c '[:print:]' '\n' < "$db" 2>/dev/null | grep -E '^/(sdcard|storage)' | sort -u | head -5)
  if [ -n "$paths" ]; then
    found=1
    echo "--- $db ---"
    echo "$paths"
  fi
done
[ "$found" = "0" ] && echo "（未从数据库中发现路径信息）"

echo
echo "########## 7. 总体积 ##########"
[ -d "$DATA" ] && du -sh "$DATA" 2>/dev/null
[ -d "$MEDIA" ] && du -sh "$MEDIA" 2>/dev/null
echo
echo "########## 判断建议 ##########"
echo "· 私有/media 目录里有大量媒体 → 可直接导入导出（本技能覆盖）"
echo "· 目录里只有 .db/索引、媒体数为 0 → 数据库索引型，需要在 App 内导入或走备份机制"
echo "· 两个目录都不存在 → 内容在内部存储 /data/data，无 root 不可达，只能通过 App 自身的导入/导出界面"
