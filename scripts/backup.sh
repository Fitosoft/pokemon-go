#!/usr/bin/env bash
# Public reference implementation, reconstructed from the proven backup workflow.
set -Eeuo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
source ./backup.env
: "${PGHOST:?}" "${PGPORT:?}" "${PGDATABASE:?}" "${PGUSER:?}" "${PGPASSFILE:?}" "${PG_BIN:?}" "${BACKUP_DIR:?}" "${BACKUP_SCHEMAS:?}" "${PROJECT_REF:?}"
[[ "$PGUSER" == "postgres.$PROJECT_REF" ]] || { echo "Unexpected pooler user" >&2; exit 1; }
[[ "${PGSSLMODE:-}" == require || "${PGSSLMODE:-}" == verify-full ]] || { echo "TLS required" >&2; exit 1; }
for cmd in psql pg_dump pg_restore; do [[ -x "$PG_BIN/$cmd" ]] || { echo "Missing $cmd" >&2; exit 1; }; done
read -r -a schemas <<< "$BACKUP_SCHEMAS"
args=()
for schema in "${schemas[@]}"; do
  case "$schema" in pogo|pogo_meta|pogo_poc|pogo_poc_restore) args+=(--schema="$schema");; *) echo "Unexpected schema: $schema" >&2; exit 1;; esac
done
mkdir -p -- "$BACKUP_DIR"
stamp="$(date -u +%Y-%m-%d_%H-%M-%S_UTC)"
final="$BACKUP_DIR/pokemon-go_$stamp"
tmp="$(mktemp -d "$BACKUP_DIR/.pokemon-go-$stamp.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
[[ ! -e "$final" ]] || { echo "Backup destination already exists" >&2; exit 1; }
server="$("$PG_BIN/psql" -X -w -At -v ON_ERROR_STOP=1 -c 'SHOW server_version;')"
client="$("$PG_BIN/pg_dump" --version)"
[[ "$server" == 17.* && "$client" == *" 17."* ]] || { echo "Expected PostgreSQL 17 tools and server; review before changing versions" >&2; exit 1; }
"$PG_BIN/pg_dump" --no-password --format=custom --strict-names "${args[@]}" --file="$tmp/database.backup"
"$PG_BIN/pg_restore" --list "$tmp/database.backup" > "$tmp/archive_contents.txt"
"$PG_BIN/pg_restore" --file=/dev/null "$tmp/database.backup"
printf '%s\n' "project=pokemon-go" "project_ref=$PROJECT_REF" "created_at_utc=$stamp" "server_version=$server" "dump_version=$client" "schemas=$BACKUP_SCHEMAS" "format=postgresql_custom" "archive_read_check=passed" > "$tmp/manifest.txt"
(cd "$tmp" && sha256sum database.backup archive_contents.txt manifest.txt > SHA256SUMS.txt && sha256sum -c SHA256SUMS.txt)
mv -T -- "$tmp" "$final"
echo "Backup complete: $final"
echo "Copy the completed archive to independent storage and verify synchronization."
