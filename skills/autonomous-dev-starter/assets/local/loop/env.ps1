# Local CLI autonomous development loop configuration.
# autonomous-dev-starter fills AGENT_CMD and QUALITY_COMMANDS from verified local evidence.

$PROJECT_PROFILE = "auto"
$VCS_PREFERENCE = "auto"  # auto | git | svn
$AGENT_CMD = ""  # REQUIRED: verified non-interactive CLI command
$SELECTED_CLI = "auto"  # codex | claude | gemini | agy | custom

# Loop controls
$SLEEP_SECONDS = 5
$MAX_LOOPS = 0
$AGENT_TIMEOUT_SECONDS = 1800
$MAX_RETRIES = 1
$RETRY_BASE_SECONDS = 10
$MAX_CONSECUTIVE_FAILURES = 2

# Only commands that already exist in the target project belong here.
$QUALITY_COMMANDS = @()
# Git receives `git diff --check` automatically when this stays empty; SVN keeps its own registered gates.

# Optional tool locations for Task Scheduler or constrained shells.
$EXTRA_PATHS = @()

# Safe initial policy. Starter may enable commit only after a reviewed Git baseline exists.
$ALLOW_AGENT_COMMIT = $false
$ALLOW_PUSH_OR_DEPLOY = $false

$RUNTIME_DIR = "loop\runtime"
$LOG_DIR = "logs\autonomous-loop"
