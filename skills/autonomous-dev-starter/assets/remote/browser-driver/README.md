# ChatGPT Persistent Browser Loop

This driver keeps the Windows-app driver in `loop/driver/` unchanged. It follows
the proven `naverCarBlog` browser pattern: real Chrome, one persistent automation
profile, one Playwright context for the entire loop, and DOM locators rather than
OS mouse coordinates.

The portable default is the target project's
`loop/runtime/chatgpt-browser-profile`. Override it with `-ProfilePath` or
`CHATGPT_BROWSER_PROFILE` when a separately authenticated automation profile
already exists. Node.js is resolved from `-NodePath`, `CHATGPT_NODE_PATH`, PATH,
or a discovered local runtime; user-specific absolute Node paths must not be
committed into the reusable template. `CHATGPT_NODE_MODULES` may point at a
Playwright installation when it is not adjacent to Node. The driver never reads
or prints cookies, passwords, or profile files. Close any other program using
the same automation profile before starting.

## Safe DOM probe (does not submit a prompt)

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\loop\browser-driver\browser-ui.ps1 -Action Probe -ProjectRoot (Get-Location).Path
```

The probe opens a fresh ChatGPT page, selects `Chat`, opens the composer `+`
menu, scrolls the exact `AI Folder Remote` row into view, and verifies the
committed plugin token. It exits without sending anything.

## Continuous run

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\loop\browser-driver\chatgpt-browser-loop.ps1 -ProjectRoot (Get-Location).Path -MaxLoops 2
```

The browser is launched once. Old restored tabs are closed, and one tab is
reused by navigating to a fresh `/` chat for every iteration. Chat mode, plugin
selection, prompt submission, late Continue-in-Chat routing, RUN_STATE
handshakes, and response-idle state are all verified before the next chat.

If ChatGPT stays on a visible connection-lost notice before any RUN_STATE or
claim change, the loop waits for the configured grace period (120 seconds by
default), stops that response with a DOM button event, rechecks project state,
and only then permits the normal fresh-chat retry. It never aborts a response
after a claim or RUN_STATE transition. Use `-DisconnectedGraceSeconds` to tune
the grace period.

To clean up an already-disconnected saved response without submitting a new
prompt, use `-Action StopDisconnected`. The action refuses to run unless the
saved conversation is both busy and visibly disconnected.

If RUN_STATE already contains an old RUNNING/RECOVERING heartbeat, the driver
resumes that exact active task and claim. It never creates a replacement claim.
The recovery agent must refresh the existing heartbeat immediately after it
verifies the exact claim. Fresh RUNNING work is observed in bounded watch
windows. A watch timeout is not a kill timeout: while the saved ChatGPT response
is actually busy, the driver keeps watching the same response and never presses
Stop merely to advance the loop. Recovery is allowed only after the response is
idle and the heartbeat is stale.
`loop/STOP` is graceful: if an iteration is already submitted/adopted it is
allowed to finish, then the driver refuses to open the next chat. `FAIL`,
`BLOCKED`, and `SKIP` results are terminal even when a handoff records the state
as `RECOVERING`; the loop stops without opening a replacement chat. Run only one
of the app, persistent-browser, or legacy profile-browser loops at a time.
