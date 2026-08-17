#!/bin/bash
# ============================================================
# netfx48-deploy — 一键部署 .NET Framework 4.8 到任意 Wine/Proton 前缀
#
# 用法:
#   ./deploy.sh <前缀路径>                  # 例如 ./deploy.sh ~/.proton_pfx/pfx
#   ./deploy.sh ~/Games/pfx --wine /usr/bin/wine
#   ./deploy.sh ~/Games/pfx --mono-version 9.4.0
#
# 可选参数:
#   --wine <路径>          指定 wine 可执行文件（默认自动检测）
#   --mono-version <版本>  指定该前缀所用 wine 自带的 wine-mono 版本
#                          （用于防覆盖标记，默认自动检测，检测不到用 11.2.0）
#   -y / --yes             跳过确认提示
#
# 说明:
#   - 会备份原 system.reg / user.reg 为 *.netfx48bak
#   - 原 Microsoft.NET 目录会改名为 Microsoft.NET.mono-bak-<时间戳>
#   - 幂等：重复执行安全
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES_DIR="$SCRIPT_DIR/files"
REG_FILE="$SCRIPT_DIR/registry/netfx.reg"
PFX=""
WINE_ARG=""
MONO_ARG=""
YES=0

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --wine) WINE_ARG="$2"; shift 2 ;;
    --mono-version) MONO_ARG="$2"; shift 2 ;;
    -y|--yes) YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) PFX="$1"; shift ;;
  esac
done

if [ -z "$PFX" ] || [ ! -d "$PFX/drive_c/windows" ]; then
  echo "错误: 请提供一个有效的 wine 前缀路径（需包含 drive_c/windows）"
  echo
  usage
  exit 1
fi
PFX="$(cd "$PFX" && pwd)"

[ -f "$REG_FILE" ] || { echo "错误: 找不到注册表文件 $REG_FILE"; exit 1; }
[ -d "$FILES_DIR/Microsoft.NET" ] || { echo "错误: 找不到框架文件目录 $FILES_DIR/Microsoft.NET"; exit 1; }

# ---------- 检测前缀所属的 wine 构建 ----------
# 统计前缀里所有 DLL 软链指向的 wine 构建，选占比最高的那个
# （前缀可能被多个 proton 版本碰过，软链指向会混着来）
if [ -n "$WINE_ARG" ]; then
  WINE_BIN="$WINE_ARG"
  WINE_BASE="$(dirname "$(readlink -f "$WINE_ARG")")"
else
  WINE_BASE=$(find "$PFX/drive_c/windows/system32" -maxdepth 1 -type l -name '*.dll' \
    -exec readlink -f {} \; 2>/dev/null \
    | sed -E 's#/(lib|lib64)/wine/.*##' \
    | sort | uniq -c | sort -rn | head -1 | sed 's/^ *[0-9]* *//')
  if [ -z "$WINE_BASE" ] || [ ! -x "$WINE_BASE/bin/wine" ]; then
    if command -v wine >/dev/null 2>&1; then
      WINE_BASE="$(dirname "$(readlink -f "$(command -v wine)")")"
    else
      echo "错误: 找不到 wine，请用 --wine 指定"; exit 1
    fi
  fi
  WINE_BIN="$WINE_BASE/bin/wine"
fi
WINESERVER_BIN="$WINE_BASE/wineserver"

# ---------- 检测该 wine 自带的 wine-mono 版本（防覆盖标记用） ----------
detect_mono_ver() {
  [ -n "$MONO_ARG" ] && { echo "$MONO_ARG"; return 0; }
  local v
  v=$(ls "$WINE_BASE/../share/wine/mono" 2>/dev/null | grep -oE 'wine-mono-[0-9.]+' | head -1 | sed 's/wine-mono-//')
  [ -n "$v" ] && { echo "$v"; return 0; }
  for d in /usr/share/wine/mono /opt/wine/mono; do
    v=$(ls "$d" 2>/dev/null | grep -oE 'wine-mono-[0-9.]+' | head -1 | sed 's/wine-mono-//')
    [ -n "$v" ] && { echo "$v"; return 0; }
  done
  echo "11.2.0"   # 兜底（proton-cachyos 自带版本）
}
MONO_VER=$(detect_mono_ver)

