# Local CLI Command Templates

Starter must verify the installed CLI help before using these shapes.
Replace `<ROOT>` with the absolute project root and keep one fresh session per iteration.

## Codex

```text
codex exec -C "<ROOT>" --sandbox workspace-write "Read loop/PROMPT.md completely and execute exactly one iteration."
```

If local policy requires approvals, do not add bypass flags.

## Claude

```text
claude -p --permission-mode acceptEdits "Read loop/PROMPT.md completely and execute exactly one iteration."
```

Run with the project root as the working directory. Never use bypassPermissions by default.

## Gemini

```text
gemini --approval-mode auto_edit -p "Read loop/PROMPT.md completely and execute exactly one iteration."
```

Run with the project root as the working directory. Never use `--yolo` by default.

## agy

```text
agy --print --mode accept-edits "Read loop/PROMPT.md completely and execute exactly one iteration."
```

Run with the project root as the working directory. Never use `--dangerously-skip-permissions` by default.
