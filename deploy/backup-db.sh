#!/usr/bin/env bash
# 只备份 SQLite 库文件（.db），不打包 materials / 截图 / 日志。
# 用法: bash deploy/backup-db.sh
# 备份目录默认在仓库外: ../finance-ai-db-backups/<YYYYMMDDTHHMMSS>/
# 覆盖路径: FINANCE_AI_DB_BACKUP_DIR；保留份数: FINANCE_AI_DB_BACKUP_KEEP（默认 14）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KEEP="${FINANCE_AI_DB_BACKUP_KEEP:-14}"
BASE="${FINANCE_AI_DB_BACKUP_DIR:-$ROOT/../finance-ai-db-backups}"
STAMP="$(date +%Y%m%dT%H%M%S)"
DEST="$BASE/$STAMP"

DB_NAMES=(
  wework_external.db
  rag.db
  external_groups.db
)

pick_python() {
  local cand
  if [[ -n "${FINANCE_AI_BACKUP_PYTHON:-}" ]]; then
    echo "$FINANCE_AI_BACKUP_PYTHON"
    return 0
  fi
  for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import sqlite3" >/dev/null 2>&1; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

backup_one() {
  local src="$1"
  local dest="$2"
  local py
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$src" ".backup '$dest'"
    return
  fi
  if py="$(pick_python)"; then
    "$py" - "$src" "$dest" <<'PY'
import sqlite3
import sys

src, dest = sys.argv[1], sys.argv[2]
source = sqlite3.connect(src)
target = sqlite3.connect(dest)
try:
    source.backup(target)
finally:
    target.close()
    source.close()
PY
    return
  fi
  echo "错误: 需要 sqlite3 或 python3 才能备份 $src" >&2
  return 1
}

backed=0
mkdir -p "$DEST"

for name in "${DB_NAMES[@]}"; do
  src="$ROOT/data/$name"
  if [[ ! -f "$src" ]]; then
    echo "跳过: 不存在 $src"
    continue
  fi
  echo "备份 $src -> $DEST/$name"
  backup_one "$src" "$DEST/$name"
  backed=$((backed + 1))
done

if [[ "$backed" -eq 0 ]]; then
  echo "没有可备份的 .db，跳过"
  rmdir "$DEST" 2>/dev/null || true
else
  echo "已备份 ${backed} 个库文件: $DEST"
fi

mkdir -p "$BASE"
# 时间戳目录名可按字典序排，只保留最近 KEEP 份
shopt -s nullglob
old_dirs=("$BASE"/*/)
names=()
for d in "${old_dirs[@]}"; do
  names+=("$(basename "$d")")
done
if [[ "${#names[@]}" -gt 0 ]]; then
  IFS=$'\n' sorted=($(printf '%s\n' "${names[@]}" | sort -r))
  unset IFS
  if [[ "${#sorted[@]}" -gt "$KEEP" ]]; then
    for old in "${sorted[@]:$KEEP}"; do
      echo "删除过期备份: $BASE/$old"
      rm -rf "$BASE/$old"
    done
  fi
fi
