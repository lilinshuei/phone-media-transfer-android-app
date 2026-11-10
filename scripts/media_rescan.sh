#!/system/bin/sh
# 让公共目录里的新文件被媒体库收录，从而被大多数 App 看到
# 用法: sh media_rescan.sh [路径]
TARGET="${1:-/sdcard/Download}"

echo "--- 尝试 1：MediaProvider 全卷扫描 ---"
content call --uri content://media --method scan_volume --arg external_primary 2>&1 | head -3

echo "--- 尝试 2：对目标文件逐个广播（旧版机制，部分机型仍有效）---"
find "$TARGET" -maxdepth 2 -type f \( -name '*.mp4' -o -name '*.jpg' -o -name '*.png' \) 2>/dev/null | head -5 | while read -r f; do
  am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$f" 2>&1 | tail -1
done

echo "--- 校验：媒体库里的视频总数 ---"
content query --uri content://media/external/video/media --projection _id 2>/dev/null | grep -c "Row:"
