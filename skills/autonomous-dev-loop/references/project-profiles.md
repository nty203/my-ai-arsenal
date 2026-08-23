# Project profiles

Choose commands that already exist in the target repository.
Run them from the project root unless the command explicitly changes directory.

## Frontend

Typical evidence:

- package-manager install state is valid
- lint or type-check passes
- non-watch test command passes
- production build passes
- the changed screen is opened and visually checked

Example QUALITY_COMMANDS:

`@('npm run lint', 'npm test -- --run', 'npm run build')`

Adjust test flags to the repository's actual runner. Do not assume Vitest, Jest, or Playwright.

## Backend/API

Python examples:

`@('python -m pytest', 'python -m ruff check .')`

Node examples:

`@('npm run lint', 'npm test', 'npm run build')`

Also verify success, error, boundary inputs, schema or contract compatibility, and migrations.

## Full-stack

Run each workspace's existing checks and then test one real frontend-to-API flow.
Include a failed API response so the user-facing error path is verified.

## Game

Run the engine's headless test or export command when available.
Verify input, state transitions, persistence, and one representative scene visually.
Keep game-specific commands in env.ps1; keep loop.ps1 generic.

## CLI and automation

Verify help, success, invalid input, non-zero failure exit, idempotent rerun, and readable logs.
For schedulers, reproduce the restricted PATH or service-account environment.

## Documentation and data

Verify links, schemas, calculations, samples, and generated output.
Use reproducible scripts instead of visual inspection alone.

## Safe starting values

- MAX_LOOPS: 1 for the first pilot
- AGENT_TIMEOUT_SECONDS: 900 to 1800
- MAX_RETRIES: 1 or 2
- RETRY_BASE_SECONDS: 10
- MAX_CONSECUTIVE_FAILURES: 2 or 3
- ALLOW_AGENT_COMMIT: true only when the prompt stages scoped files
- ALLOW_PUSH_OR_DEPLOY: false by default
