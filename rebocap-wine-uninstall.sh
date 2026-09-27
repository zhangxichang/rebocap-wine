#!/usr/bin/env bash
# rebocap-wine-uninstall.sh
# ReboCap Wine setupapi 兼容补丁 —— 卸载（install 的反向）
#
# 职责：
#   1. 定位并校验程序环境（prefix / wine）；
#   2. 还原 KnownDLLs\setupapi = "setupapi.dll"；
#   3. 删除 HKCU\Software\Wine\DllOverrides\setupapi；
#   4. 删除运行期由 DLL 创建的 REBORNRX 整键（含 Device Parameters\PortName）。
# 不删除文件；需要时请手动删除 setupapi.dll 与本脚本、README。
#
# 用法：
#   ./rebocap-wine-uninstall.sh [--prefix <prefix>] [--wine <wine 路径>]
#
# 生效时机：与安装相同，需要 wine 会话重启（或 wineserver -k）。

set -u

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"
APP_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

PREFIX_OVERRIDE=""
WINE_OVERRIDE=""

usage() {
    cat <<'EOF'
用法: ./rebocap-wine-uninstall.sh [选项]

选项:
  --prefix <路径>   显式指定 wine prefix（默认自动定位）
  --wine <路径>     显式指定 wine 可执行文件（默认自动查找）
  -h, --help        显示本帮助
EOF
}

log()  { printf '[uninstall] %s\n' "$*"; }
die()  { printf '[uninstall] 错误: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) [ $# -ge 2 ] || die "--prefix 缺少参数"; PREFIX_OVERRIDE="$2"; shift 2 ;;
        --wine)   [ $# -ge 2 ] || die "--wine 缺少参数";   WINE_OVERRIDE="$2";   shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "未知参数: $1（-h 查看帮助）" ;;
    esac
done

# ---------------------------------------------------------------- 环境定位

find_prefix() {
    if [ -n "$PREFIX_OVERRIDE" ]; then
        printf '%s\n' "$PREFIX_OVERRIDE"; return 0
    fi
    if [ -n "${WINEPREFIX:-}" ]; then
        case "$APP_DIR/" in
            "$WINEPREFIX"/*) printf '%s\n' "$WINEPREFIX"; return 0 ;;
        esac
    fi
    local d="$APP_DIR"
    while [ "$d" != "/" ]; do
        if [ -f "$d/system.reg" ] && [ -d "$d/drive_c" ]; then
            printf '%s\n' "$d"; return 0
        fi
        d="$(dirname "$d")"
    done
    local logical="$SCRIPT_PATH"
    case "$logical" in
        /*) : ;;
        *) logical="$PWD/$logical" ;;
    esac
    d="$(dirname "$logical")"
    while [ "$d" != "/" ] && [ -n "$d" ]; do
        if [ -f "$d/system.reg" ] && [ -d "$d/drive_c" ]; then
            printf '%s\n' "$d"; return 0
        fi
        d="$(dirname "$d")"
    done
    return 1
}

find_wine() {
    if [ -n "$WINE_OVERRIDE" ]; then
        printf '%s\n' "$WINE_OVERRIDE"; return 0
    fi
    if [ -n "${WINE:-}" ] && [ -x "${WINE}" ]; then
        printf '%s\n' "${WINE}"; return 0
    fi
    if [ -f "$PREFIX/bottle.yml" ]; then
        local runner
        runner="$(sed -n 's/^Runner: *//p' "$PREFIX/bottle.yml" 2>/dev/null | tr -d '"' | head -1)"
        if [ -n "$runner" ] && [ -x "$HOME/.local/share/bottles/runners/$runner/bin/wine" ]; then
            printf '%s\n' "$HOME/.local/share/bottles/runners/$runner/bin/wine"; return 0
        fi
        if [ -n "$runner" ] && [ -x "$HOME/.var/app/com.usebottles.bottles/data/bottles/runners/$runner/bin/wine" ]; then
            printf '%s\n' "$HOME/.var/app/com.usebottles.bottles/data/bottles/runners/$runner/bin/wine"; return 0
        fi
    fi
    local path_wine
    path_wine="$(command -v wine 2>/dev/null || true)"
    if [ -n "$path_wine" ]; then
        printf '%s\n' "$path_wine"; return 0
    fi
    return 1
}

# ---------------------------------------------------------------- 主流程

log "应用目录: $APP_DIR"
[ -f "$APP_DIR/rebocap.exe" ] || log "提示: 本目录未找到 rebocap.exe（继续执行）"

PREFIX="$(find_prefix)" || die "无法定位 wine prefix（可用 --prefix 显式指定）"
[ -f "$PREFIX/system.reg" ] && [ -d "$PREFIX/drive_c" ] || die "prefix 校验失败: $PREFIX"
log "Wine prefix: $PREFIX"

WINE="$(find_wine)" || die "无法定位 wine（可用 --wine 显式指定）"
[ -x "$WINE" ] || die "wine 不可执行: $WINE"
WINESERVER="$(dirname "$WINE")/wineserver"
log "Wine: $WINE"

run_wine() {
    WINEPREFIX="$PREFIX" "$WINE" "$@"
}

KNOWN_KEY='HKLM\System\CurrentControlSet\Control\Session Manager\KnownDLLs'
DLLOVERRIDE_KEY='HKCU\Software\Wine\DllOverrides'
DEVICE_KEY='HKLM\SYSTEM\CurrentControlSet\Enum\USB\VID_248A&PID_8002\REBORNRX'

# 1) 还原 KnownDLLs 表项（Wine 默认值: setupapi.dll）
log "还原 KnownDLLs\\setupapi ..."
run_wine reg add "$KNOWN_KEY" /v setupapi /d 'setupapi.dll' /f >/dev/null 2>&1 || true

if ! run_wine reg query "$KNOWN_KEY" /v setupapi 2>/dev/null | grep -q 'setupapi.dll'; then
    die "KnownDLLs\\setupapi 还原失败（可手动执行: wine reg add \"$KNOWN_KEY\" /v setupapi /d setupapi.dll /f）"
fi

# 2) 删除 DllOverrides\setupapi（值不存在不算错误）
log "删除 DllOverrides\\setupapi ..."
run_wine reg delete "$DLLOVERRIDE_KEY" /v setupapi /f >/dev/null 2>&1 || true

if run_wine reg query "$DLLOVERRIDE_KEY" /v setupapi >/dev/null 2>&1; then
    die "DllOverrides\\setupapi 仍然存在（可手动执行: wine reg delete \"$DLLOVERRIDE_KEY\" /v setupapi /f）"
fi

# 3) 删除运行期创建的设备键（不存在不算错误）
log "删除设备键 REBORNRX ..."
run_wine reg delete "$DEVICE_KEY" /f >/dev/null 2>&1 || true

cat <<EOF

[uninstall] 完成。

  - KnownDLLs\\setupapi 已还原
  - DllOverrides\\setupapi 已删除
  - 设备键 REBORNRX 已删除（如存在）

  生效时机（二选一）：
    * 关闭该 prefix 里所有程序后重新启动（推荐）
    * 或执行立即结束会话: WINEPREFIX="$PREFIX" "$WINESERVER" -k

  彻底移除请手动删除: setupapi.dll、本脚本与 README。
EOF
