# Generic autonomous development loop configuration.
# Customize this file per project; reuse loop.ps1 and PROMPT.md unchanged.

$PROJECT_PROFILE = "auto"  # auto | frontend | backend | fullstack | game | cli | docs | custom
$SELECTED_CLI = "agy"      # codex | claude | gemini | agy | custom; keep aligned with AGENT_CMD
$VCS_PREFERENCE = "auto"   # auto | git | svn; use explicit mode only when a project is intentionally nested in another VCS
$AGENT_CMD = 'agy --prompt-file "loop\PROMPT.md"'

# Loop controls
$SLEEP_SECONDS = 5
$MAX_LOOPS = 0
$AGENT_TIMEOUT_SECONDS = 1800
$MAX_RETRIES = 2
$RETRY_BASE_SECONDS = 10
$MAX_CONSECUTIVE_FAILURES = 3

# Commands run by the orchestrator after a successful agent session.
# Add the project's existing test, lint, type-check, and build commands.
$QUALITY_COMMANDS = @()
# Git gets `git diff --check` automatically when this list is empty.
# SVN projects should add their existing project gates here; do not initialize nested Git just for validation.

# Example frontend:
# @('npm run lint', 'npm test -- --run', 'npm run build')
# Example Python backend:
# @('python -m pytest', 'python -m ruff check .')
# Example Node backend:
# @('npm run lint', 'npm test', 'npm run build')
# Example docs:
# @('python scripts/check_links.py', 'git diff --check')

# Optional tool locations for Task Scheduler environments.
$EXTRA_PATHS = @()

# Safety policy passed to each fresh agent session.
$ALLOW_AGENT_COMMIT = $true
$ALLOW_PUSH_OR_DEPLOY = $false

$RUNTIME_DIR = "loop\runtime"
$LOG_DIR = "logs"
