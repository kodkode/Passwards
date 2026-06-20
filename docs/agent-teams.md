# Agent Teams — Master Reference Guide

A practical, build-better reference for orchestrating **agent teams** in Claude Code. Distilled
from the official docs (<https://code.claude.com/docs/en/agent-teams>, reflecting **v2.1.178+**,
notes through v2.1.181) plus the live `SendMessage` tool schema. Use this to decide *when* to form a
team, *how* to spawn and steer it, and *what* the real tools/settings/limits are.

> **Status:** experimental, **off by default**. In this repo it is already enabled via
> `.claude/settings.local.json` → `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"`. Restart Claude
> Code (or start a new session) for that to take effect.

---

## 1. TL;DR

- An **agent team** = one **lead** session (your main session) + N **teammates**, each a *full,
  independent* Claude Code session with its own context window. Teammates **message each other
  directly** and **share a task list** — unlike subagents, which only report back to the caller.
- **Enable:** set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (settings.json or env). No team-creation
  step; teams form when the first teammate spawns and are cleaned up on session exit.
- **Spawn:** describe the work + the teammates in natural language ("spawn 3 teammates to review PR
  #142: security, performance, tests"). Claude won't spawn without your approval.
- **Best for:** parallel research/review, competing-hypothesis debugging, new independent modules,
  cross-layer changes. **Not for:** sequential work, same-file edits, dependency-heavy tasks.
- **Cost:** each teammate is a separate Claude instance → **significantly more tokens**. Reserve for
  work that genuinely parallelizes. Start with **3–5 teammates**, **5–6 tasks each**.

---

## 2. Mental model: Teams vs Subagents vs Workflows

Claude Code gives you three ways to parallelize. Pick by **how much the workers must talk** and
**how much determinism/steering you want**.

| Approach | What it is | Workers talk to each other? | You steer mid-run? | Best for |
|---|---|---|---|---|
| **Subagents** (`Agent` tool) | One-shot helpers spawned by the main agent; results summarized back | No — report to caller only | No | Focused lookups/research/verification where only the result matters |
| **Workflows** (`Workflow` tool) | A deterministic JS script that fans out *ephemeral* subagents in pipelines/parallel stages with structured output | No (script orchestrates) | No (runs to completion) | Repeatable, structured fan-out: review pipelines, migrations, audits, judge panels |
| **Agent teams** | Long-lived peer sessions sharing a task list + mailbox; you can open and message any teammate | **Yes** — direct peer messaging | **Yes** — talk to any teammate, redirect, approve plans | Collaborative work needing discussion/challenge: parallel review, hypothesis debates, cross-layer features |

Rule of thumb: **need debate/coordination or live steering → agent team. Need a clean, repeatable,
structured pass → workflow. Need a quick answer back → subagent.**

---

## 3. Enabling agent teams

Set the env var (string `"1"`), via `settings.json` or the shell:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Without it: no team is set up at session start, no team directories are written, and Claude will not
spawn or propose teammates. **Applied at session startup** — restart after changing it.

---

## 4. Architecture & where things live

| Component | Role |
|---|---|
| **Team lead** | The main session — spawns teammates, coordinates, synthesizes. Fixed for the session's life. |
| **Teammates** | Separate Claude Code instances, each on assigned tasks, each own context window. |
| **Task list** | Shared work items teammates claim/complete; supports dependencies. |
| **Mailbox** | Messaging system; teammate messages arrive at the lead automatically (no polling). |

**Storage** (session-derived name = `session-` + first 8 chars of the session ID):

- Team config: `~/.claude/teams/{team-name}/config.json` — runtime state (session IDs, tmux pane
  IDs) + a `members` array (each teammate's name, agent ID, agent type; teammates can read it to
  discover peers). **Removed when the session ends. Don't hand-edit or pre-author** — overwritten on
  the next state update.
- Task list: `~/.claude/tasks/{team-name}/` — **persists** locally (never uploaded), so resumed
  sessions keep tasks. Retention follows `cleanupPeriodDays`.

There is **no project-level team config** — a `.claude/teams/teams.json` in the repo is treated as an
ordinary file, not configuration.

---

## 5. Spawning teammates

Two ways a team forms (you always approve first):

1. **You request** teammates explicitly in a prompt.
2. **Claude proposes** teammates when it judges the task benefits from parallelism; you confirm.

### Control what gets spawned

- **Count + model:** `"Spawn 4 teammates to refactor these modules in parallel. Use Sonnet for each
  teammate."` Teammates don't inherit the lead's `/model`; set **Default teammate model** in
  `/config` (choose *Default (leader's model)* to follow the lead).
- **Names:** the lead names each teammate. For **predictable names you can reference later**, tell it
  what to call them in the spawn prompt.
- **Subagent definitions as roles:** reference any subagent type (project/user/plugin/CLI scope) —
  `"Spawn a teammate using the security-reviewer agent type to audit the auth module."` The teammate
  honors that definition's `tools` allowlist and `model`, and its body is **appended** to the system
  prompt. ⚠️ `skills` and `mcpServers` frontmatter are **not** applied to teammates (they load
  skills/MCP from project + user settings like a normal session). Team tools (`SendMessage`, task
  tools) are always available even if `tools` is restricted.
- **Require plan approval** (for risky work): `"Spawn an architect teammate to refactor auth. Require
  plan approval before they make any changes."` The teammate stays in read-only plan mode, submits a
  plan, the lead approves/rejects-with-feedback (autonomously — give it criteria like "only approve
  plans with test coverage"), and on approval it implements.

### What a teammate inherits

- ✅ Project context: `CLAUDE.md`, MCP servers, skills (loaded fresh, same as a normal session).
- ✅ The **spawn prompt** from the lead.
- ✅ The lead's **permission mode** at spawn (incl. `--dangerously-skip-permissions` if the lead has
  it). You can change an individual teammate's mode *after* spawn, not per-teammate at spawn time.
- ❌ The lead's **conversation history** does **not** carry over → put task-specific context in the
  spawn prompt.

---

## 6. Communication — the `SendMessage` tool

**Plain text output is NOT visible to other agents.** To communicate you MUST call `SendMessage`.
Incoming messages are delivered automatically — there's no inbox to poll.

```json
{ "to": "researcher", "summary": "assign task 1", "message": "start on task #1" }
```

| Field | Meaning |
|---|---|
| `to` | Recipient **teammate name** (e.g. `"researcher"`). `"main"` targets the main conversation — **background subagents only**. |
| `message` | Plain-text string, **or** a structured protocol object (below). |
| `summary` | 5–10 word UI preview. **Required when `message` is a string** (≤200 chars). |

- Refer to **active teammates by name**. To resume a completed background agent, use its `agentId`
  (`a...-...`) from the spawn result.
- To reach **everyone**, send **one message per recipient** (no broadcast).
- When relaying, **don't quote the original** — it's already rendered to the user.
- For status, use **`TaskUpdate`**, *not* JSON status messages over SendMessage.

### Protocol responses (shutdown / plan approval)

If you receive a JSON message with `type: "shutdown_request"` or `type: "plan_approval_request"`,
reply with the matching `_response`, echoing `request_id` and setting `approve`:

```json
{ "to": "team-lead",  "message": { "type": "shutdown_response",      "request_id": "...", "approve": true } }
{ "to": "researcher", "message": { "type": "plan_approval_response", "request_id": "...", "approve": false, "feedback": "add error handling" } }
```

- **Approving a shutdown terminates your process.** Rejecting a plan sends the teammate back to
  revise. **Don't originate `shutdown_request` unless asked.**

### How information flows

- **Automatic delivery** to recipients (lead doesn't poll).
- **Idle notifications:** a teammate that finishes/stops auto-notifies the lead.
- **Shared task list:** all agents see status and claim available work.

---

## 7. The shared task list

- States: **pending → in progress → completed**. Tasks may **depend** on others; a pending task with
  unresolved deps can't be claimed until they complete. Dependencies **auto-unblock** on completion.
- **Assignment:** lead assigns explicitly *or* a teammate **self-claims** the next unassigned,
  unblocked task after finishing one.
- **Claiming uses file locking** to avoid races when teammates grab the same task.
- Teammates update status with **`TaskUpdate`**; tasks are created with the task tools (lead drives
  this). Toggle the task list view with **Ctrl+T** (in-process).
- This is distinct from the single-session `TodoWrite` panel.

---

## 8. Display modes

| Mode | Behavior | Requirements |
|---|---|---|
| `in-process` *(default)* | All teammates run in your main terminal; navigate via the agent panel | Any terminal |
| split panes (`tmux` / `auto`) | Each teammate gets its own pane; see all output at once | tmux **or** iTerm2 + `it2` CLI |

- Set globally in `~/.claude/settings.json`: `{ "teammateMode": "auto" }` — values: `in-process`
  (default), `auto` (split panes when already in tmux or iTerm2, else in-process), `tmux` (force
  split, auto-detects tmux vs iTerm2).
- Per session: `claude --teammate-mode auto`.
- iTerm2 path: install `it2`, then **iTerm2 → Settings → General → Magic → Enable Python API**. tmux
  works best on macOS; `tmux -CC` in iTerm2 is the suggested entrypoint.
- ⚠️ Split panes are **not** supported in VS Code's integrated terminal, Windows Terminal, or
  Ghostty — those stay in-process.

### Agent panel controls (in-process)

| Key | Action |
|---|---|
| ↑ / ↓ | Select a teammate |
| Enter | Open the selected teammate's transcript / message it directly |
| Esc | Interrupt the selected teammate's current turn |
| `x` | Stop the selected teammate |
| Ctrl+T | Toggle the task list |

Idle rows hide after ~30s and reappear on the teammate's next turn — the teammate stays running and
addressable; message it by name to bring it back.

---

## 9. Controlling & ending teammates

- **Talk directly:** select + Enter (in-process) or click the pane (split) to give instructions, ask
  follow-ups, or redirect. Each teammate is a full session.
- **Assign/claim:** tell the lead who gets which task, or let teammates self-claim.
- **Shut down gracefully:** `"Ask the researcher teammate to shut down"` → the teammate approves
  (exits) or rejects with an explanation. Shared dirs are cleaned up automatically on session end.

---

## 10. Quality gates via hooks

Enforce rules at team lifecycle points (exit code **2** = block + send feedback):

| Hook | Fires | Exit-2 effect |
|---|---|---|
| `TeammateIdle` | A teammate is about to go idle | Keep it working with feedback |
| `TaskCreated` | A task is being created | Prevent creation, send feedback |
| `TaskCompleted` | A task is being marked complete | Prevent completion, send feedback |

(The `team_name` field in these payloads carries the session-derived name and is **deprecated**.)

---

## 11. Settings & flags reference

| Setting / flag | Where | Effect |
|---|---|---|
| `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="1"` | settings.json / env | Enable agent teams (required) |
| `teammateMode` | `~/.claude/settings.json` | `in-process` (default) / `auto` / `tmux` |
| `--teammate-mode <mode>` | CLI flag | Per-session display mode |
| **Default teammate model** | `/config` | Model for teammates when the prompt doesn't specify; *Default (leader's model)* to follow the lead |
| `cleanupPeriodDays` | settings.json | Retention for the persisted task list (and transcripts) |
| `isolatePeerMachines` | settings.json | Require approval before `SendMessage` reaches a peer on another machine (Remote Control) |
| `teammateMode: "in-process"` permission mode | inherited at spawn | Teammates start with the lead's permission mode |

Deprecated/removed: `TeamCreate`/`TeamDelete` tools (gone); the `team_name` input on the `Agent` tool
is accepted but **ignored**.

---

## 12. Playbooks (copy-paste prompts)

**Parallel code review** (distinct lenses so they don't overlap):
```
Spawn three teammates to review PR #142:
- One focused on security implications
- One checking performance impact
- One validating test coverage
Have them each review and report findings.
```

**Competing-hypothesis debugging** (adversarial debate beats anchoring):
```
Users report the app exits after one message instead of staying connected.
Spawn 5 agent teammates to investigate different hypotheses. Have them talk to
each other to try to disprove each other's theories, like a scientific
debate. Update the findings doc with whatever consensus emerges.
```

**New modules / cross-layer feature** (disjoint file ownership):
```
Spawn 3 teammates to add feature X. One owns the PasswardsCore model + storage,
one owns the SwiftUI app surfaces, one writes tests. Each owns a separate set
of files; coordinate on the shared API via messages before editing.
```

**Rich spawn prompt** (since history doesn't carry over — give full context):
```
Spawn a security reviewer teammate with the prompt: "Review the authentication module
at src/auth/ for security vulnerabilities. Focus on token handling, session
management, and input validation. The app uses JWT tokens stored in httpOnly
cookies. Report any issues with severity ratings."
```

---

## 13. Best practices

- **Give enough context in the spawn prompt** (no inherited history): paths, constraints, the
  deliverable, acceptance criteria.
- **Team size: 3–5** for most work; **5–6 tasks per teammate.** 3 focused teammates beat 5 scattered
  ones. Scale only when work *genuinely* parallelizes.
- **Size tasks** as self-contained units with a clear deliverable (a function, a test file, a
  review) — not too small (coordination overhead), not too large (long unattended runs).
- **Avoid file conflicts:** give each teammate a disjoint set of files. Two teammates editing one
  file → overwrites.
- **Wait for teammates:** if the lead starts doing the work itself, say *"Wait for your teammates to
  complete their tasks before proceeding."*
- **Monitor & steer:** check progress, redirect dead ends, synthesize as findings arrive. Don't let
  a team run unattended too long.
- **Start with research/review** (clear boundaries, no code) before parallel implementation.
- **Pre-approve permissions** before spawning — teammate permission prompts bubble up to the lead.

---

## 14. Limitations & troubleshooting

**Limitations (experimental):**
- **No session resumption for in-process teammates** — `/resume` and `/rewind` don't restore them;
  the lead may try to message teammates that no longer exist → tell it to spawn new ones.
- **Task status can lag** — teammates sometimes don't mark tasks complete, blocking dependents;
  update manually or nudge.
- **Shutdown can be slow** — teammates finish the current request/tool call first.
- **One team per session; no nested teams; lead is fixed** — teammates can't spawn teammates, and you
  can't transfer leadership.
- **Permissions set at spawn** (changeable per-teammate after).
- **Split panes need tmux/iTerm2.**

**Troubleshooting:**
- *Teammates not appearing:* check the agent panel (↑/↓, Enter); an idle row may be hidden (message
  by name); confirm the task was complex enough; for split panes verify `which tmux` / the `it2` CLI.
- *Too many permission prompts:* pre-approve common ops in permission settings.
- *Teammates stop on errors:* open the teammate, give instructions, or spawn a replacement.
- *Lead shuts down early:* tell it to keep going / wait for teammates.
- *Orphaned tmux sessions:* `tmux ls` then `tmux kill-session -t <name>`.

---

## 15. Applying this to **Passwards** (this repo)

This project has a clean two-layer architecture and a rich `CLAUDE.md`, which makes teams effective —
teammates auto-load `CLAUDE.md`, so they inherit the encryption invariant, naming gotcha, build/test
commands, and subsystem map for free.

**Strong fits here:**
- **Security review** — spawn lenses for crypto (`PasswardsCore/Crypto`), storage/SQL, CloudKit sync,
  and secrets-hygiene; have them challenge each other. (Mirrors the prior security-audit work.)
- **Cross-layer features** — one teammate owns `Packages/PasswardsCore` (models/storage/crypto), one
  owns the `Passwards/` SwiftUI app target, one owns tests. The **strict layer boundary** makes
  disjoint file ownership natural.
- **Competing-hypothesis debugging** — e.g., a sync conflict or a Touch ID enrollment failure.
- **Research** — 1Password-8 fidelity comparisons, library/API investigations.

**Cautions specific to this repo:**
- **File-conflict discipline:** split by directory/subsystem (e.g. `Crypto/` vs `Storage/` vs
  `Sync/`, or core vs app). Agent teams do **not** auto-isolate the filesystem — for parallel
  *implementation* that might collide, prefer disjoint ownership or git **worktrees** (the
  `Workflow` tool's `isolation: "worktree"` is the scripted alternative).
- **Verification still needs the owner:** the unlocked GUI can't be driven by automation (secure
  input; no master password). Teammates touching UI/Touch-ID/sync flows must hand exact steps to the
  owner — same rule as solo work.
- **Real passwords / safe-by-default:** the same security bar applies to every teammate; adversarially
  verify crypto/model/sync changes before declaring done.
- **Tests/build are headless and shareable:** `cd Packages/PasswardsCore && swift test` and the
  `xcodebuild … -allowProvisioningUpdates build` command work for any teammate.
- **Permissions:** `.claude/settings.local.json` already has a broad allowlist (git, swift, xcodebuild,
  screencapture, …) which teammates inherit — good, fewer prompts bubbling to the lead.
- **Reusable roles:** consider defining subagent types under `.claude/agents/` (e.g.
  `security-reviewer`, `swift-test-runner`) so they're reusable both as subagents and teammates.
  Remember their `skills`/`mcpServers` frontmatter won't apply when run as a teammate.

**When NOT to use a team here:** routine single-file edits, doc tweaks, a quick fix, or anything
sequential — use a single session or a subagent. For structured, repeatable fan-out (review
pipelines, codebase audits, migrations) prefer the **`Workflow`** tool, which this project already
uses heavily.

---

## 16. Cheat sheet

```
Enable:        env CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1   (restart)
Spawn:         "Spawn N teammates to … ; call them A/B/C ; use Sonnet"
Plan-gate:     "… Require plan approval before they make changes."
Role:          "Spawn a teammate using the <subagent-type> agent type to …"
Message:       SendMessage { to:"<name>", summary:"<5-10 words>", message:"…" }
Reach all:     one SendMessage per recipient (no broadcast)
Display:       teammateMode = in-process | auto | tmux   (or --teammate-mode)
Panel:         ↑/↓ select · Enter open/msg · Esc interrupt · x stop · Ctrl+T tasks
Wait:          "Wait for your teammates to complete before proceeding."
Shutdown:      "Ask the <name> teammate to shut down."
Size:          3–5 teammates · 5–6 tasks each · disjoint files
Hooks:         TeammateIdle / TaskCreated / TaskCompleted  (exit 2 = block+feedback)
Storage:       ~/.claude/teams/{session-xxxxxxxx}/  (ephemeral)
               ~/.claude/tasks/{session-xxxxxxxx}/  (persists)
```

---

*Source: official Claude Code docs — Agent Teams (<https://code.claude.com/docs/en/agent-teams>),
v2.1.178+ semantics, plus the live `SendMessage` tool schema. Re-verify against the latest docs as
the feature is experimental and evolving.*
