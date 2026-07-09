# AgentDeck

Floating macOS widget showing every live AI agent thread — Claude Code (CLI + Claude desktop app) and Codex (CLI + Codex Desktop) — with status, completion sound + notification, and click-to-jump.

## What it does

- **Always-on-top glass panel** (all Spaces, no dock icon). Drag it anywhere; position is remembered.
- **Status dots**: 🟢 working · 🟠 ready for you (turn finished, or stalled >3 min on a likely permission prompt) · ⚪ idle (>30 min). Sessions older than 8h drop off.
- **Sound (Glass) + notification** when a thread flips working → ready. Clicking the notification jumps to the thread.
- **Click a row to jump**:
  - Claude app thread → `claude://resume?session=<id>` (opens that exact session in the Claude desktop app)
  - Codex app thread → `codex://threads/<id>`
  - CLI thread still running → raises the matching Ghostty tab (title match via Accessibility), else activates Ghostty
  - CLI thread that exited → new Ghostty window in the session's cwd running `claude --resume <id>` / `codex resume <id>`

## Data sources

- Claude Code: `~/.claude/projects/*/*.jsonl` (entrypoint distinguishes CLI vs desktop app; subagent sidechains skipped)
- Codex: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` (originator distinguishes CLI vs Codex Desktop; subagent rollouts skipped)

Polls every 2s, reads only head/tail chunks of each file — negligible CPU.

## Build & run

```sh
./build.sh run     # builds dist/AgentDeck.app and (re)launches it
```

Debug the scanner without UI: `.build/debug/AgentDeck --dump`

First run: allow **Notifications** when prompted. First CLI-tab jump: allow **Accessibility** (System Events control) when prompted. Add `dist/AgentDeck.app` to Login Items to keep it around.

## Known caveats

- Clicking a Claude-app thread uses Anthropic's own import deep link; if that session is already open in the app it may open as a fresh imported tab rather than focusing the existing one.
- Ghostty tab matching is by window title (macOS exposes no tty→window mapping). If no title matches, it just activates Ghostty.
- claude.ai chat threads (non-agent chats) are server-side only and out of scope.
