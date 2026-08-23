# Karpathy LLM Wiki adaptation

Source reference: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f

Adopt these project-memory principles:
- immutable raw sources
- LLM-maintained persistent Markdown wiki
- schema/instructions as the maintenance contract
- `index.md` for content navigation
- `log.md` for chronological append-only history
- ingest/query/lint operations compound knowledge instead of rediscovering it

For development projects, compile intake, plans, important decisions, domain concepts, implementation learnings, and reusable verification findings into the project Wiki.
Do not copy the source text wholesale; instantiate the pattern to the current project's needs.