echo "=================================================="
echo " .NET Framework 4.8 一键部署"
echo "=================================================="
echo "  前缀:     $PFX"
echo "  wine:     $WINE_BIN"
echo "  mono标记: $MONO_VER"
echo

if [ "$YES" != "1" ]; then
  printf "确认部署？(y/N) "
  read -r ans
  case "$ans" in
    y|Y|yes) ;;
    *) echo "已取消"; exit 0 ;;
  esac
fi

TS=$(date +%Y%m%d%H%M%S)

# [1] 停止该前缀的 wineserver（改注册表文件前必须）
echo "[1/6] 停止 wineserver..."
WINEPREFIX="$PFX" "$WINESERVER_BIN" -k 2>/dev/null || true
sleep 1

# [2] 备份注册表
echo "[2/6] 备份注册表..."
cp -a "$PFX/system.reg" "$PFX/system.reg.netfx48bak" 2>/dev/null || true
cp -a "$PFX/user.reg"  "$PFX/user.reg.netfx48bak"  2>/dev/null || true

# [3] 移走旧的 Microsoft.NET（Wine Mono 残留）
echo "[3/6] 处理旧 Microsoft.NET..."
if [ -e "$PFX/drive_c/windows/Microsoft.NET" ]; then
  mv "$PFX/drive_c/windows/Microsoft.NET" "$PFX/drive_c/windows/Microsoft.NET.mono-bak-$TS"
  echo "      旧目录已备份为 Microsoft.NET.mono-bak-$TS"
fi

# [4] 复制框架文件
echo "[4/6] 复制框架文件..."
cp -a "$FILES_DIR/Microsoft.NET" "$PFX/drive_c/windows/Microsoft.NET"
mkdir -p "$PFX/drive_c/windows/system32" "$PFX/drive_c/windows/syswow64"
for f in "$FILES_DIR"/system32/*; do
  [ -f "$f" ] || continue
  rm -f "$PFX/drive_c/windows/system32/$(basename "$f")"
  cp -a "$f" "$PFX/drive_c/windows/system32/"
done
for f in "$FILES_DIR"/syswow64/*; do
  [ -f "$f" ] || continue
  rm -f "$PFX/drive_c/windows/syswow64/$(basename "$f")"
  cp -a "$f" "$PFX/drive_c/windows/syswow64/"
done

# [5] 合并注册表：先删掉目标里旧的 .NET 键，再写入打包的键
echo "[5/6] 合并注册表..."
awk '
  /^\[/ { skip = (index($0,"[Software")==1 && (index($0,"NET Framework Setup")>0 || index($0,".NETFramework")>0)) }
  { if (!skip) print }
' "$PFX/system.reg" > "$PFX/system.reg.new"
printf '\n' >> "$PFX/system.reg.new"
cat "$REG_FILE" >> "$PFX/system.reg.new"
mv "$PFX/system.reg.new" "$PFX/system.reg"

# [6] 设置覆盖与防覆盖标记
echo "[6/6] 设置 mscoree=native + Wine\\Mono 标记..."
export WINEPREFIX="$PFX"
"$WINE_BIN" reg add 'HKCU\Software\Wine\DllOverrides' /v mscoree /d native /f >/dev/null 2>&1 \
  || echo "      警告: 设置 mscoree 覆盖失败，请手动执行: wine reg add 'HKCU\\Software\\Wine\\DllOverrides' /v mscoree /d native /f"
"$WINE_BIN" reg add 'HKLM\Software\Wine\Mono' /v Version /t REG_SZ /d "$MONO_VER" /f >/dev/null 2>&1 \
  || echo "      警告: 设置 Wine\\Mono 标记失败（不影响使用，但前缀更新时可能被覆盖）"

echo
echo "=================================================="
echo " 部署完成！"
echo "=================================================="
echo "  验证方法："
echo "    WINEPREFIX=\"$PFX\" wine 'C:\\windows\\Microsoft.NET\\Framework\\v4.0.30319\\csc.exe' /help"
echo "  （能打印出 C# 编译器版本信息即为成功）"
echo
echo "  如需撤销："
echo "    注册表: 恢复 system.reg.netfx48bak / user.reg.netfx48bak"
echo "    文件:   删除 Microsoft.NET，把 Microsoft.NET.mono-bak-$TS 改回来"
