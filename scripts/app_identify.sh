#!/system/bin/sh
# 识别当前前台 App 的包名（用户说"就在这个 App 里"时用）
echo "===== 当前前台窗口 ====="
dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | head -4
echo
echo "===== 前台 Activity ====="
dumpsys activity activities 2>/dev/null | grep -E 'ResumedActivity|topResumedActivity' | head -3
echo
echo "===== 最近使用的 App（近 10 个）====="
dumpsys usagestats 2>/dev/null | grep -oE 'package=com\.[A-Za-z0-9_.]+' | head -10
