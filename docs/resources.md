# Resource ledger — schema 0.5.1 / contract 0.6.1

The resource module records observed balances, confirmed movements and unresolved reconciliation separately from planned spending. Catalog entries are stable concrete resource definitions; the ledger does not infer a player's balance from inventory counts or future rewards.

## Tables

- `pogo.resource_catalog`: unique code, type, scope, measure, unit, source and optional period rules.
- `pogo.resource_balances`: one versioned selected balance per catalog entry and period; observation basis, effective time and reconciliation flags.
- `pogo.resource_history`: append-only snapshots and movements, evidence, before/after state, disposition and discrepancy.
- `pogo.resource_operations`: atomic batch payloads, stable operation keys and stored results.

All four use RLS, reader SELECT policies and accidental-write guards. The reader cannot execute write functions. Chat IDs are organizational labels, not authenticated identities.

## Read and write

```sql
SELECT pogo.get_resource_overview();
pogo.write_resource_batch(p_key text,p_actor text,p_entries jsonb)
pogo.publish_resource_catalog(p_key text,p_actor text,p_entries jsonb)
```

The overview includes catalog, balance (NULL until observed), basis_evidence and current_period. Read historical entries separately. Do not treat expired periods as current. A non-NULL selected balance may need reconciliation.

Each batch entry has code, expected (0 for new balance, otherwise current version), event_key, kind (snapshot/movement), integer amount, precision (instant/day/month/year/interval/unknown), source_type, source_ref and verification_status. Add observed_from and observed_to as ISO timestamps with explicit offset, equal for instant; omit both for unknown. Verified entries require verified_at. Optional pokemon_id, related_ref; explicit period_start and period_end for periodic entries. Explicit reconcile_reason requires a verified instant snapshot and confirmed resolution of uncertainty. One entry per resource and period per batch.

Only verified, time-bounded snapshots with clear ordering become selected balances. Confirmed signed nonzero movements apply only after the current balance with known exact timing; earlier-than-basis movements are covered, uncertain ordering is pending. Pending observations are retained, not silently discarded; resolve with a later verified snapshot, explicit reconciliation if timing is unknown. A discrepancy is a difference from the previous selected amount, not a known source of gain/loss. Missing values are omitted; explicit zero is valid. Negative balances are rejected. No automatic replay of ambiguous movements, no automatic period resets. Stable shared event keys prevent repeat events for the same balance/kind; semantic deduplication still requires coordination. A batch is atomic.

## Catalog ownership

Chat 99 maintains definitions, verified shared pools, limits and corrections. Chat 00 may add only clearly identified nonperiodic global item stock entries: category=item, scope_key=global, measure=stock, unit=units, periodic=false, rules empty, code=resource_type in English snake_case. Check existing semantic equivalents first and record source_ref. The API accepts only these additions from 00; existing definitions remain append-only. Other chats report gaps to the resource lead or technical administrator. Catalog entries require code, resource_type, label, category, unit, scope_key, measure, source_ref; optional periodic and rules. Categories currency/item/candy/energy/storage/progress/reward; measures stock/capacity/occupancy/counter/limit/claimable. Pool identifiers must be validated, not inferred from species names.

The optional [starter catalog](../supabase/seeds/resource_catalog.sql) contains 46 generic definitions only. The public reconstruction stays building: authorize a local pilot before seeding. No personal balances, assumed numerical limits or private data are shipped. Actual storage occupancy, capacity, daily counters and unclaimed rewards remain separate. Individual progression and planned actions are not spendable balances.

## Validation

Sequential tests in the reference deployment covered operation retry, duplicate events, late movements, discrepancies, stale version, negative balance, atomic rollback, unknown timing, zero balance, explicit reconciliation, separate periods, direct-write rejection, delegated item creation and delegated pool rejection. Test fixtures were rolled back. True multi-session tests and independent public reconstruction remain deferred. Planned actions, verified game-cost rules, and complete pool mappings are separate future work.
