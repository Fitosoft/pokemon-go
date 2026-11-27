# Project context — schema 0.3.0, contract 0.4.0

A stable chat identifier plus shared bootstrap instructions replaces duplicated role prompts. Runtime configuration is stored in the database, not in this repository. Private role descriptions and player strategy are intentionally excluded.

## Tables

- `pogo_meta.project_chats`: versioned chat identity, purpose, responsibilities, boundaries, initial tasks and status (planned, active, temporary, retired).
- `pogo_meta.project_config`: versioned titled text keyed by configuration name.

Both retain historical revisions, record actor/reason/operation key, and enforce one current revision per key. RLS and reader SELECT policies apply. Statement-level guards reject ordinary direct writes, not privileged administrative bypass.

## API

```sql
SELECT pogo_meta.get_chat_context('01');
```

The result contains system_state, technical_contract, own_chat, project_chats, project_config, loaded_at, available_modules and unavailable_modules. Unknown or retired identities and incomplete configuration fail closed. Planned identities can initialize. Reload before relevant work, not only on first use; do not repeat completed initial tasks.

Required configuration keys: collaboration_rules, responsibility_matrix, initialization_matrix, playing_strategy, player_preferences, strategic_guidelines, decision_rules, research_rules, communication_rules. The two matrices distinguish ongoing ownership from initial definition and population.

```sql
pogo_meta.publish_context_revision(
  p_kind text, p_key text, p_expected integer,
  p_operation_key text, p_actor text, p_reason text, p_data jsonb
)
```

Kind chat or config; expected 0 for creation, otherwise current revision. Actor 00 or 99 is an organizational label, not authentication. Supply complete string-valued payload: chat requires display_name, status, purpose, responsibilities, boundaries, initial_tasks; config requires title, content. Identical retries return the original result reference; changed payloads and stale revisions fail. A transaction advisory lock serializes revisions. Never bypass guards. Major role changes require owner approval.

## Fresh installation

Public reconstruction stays building and contains no private configuration. Populate local roles and all nine keys only after reviewing the schema and explicitly authorizing pilot writes; publish the local full contract before release. The reader can inspect tables but cannot execute the context or publication functions. The original deployment passed sequential revision, retry, stale/conflicting request, direct update rejection, unknown identity and refreshed context checks; true concurrent tests remain deferred.

## Shared mailbox

The context now includes pending messages, tasks and results. See [Shared mailbox](mailbox.md). No automatic chat activation.
