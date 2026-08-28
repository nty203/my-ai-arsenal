# Autonomous Development Target Registry

The installer replaces this placeholder with targets discovered from the repository.
Each iteration must choose exactly one key.

| key | path | quality gates |
|---|---|---|
| `project` | `.` | detected existing commands only |

Rules:
- Never invent a validation command that does not exist.
- Never register deploy/publish/payment commands as Quality Gates.
- Shared changes require validation of known consumers when practical.
