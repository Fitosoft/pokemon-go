# Architecture decision records

| ADR | Decision | Status |
|---|---|---|
| 001 | Dedicated Supabase database and private schemas | Accepted |
| 002 | Stable UUID, NULL for unknown, field evidence | Accepted |
| 003 | Idempotent atomic operations and optimistic locking | Accepted |
| 004 | Controlled write functions and accidental-write guards | Accepted |
| 005 | Independent native backup and restore | Accepted |
| 006 | Versioned live contract and readiness gate | Accepted |
| 007 | Separate mobile reader with SELECT policies | Accepted |
| 008 | Public Git repository, manual deployment, no direct integration | Accepted |
| 009 | Prioritize cross-chat data needs | Accepted |
| 010 | Defer expensive parallel tests and optional in-game tags | Accepted |

## Rationale

001–004: Shared facts must survive chat context changes and resist duplicate or stale writes without a separate service. Administrative access remains a known residual risk; context guards are not a privilege boundary.

005: A schema repository cannot recover player data. Native archives are stored outside the database and independently restored periodically. Roles and platform configuration need separate handling.

006: A live versioned contract keeps volatile rules out of fixed chat prompts and gates writes until validation.

007: Mobile browsing should not require administrative credentials.

008: Git records technical changes and reasoning; Supabase retains the live state. Public copies omit private metadata. One main branch and manually applied migrations minimize complexity.

009–010: Implement shared, persistent information before isolated chat conveniences. Retain locking and idempotency, but defer expensive concurrency validation until actual usage warrants it.

## ADR 011 — Centralize project context (Accepted)

Keep only stable bootstrap rules and chat identity in prompts. Store versioned roles, shared rules and ownership matrices in PostgreSQL; retrieve current context before relevant work. Preserve private content outside public Git history. Prioritize a shared mailbox next.
