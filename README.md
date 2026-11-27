# Pokémon GO – Shared AI-assisted database

An unofficial, independent project exploring how multiple AI-assisted specialist chats can share a consistent Pokémon GO inventory and coordinate game-related decisions through PostgreSQL and Supabase.

## Project goals

- Maintain a single reliable inventory with stable individual Pokémon identities.
- Preserve field-level provenance, verification and historical observations.
- Prevent accidental duplicate operations and stale updates.
- Keep facts, recommendations, plans and completed game actions separate.
- Extend the shared database only where multiple workflows benefit.

## Current baseline

Schema **0.3.0**, technical contract **0.4.0**, architecture milestone **R2.1**. The original deployment passed a small inventory pilot. The public reconstruction intentionally starts in `building`, with no player inventory and no automatic release.

## Documentation

- [Architecture](docs/architecture.md)
- [Project context](docs/project-context.md)
- [Data model](docs/data-model.md)
- [Technical contract](docs/technical-contract.md)
- [Development workflow](docs/development-workflow.md)
- [Architecture decisions](docs/decisions/README.md)
- [Changelog](CHANGELOG.md)
- [Public migration history](supabase/migrations/README.md)
- [Schema reconstruction](supabase/schema.sql)

## Scope and safety

This is a reference implementation, not a hosted service or a production-ready multi-user application. It uses a dedicated Supabase project, controlled SQL functions, backups and manual deployment. Do not connect a privileged AI integration to sensitive or unrelated production databases. Never commit credentials, player records or database dumps. Public migrations are sanitized historical editions, not the original deployment ledger.

Pokémon GO and Pokémon are trademarks of their respective owners. This project is not affiliated with Niantic, Scopely, Nintendo, Game Freak or The Pokémon Company.
