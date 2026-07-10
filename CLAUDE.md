# AgentDeck — agent context

Personal macOS widget (Swift/SwiftUI, SPM, no Xcode project). Owner: Esteban. Style: ponytail/minimal — smallest diff that works, files ≤200 lines, no speculative abstractions. `./build.sh run` is the whole dev loop; verify with `dist/.../AgentDeck --dump` (headless scan) before claiming anything works.

## Architecture (one line each)

- `main.swift` — AppDelegate: floating NSPanel, window resize dance, £ hotkey, menu-bar badge, `--dump` harness.
- `Store.swift` — 2s scan tick: scanners → dedupe → time-rule overlay → Titler → filters/sort → publish.
- `Models.swift` — `AgentThread`, `ThreadStatus` (sort order = rawValue), `Config` tunables (UserDefaults-backed).
- `ClaudeScanner.swift` / `CodexScanner.swift` — parse session jsonl (head/tail chunks only, mtime-keyed cache).
- `ScanCore.swift` — file readers, `finalStatus` time overlay (working + quiet 3min → `.stalled`).
- `Titler.swift` — OpenRouter gpt-oss-120b titles/summaries; disk cache; per-thread backoff; `Budget` caps.
- `ThreadRow.swift` / `DeckView.swift` / `SettingsView.swift` — UI. `Actions.swift` — click routing/jump.
- `MusicBar.swift` — `media-control stream` watcher + transport UI. `StatusBadge.swift` — badge image.
- `Notifier.swift` — working→ended sounds/notifications + `Notifier.log` (~/Library/Logs/AgentDeck.log).

## Hard-won gotchas (do not re-learn these)

**macOS 26.4 NSStatusItem minefield** (14-run bisection, 2026-07-10): a status item only ever materialized as a raw SF-symbol image with NOTHING else on the button — any `title`, `attributedTitle`, `target/action`, `toolTip`, or custom lockFocus-drawn NSImage (template or not) prevented the item from appearing (no window, no AX menu bar 2). Even the bare config is nondeterministic on build 25E246. Hence: numbered SF symbols carry the count, clicks come from global+local mouse monitors over the button window's frame. If the badge misbehaves, prefer replacing the mechanism (e.g. auto-reopen deck on new actionable) over another bisection.

**gpt-oss-120b is a reasoning model**: reasoning tokens count against `max_tokens`. At 160 a realistic payload burned everything thinking → empty content, `finish_reason=length`, billed, backoff. Fix: `max_tokens: 400` + `reasoning: {effort: "low"}` (~75 completion tokens). JSON sometimes lands in `message.reasoning` with empty `content` — parser checks both.

**`claude://resume` IMPORTS the transcript** — on an already-open session it spawns a duplicate "general coding session" tab in the Claude app. Check liveness first via `~/.claude/sessions/<pid>.json` (sessionId + pid; `kill(pid, 0)`), and just activate the app when live.

**MediaRemote is locked down on macOS 15.4+** — direct framework calls return nothing. `media-control` (brew, ungive) uses the perl-adapter trick. Use `stream` (one persistent process, diff-merge into a dict; NSNull deletes keys), never poll `get`. Two traps: (1) `waitUntilExit` on the main thread during `MusicWatcher.shared` init pumps the run loop → SwiftUI re-enters `shared` → dispatch_once deadlock at launch (crash bug_type 309). Everything runs on a private serial queue. (2) killing AgentDeck orphans the perl child → sweep `pkill -f mediaremote-adapter.pl.*stream` before spawning.

**Window resize dance**: the panel must NEVER animate its frame (SwiftUI animates the card; both animating = twitching). Grow instantly, shrink after `Config.animDuration` settles, card top-pinned with a Spacer. Post `.agentDeckResize` after any view-size-changing state flip.

**Status pipeline order matters**: scanners cache CONTENT-derived status (mtime-keyed, so time rules can't live there); `ScanCore.finalStatus` overlays time rules at every tick in Store AND in `--dump`.

**Titler budget**: 120/h, 600/day (UserDefaults `aiCallsHour`/`aiCallsDay` in bundle domain `com.esteban.agentdeck`). A failing thread backs off 10 min — without it one bad thread burned the hourly budget in under a minute. Cache: `~/Library/Application Support/AgentDeck/titles.json` (newest 300 kept). Key: `~/.config/agentdeck/env`.

**ThreadStatus rawValues are sort order** and nothing persists them — renumbering is safe. `actionable` = needsInput/error/stalled; drives badge, "need you" count, jump, pings.

**Text concatenation in ThreadRow subtitle** is built in pieces — one long `Text +` chain times out the Swift type-checker.

## QA

- `--dump` prints every thread with status/PR — synthetic transcripts under `~/.claude/projects/<dir>/<uuid>.jsonl` (+ `touch -t` for age) exercise stalled/PR/needs-input paths end-to-end.
- Screen-capture is blocked for CLI shells (no Screen Recording permission); verify UI via AX (`System Events → process "AgentDeck" → menu bars`, window list) or ask Esteban to look.
- Watch `~/Library/Logs/AgentDeck.log` and crash reports in `~/Library/Logs/DiagnosticReports/AgentDeck-*.ips`.
