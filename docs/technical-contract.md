# Public technical contract reference — 0.3.2

This is a generalized reference, not the runtime contract of any particular installation. Configure and publish the local contract in Supabase before enabling writes.

```sql
SELECT s.project_ref, s.schema_version, s.contract_version,
       s.readiness, c.body
FROM pogo_meta.system_state s
JOIN pogo_meta.technical_contracts c ON c.version = s.contract_version;
```

Verify the intended project and actual schema. Stop writes if the contract or connection is unavailable. Runtime readiness is building, pilot, released or maintenance. Only pilot and released permit controlled writes; local approval is still required.

## Inventory API

```sql
pogo.write_pokemon(p_key text, p_id uuid, p_expected bigint,
                   p_fields jsonb, p_evidence jsonb, p_batch jsonb default null)
pogo.record_observation(p_key text, p_id uuid, p_expected bigint,
                        p_field text, p_value jsonb, p_evidence jsonb)
```

Create with NULL id and expected version; update with the individual UUID and current row version. Supply only intended fields and matching evidence keys. Evidence includes source_type (user, screenshot, scanner, legacy_chat, derived, other, test), source_ref, verification_status (unverified, verified, inferred; conflicting for alternatives), and optional observed_at and verified_at timestamps. Verified requires verified_at. Never fabricate timestamps or values. Do not overwrite a stronger observation without deliberate review.

The optional import object contains batch_key, source_type, source_ref and source_item_key. Do not deduplicate individuals by species, CP or IVs. Stable operation keys must survive retries. The same key and JSONB payload return the stored result while writes are enabled; changed payloads are rejected. If execution is uncertain, read operations first. Reload records after version conflicts.

Do not directly write, delete or truncate application inventory tables. The guards use PG_CONTEXT and are not an authorization boundary against administrators. Metadata and structural changes are reserved for technical administration. Only implemented modules may be used. Keep facts separate from assessments and plans. Preserve UUID across permanent evolution; clear unknown newly changed attributes; do not overwrite regular stats with temporary transformation stats.

## Mobile access

Grant the dedicated reader SELECT only, with appropriate RLS policies for every new table, and no write-function execution. Verify privileges. Set credentials privately. Global roles must be recreated before restoring schema ACLs and policies.

## Backup and release

Take an independent native backup before structural or bulk changes. Verify migration results and runtime contract consistency before release. Never expose credentials or player data in Git. Expensive true multi-session tests were deferred in the reference project; this is not a concurrency certification.
