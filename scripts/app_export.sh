#!/system/bin/sh
# 通用导出：把任意 App 私有目录里的视频/图片复制到指定文件夹
# 用法: sh app_export.sh <包名> <目标目录> [关键词] [video|image|all]
# 说明: shell 对 /sdcard/Android/data|media/<包名> 有读权限，无需 root；是复制不是移动

PKG="$1"
OUT="$2"
KW="$3"
TYPE="${4:-all}"

[ -n "$PKG" ] && [ -n "$OUT" ] || { echo "用法: sh app_export.sh <包名> <目标目录> [关键词] [video|image|all]"; exit 1; }

# 包名会被拼进路径，先做白名单过滤（字母数字与 . _），防止 ../ 跳目录
case "$PKG" in
  *[!A-Za-z0-9._]*) echo "非法包名: $PKG"; exit 2 ;;
esac

DATA="/sdcard/Android/data/$PKG"
MEDIA="/sdcard/Android/media/$PKG"
[ -d "$DATA" ] || [ -d "$MEDIA" ] || { echo "该 App 没有可读的外部目录: $DATA / $MEDIA"; exit 1; }
mkdir -p "$OUT" || { echo "无法创建目标目录: $OUT"; exit 1; }

case "$TYPE" in
  video) PAT="-name *.mp4 -o -name *.mkv -o -name *.avi -o -name *.mov -o -name *.webm -o -name *.flv -o -name *.3gp" ;;
  image) PAT="-name *.jpg -o -name *.jpeg -o -name *.png -o -name *.webp -o -name *.gif -o -name *.bmp" ;;
  *)     PAT="-name *.mp4 -o -name *.mkv -o -name *.avi -o -name *.mov -o -name *.webm -o -name *.flv -o -name *.3gp -o -name *.jpg -o -name *.jpeg -o -name *.png -o -name *.webp -o -name *.gif -o -name *.bmp" ;;
esac

LOG=/data/local/tmp/app_export.log
: > "$LOG"

for root in "$DATA" "$MEDIA"; do
  [ -d "$root" ] || continue
  find "$root" -type f \( $PAT \) 2>/dev/null | while read -r f; do
    name=$(basename "$f" | tr -d '\r')
    if [ -n "$KW" ]; then
      case "$name" in
        *"$KW"*) ;;
        *) continue ;;
      esac
    fi
    target="$OUT/$name"
    if [ -e "$target" ]; then
      base="${name%.*}"
      ext="${name##*.}"
      i=1
      while [ -e "$OUT/${base}_$i.$ext" ]; do i=$((i + 1)); done
      target="$OUT/${base}_$i.$ext"
    fi
    if cp "$f" "$target"; then
      echo "OK $name" >> "$LOG"
    else
      echo "FAIL $name" >> "$LOG"
    fi
  done
done

cnt=$(grep -c '^OK ' "$LOG" 2>/dev/null)
bad=$(grep -c '^FAIL ' "$LOG" 2>/dev/null)
echo "EXPORTED=${cnt:-0}  FAILED=${bad:-0}"
echo "TARGET=$OUT"
echo "DETAIL=$LOG"
