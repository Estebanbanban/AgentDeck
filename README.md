# AgentDeck

Floating macOS mission-control for AI coding agents. Shows every live Claude Code (CLI + desktop app) and Codex (CLI + Codex Desktop) thread with AI-generated titles/summaries, status, and one-click jump — plus a browser music playbar so you never leave the deck.

![status: personal tool](https://img.shields.io/badge/status-personal%20tool-blue)

## What it does

- **Always-on-top glass panel** (all Spaces, no dock icon). Drag anywhere; position remembered. `£` toggles it globally.
- **Status dots**: 🟣 running · 🟠 needs input (question / permission prompt / interrupted) · 🟡 stalled? (says "working" but transcript quiet >3 min) · 🔴 error · 🟢 done · ⚪ idle (>30 min). Actionable rows sort to the top; stale rows auto-expire.
- **AI titles + summaries** via OpenRouter `gpt-oss-120b` (~75 tokens/call, disk-cached, capped 120/h · 600/day). Falls back to heuristic parsing without a key.
- **Sound + notification** when a thread flips running → done / needs-input / stalled. Clicking the notification jumps to the thread.
- **Click a row to jump**: Claude app → activates the app if the session is live (avoids `claude://resume` import duplicates), deep-links otherwise · Codex app → `codex://threads/<id>` · live CLI → raises the matching Ghostty tab · dead CLI → new Ghostty window running `claude --resume` / `codex resume` in the session's cwd.
- **PR button**: sessions that opened a PR get a hover button straight to it (from `pr-link` transcript records).
- **Star** rows to pin them (survive auto-expiry, gold glow). **Focus mode** shows starred only; **compact mode** shows actionable + running only.
- **Menu-bar badge**: ✳ when quiet, orange count when agents are blocked on you; click toggles the deck. (Flaky on macOS 26.4 — see CLAUDE.md.)
- **Music playbar** at the bottom: now-playing from any browser/app with prev / play-pause / next. Requires `brew install media-control`. Hidden when nothing plays.

## Data sources

- Claude Code: `~/.claude/projects/*/*.jsonl` (entrypoint distinguishes CLI vs desktop; sidechains skipped)
- Codex: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` (originator distinguishes CLI vs Desktop; spawned reviewers hidden by default)
- Liveness: `~/.claude/sessions/<pid>.json` registry + process table
- Now playing: `media-control stream` (MediaRemote via the perl-adapter trick, macOS 15.4+ safe)

Polls every 2s, reads only head/tail chunks of each file — negligible CPU.

## Build & run

```sh
./build.sh run     # builds dist/AgentDeck.app and (re)launches it
```

- Debug the scanner without UI: `dist/AgentDeck.app/Contents/MacOS/AgentDeck --dump`
- AI titles: put `OPENROUTER_API_KEY=sk-or-...` in `~/.config/agentdeck/env` (chmod 600). Toggle off in Settings.
- Music bar: `brew install media-control`
- First run: allow **Notifications**; first CLI-tab jump: allow **Accessibility**. Add `dist/AgentDeck.app` to Login Items to keep it around.

## Settings (gear icon)

Show window / retention / dim / overdue timings, DND mute, hide spawned agents, AI titles kill switch. All UserDefaults-backed.

## Known caveats

- Ghostty tab matching is by window title (macOS exposes no tty→window mapping); falls back to activating Ghostty.
- The menu-bar badge materializes unreliably on macOS 26.4 — OS-level NSStatusItem flakiness, documented in CLAUDE.md.
- claude.ai chat threads (non-agent chats) are server-side only and out of scope.
