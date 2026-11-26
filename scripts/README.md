# Backup and restore

The public backup script is a reconstructed, generalized reference implementation of the established local workflow, not a byte-identical copy of a private installed script. It has not yet been executed as published. Use PostgreSQL 17 client tools and a private local configuration. Run with bash.

1. Copy backup.env.example to backup.env and fill in the project reference, session pooler hostname and local destination.
2. Store the database password only in a local .pgpass file with mode 600 (host:port:database:user:password). Do not commit it.
3. Review the script and run bash -n backup.sh, then bash backup.sh.
4. Verify the SHA256SUMS.txt checks and copy the completed folder or archive to independent storage.

TLS require encrypts the connection but does not verify server identity. Prefer verify-full with the correct CA configuration. The native custom archive is compressed but not encrypted; protect its contents and use encrypted storage if necessary. Keep weekly backups for four weeks, monthly backups for six months and test restores quarterly; back up before structural and bulk changes.

For a restore, use an isolated PostgreSQL 17 database and explicitly specify local host, port and database. Recreate required global roles before restoring ACLs and policies (e.g. pogo_reader NOLOGIN, plus the standard Supabase roles where missing). Never restore over production for a test. Use pg_restore --single-transaction --exit-on-error and verify counts, constraints, functions, RLS and integrity independently. Archive readability and checksums are not substitutes for a real restore. Schema-scoped backups do not cover global roles, platform configuration, Auth or Storage. No automatic deletion or upload is implemented.
