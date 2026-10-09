#!/bin/sh
set -eu
[ "$(id -u)" = 0 ] || { echo '需要管理员权限。'; exit 1; }
BASE=/Library/Printers/hp-legacy-mac
QUEUE=HP1020_SMB
PPDS=/etc/cups/ppd
FILTER=$BASE/hp1020-smb-filter

# A failed queue lookup must not be mistaken for an absent queue when CUPS is down.
/usr/sbin/cupsctl >/dev/null || { echo '无法读取打印系统配置，未删除任何内容。请确认打印服务可用后重试。'; exit 1; }
HAS_QUEUE=no
if /usr/bin/lpstat -p "$QUEUE" >/dev/null 2>&1; then
    HAS_QUEUE=yes
    [ -f "$PPDS/$QUEUE.ppd" ] && [ ! -L "$PPDS/$QUEUE.ppd" ] || {
        echo '无法确认 HP1020_SMB 队列使用的驱动，未删除任何内容。'; exit 1
    }
    /usr/bin/grep -Fq " $FILTER\"" "$PPDS/$QUEUE.ppd" || {
        echo 'HP1020_SMB 队列未使用本工具的过滤器，未删除任何内容。'; exit 1
    }
fi

if [ -e "$BASE" ] || [ -L "$BASE" ]; then
    [ -d "$BASE" ] && [ ! -L "$BASE" ] && [ -f "$FILTER" ] && [ ! -L "$FILTER" ] || {
        echo '驱动目录不是本工具预期的安装结构，未删除任何内容。'; exit 1
    }
    /usr/bin/grep -Fxq "BASE=$BASE" "$FILTER" || {
        echo '无法确认驱动属于本工具，未删除任何内容。'; exit 1
    }
    [ -d "$PPDS" ] && [ -r "$PPDS" ] && [ -x "$PPDS" ] || {
        echo '无法检查打印队列的驱动目录，未删除任何内容。'; exit 1
    }
    # Check every installed PPD before changing either the queue or driver files.
    # Matching the directory also catches other filters from this shared bundle.
    for ppd in "$PPDS"/*.ppd; do
        [ -e "$ppd" ] || [ -L "$ppd" ] || continue
        [ "$HAS_QUEUE" = yes ] && [ "$ppd" = "$PPDS/$QUEUE.ppd" ] && continue
        if /usr/bin/grep -Fq "$BASE" "$ppd"; then
            printf '打印队列 %s 仍在使用此驱动，未删除任何内容。请先在系统设置中处理该队列。\n' "$(basename "$ppd" .ppd)"
            exit 1
        else
            result=$?
            [ "$result" = 1 ] || { echo '无法检查其他队列的驱动引用，未删除任何内容。'; exit 1; }
        fi
    done
fi

if [ "$HAS_QUEUE" = yes ]; then
    /usr/sbin/lpadmin -x "$QUEUE" || { echo '移除打印队列失败，驱动文件已保留。'; exit 1; }
    echo '已删除 HP1020_SMB 打印队列及其未完成的打印任务。'
fi
if [ -d "$BASE" ]; then
    /bin/rm -rf "$BASE" || { echo '驱动文件未能完整删除，请检查目录权限后重试。'; exit 1; }
    echo '已删除 hp-legacy-mac 驱动文件。需要时可重新安装。'
elif [ "$HAS_QUEUE" = no ]; then
    echo '未发现本工具的打印队列或驱动，无需删除。'
else
    echo '驱动目录已不存在，无需删除驱动文件。'
fi
