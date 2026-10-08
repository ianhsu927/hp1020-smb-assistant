#!/bin/sh
set -eu
[ "$(id -u)" = 0 ] || { echo '需要管理员权限。'; exit 1; }
[ "$(uname -m)" = arm64 ] || { echo '仅支持 Apple 芯片。'; exit 1; }
BUNDLE=$1
URI=$2
AUTH=$3
BASE=/Library/Printers/hp-legacy-mac
QUEUE=HP1020_SMB
FILTER=$BASE/hp1020-smb-filter
case "$URI" in smb://*) ;; *) echo '无效的 SMB 地址'; exit 1;; esac
[ -f "$BUNDLE/ppd/HP-LaserJet_1020.ppd.gz" ] && [ -x "$BUNDLE/bin/gs" ] && [ -x "$BUNDLE/bin/foo2zjs" ] || { echo '驱动资源不完整'; exit 1; }
if /usr/bin/lpstat -p "$QUEUE" >/dev/null 2>&1; then
    echo 'HP1020_SMB 队列已存在。请先在系统设置中移除这个队列，再重新安装。'; exit 1
fi
if [ -e "$BASE" ]; then
    echo '发现已安装的 hp-legacy-mac 驱动。为避免覆盖，停止安装。'; exit 1
fi
WORK=$(/usr/bin/mktemp -d)
COPIED=no
SUCCESS=no
cleanup() {
    /bin/rm -rf "$WORK"
    if [ "$SUCCESS" != yes ] && [ "$COPIED" = yes ]; then
        /usr/sbin/lpadmin -x "$QUEUE" 2>/dev/null || true
        /bin/rm -rf "$BASE"
        echo '安装未完成，已回退本次新增的驱动文件。'
    fi
}
trap cleanup EXIT
/bin/cp -R "$BUNDLE" "$BASE"
COPIED=yes
/usr/sbin/chown -R root:wheel "$BASE"
/bin/chmod -R go-w "$BASE"
/bin/chmod -R a+rX "$BASE"
/bin/cat > "$FILTER" <<'FILTEREOF'
#!/bin/sh
BASE=/Library/Printers/hp-legacy-mac
export PATH="$BASE/bin:/usr/bin:/bin"
export GS_LIB="$BASE/share/ghostscript/Resource/Init:$BASE/share/ghostscript/lib:$BASE/share/ghostscript/Resource/Font:$BASE/share/ghostscript/fonts"
COPIES=${4:-1}
case "$COPIES" in ''|*[!0-9]*) COPIES=1;; esac
if [ -n "${6:-}" ]; then
    exec "$BASE/bin/foo2zjs-wrapper" -z1 -P -L0 -p a4 -n "$COPIES" -b "$BASE/bin/gs" < "$6"
else
    exec "$BASE/bin/foo2zjs-wrapper" -z1 -P -L0 -p a4 -n "$COPIES" -b "$BASE/bin/gs"
fi
FILTEREOF
/bin/chmod 755 "$FILTER"
/usr/bin/gunzip -c "$BASE/ppd/HP-LaserJet_1020.ppd.gz" | /usr/bin/sed '/^\*cupsFilter/d' > "$WORK/1020.ppd"
printf '*cupsFilter: "application/vnd.cups-pdf 0 /Library/Printers/hp-legacy-mac/hp1020-smb-filter"\n' >> "$WORK/1020.ppd"
/usr/bin/sed -i '' 's/^\*DefaultPageSize:.*/\*DefaultPageSize: A4/;s/^\*DefaultPageRegion:.*/\*DefaultPageRegion: A4/;s/^\*DefaultImageableArea:.*/\*DefaultImageableArea: A4/;s/^\*DefaultPaperDimension:.*/\*DefaultPaperDimension: A4/' "$WORK/1020.ppd"
# Verify the installed ARM64 bundle before creating the queue.
"$BASE/bin/gs" --version
if [ "$AUTH" = yes ]; then
    /usr/sbin/lpadmin -p "$QUEUE" -v "$URI" -P "$WORK/1020.ppd" -E -o auth-info-required=username,password -o printer-error-policy=stop-printer
else
    /usr/sbin/lpadmin -p "$QUEUE" -v "$URI" -P "$WORK/1020.ppd" -E -o printer-error-policy=stop-printer
fi
SUCCESS=yes
printf '已添加 HP1020_SMB。\n当前版本固定 A4、黑白打印；其他纸张及高级选项尚未实现。\n'
