# Development workflow

## One main branch, manual deployment

1. Collect specialist requirements and prioritize shared information.
2. Design a small migration and review its impact.
3. Back up the deployed application schemas.
4. Commit the public-safe SQL and corresponding documentation to main before deployment.
5. Apply the actual instance-specific migration manually using the technical administration connection.
6. Verify schema, constraints, security, data integrity and contract; publish the matching runtime contract.
7. Record the deployed status and any differences from the public edition in the changelog.

Never automatically apply the public historical files to the existing database. They are sanitized reference editions; deployed SQL remains in the Supabase ledger. New installations need local project binding, full contract publication and validation before pilot or release.

## Commit conventions

Write English imperative subjects, start with a capital letter, avoid a trailing period and prefer roughly 50 characters. Separate the body with a blank line and explain what and why. Use atomic commits; no mandatory type prefixes. Avoid rewriting published history. Do not add CI/CD or extra branches by default.

## Public repository review

Exclude credentials, project references, connection strings, inventory data, personal assessments, real IDs and private backups. Review the full staged content, not only file names or .gitignore. Record intentional sanitization. Git history is public and persistent.

## Operational checks

Confirm backups, verify exact project, use controlled functions, check read permissions for new tables, confirm rollback on failure, and re-read actual state. No production writes from examples or test fixtures.
