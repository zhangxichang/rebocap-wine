#!/usr/bin/env bash
# rebocap-wine-install.sh
# ReboCap Wine setupapi 兼容补丁 —— 安装（一次性）
#
# 职责（只有三件）：
#   1. 定位并校验程序环境（prefix / wine）；
#   2. 删除 KnownDLLs 中的 setupapi 表项；
#   3. 设置 HKCU\Software\Wine\DllOverrides\setupapi = native,builtin。
# 不探测 COM、不写 PortName、不重启会话、不启动程序。
#
# 用法：
#   ./rebocap-wine-install.sh [--prefix <prefix>] [--wine <wine 路径>]
#
# 生效时机（二选一）：
#   - 关闭该 prefix 里所有程序后重新启动（wineserver 空闲退出后配置才会重读）；
#   - 或执行 `wineserver -k` 立即结束会话（会强制关闭瓶内所有程序，慎用）。

set -u

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"
APP_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

PREFIX_OVERRIDE=""
WINE_OVERRIDE=""

usage() {
    cat <<'EOF'
用法: ./rebocap-wine-install.sh [选项]

选项:
  --prefix <路径>   显式指定 wine prefix（默认自动定位）
  --wine <路径>     显式指定 wine 可执行文件（默认自动查找）
  -h, --help        显示本帮助

说明:
  - 把 setupapi.dll 放到 rebocap.exe 同目录后再运行本脚本。
  - KnownDLLs 与 DllOverrides 的修改在 wine 会话重启后生效。
EOF
}

log()  { printf '[install] %s\n' "$*"; }
die()  { printf '[install] 错误: %s\n' "$*" >&2; exit 1; }

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
    # 物理路径向上找（解析符号链接）
    local d="$APP_DIR"
    while [ "$d" != "/" ]; do
        if [ -f "$d/system.reg" ] && [ -d "$d/drive_c" ]; then
            printf '%s\n' "$d"; return 0
        fi
        d="$(dirname "$d")"
    done
    # 逻辑路径向上找（不解析符号链接）
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
    # Bottles: 从 bottle.yml 读 Runner
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
[ -f "$APP_DIR/rebocap.exe" ] || die "未找到 rebocap.exe，请把本脚本与 setupapi.dll 放到 rebocap.exe 所在目录"
[ -f "$APP_DIR/setupapi.dll" ] || die "未找到 setupapi.dll，请先把它放到本目录"

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

# 1) 删 KnownDLLs 表项（幂等；值不存在不算错误）
KNOWN_KEY='HKLM\System\CurrentControlSet\Control\Session Manager\KnownDLLs'
log "删除 KnownDLLs\\setupapi ..."
run_wine reg delete "$KNOWN_KEY" /v setupapi /f >/dev/null 2>&1 || true

if run_wine reg query "$KNOWN_KEY" /v setupapi >/dev/null 2>&1; then
    die "KnownDLLs\\setupapi 仍然存在，删除失败（可手动执行: wine reg delete \"$KNOWN_KEY\" /v setupapi /f）"
fi

# 2) 设置 DLL 覆盖：Wine 默认优先内建 setupapi，必须让应用目录的 native 版优先
DLLOVERRIDE_KEY='HKCU\Software\Wine\DllOverrides'
log "设置 DllOverrides\\setupapi = native,builtin ..."
run_wine reg add "$DLLOVERRIDE_KEY" /v setupapi /d 'native,builtin' /f >/dev/null 2>&1 || true

if ! run_wine reg query "$DLLOVERRIDE_KEY" /v setupapi 2>/dev/null | grep -q 'native,builtin'; then
    die "DllOverrides\\setupapi 设置失败（可手动执行: wine reg add \"$DLLOVERRIDE_KEY\" /v setupapi /d native,builtin /f）"
fi

cat <<EOF

[install] 完成。

  - KnownDLLs\\setupapi 已删除
  - DllOverrides\\setupapi = native,builtin 已设置
  - setupapi.dll 已就位: $APP_DIR

  生效时机（二选一）：
    * 关闭该 prefix 里所有程序后重新启动（推荐）
    * 或执行立即结束会话: WINEPREFIX="$PREFIX" "$WINESERVER" -k

  自查:
    WINEPREFIX="$PREFIX" "$WINE" reg query "$KNOWN_KEY" /v setupapi
    （应提示找不到 setupapi 值）
    WINEPREFIX="$PREFIX" "$WINE" reg query "$DLLOVERRIDE_KEY" /v setupapi
    （应显示 native,builtin）

  接收器的 COM 号由 DLL 在运行时处理，USB 插拔无需重跑本脚本。
EOF
