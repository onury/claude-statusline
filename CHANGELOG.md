# claude-statusline - Changelog

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/) and this project adheres to [Semantic Versioning](http://semver.org).


## 2.3.0 (2026-07-14)

### Added
- **`effort` section** — shows the reasoning effort the session is running at (`.effort.level`): the `Effort` label on line 1 and the level on line 2. Effort changes both how hard the model thinks and what the turn costs, and Claude Code surfaces it nowhere else. The five levels are the ones Claude offers — `Low`, `Medium`, `High` (the default), `Extra`, `Max` — colored cool to hot so the setting reads at a glance without being read: white-ish yellow (held back a little), yellow-ish orange, Claude orange, reddish orange, red (`#BE170C`). Claude's UI calls the fourth level `Extra` while the API calls it `xhigh`; both spellings are accepted and it shows as `Extra`. A level this version has never seen is shown uncolored rather than dropped. **Off by default.**

### Changed
- **The `model` section names the model, and nothing else.** It used to append the context window — `Opus 4.8 (1M)` — which read as though 1M were a property of the model. It is not: nearly every current model can run at 1M, whether a given session does is a runtime setting of that session, and the size printed came from `.context_window.context_window_size`, not from the model's name. The `context` section already shows that number, as the denominator (`797k/1000k`). Any parenthetical carried by the payload's own `display_name` is dropped for the same reason.

## 2.2.0 (2026-07-04)

### Added
- **`cost` section** (alias `credit`) — shows this session's estimated spend (`.cost.total_cost_usd`) as a plain `S.Cost $0.41` amount: the `S.Cost` label (session cost) on line 1 and the dollar value on line 2 in amber (in compact, `S.Cost $0.41` inline). No bar and no `%` — Claude Code exposes no usage-credit balance to the status line, so there's nothing to measure against; this is the closest signal for pay-as-you-go spend once a rate limit is hit. **Off by default.**
- **`/sl cost on|off`** toggle in `sl-config.sh` (`credit` accepted as an alias).

### Fixed
- **`--responsive` no longer drops sections that actually fit.** The width estimate assumed *every* section was `--width` columns wide, but the `branch`/`model`/`cost` columns are sized to their content (often far narrower). On a line with those sections, the estimate ran well over the true width and dropped the rightmost section (e.g. `model`) even with plenty of room to spare. It now sums each section's real display width — bar sections at `--width`, label/value columns at their content width — so sections drop only when the line genuinely overflows.


## 2.1.0 (2026-06-29)

### Added
- **`sl-config.sh`** — a bundled POSIX-sh helper that powers the `/sl` slash command. It maps a request (`compact`/`expanded`, a section comma-list, `model on|off`, `branch on|off`, `time …`, `width N`, `responsive on|off`, a literal `--flag` passthrough, `help`, or empty) to the right `--flag` and edits **only** that flag on your `statusLine.command` in `settings.json`, in place (symlink-safe).

### Changed
- The **`/sl` command** is now a one-line wrapper that runs `sl-config.sh` and relays its output. Previously the full request→flag mapping was baked into the command prompt and worked out by the model on every call — moving it into the script does the **same edits for ~10× fewer tokens and near-instantly**, with no behavior change.
- `/sl` now installs **two files** (`commands/sl.md` + `sl-config.sh`).

No change to the status line renderer's output.


## 2.0.0 (2026-06-26)

### Removed
- The **`--branch` and `--model` flags** — sections are now controlled solely by `--sections`, rendered **in the order given**.

### Changed
- The token section is **renamed to `context`** (`tokens` still works as a legacy alias).
- **New default:** `--sections context,5hr,week,branch`.
- **Narrow widths (expanded):** when a section's `%` no longer fits, it's dropped (the bar still shows the level). For `5hr`/`Week` the label stays pinned left and the time value (`-02:35`, `-6days`) right-aligns into the freed space; `context` stays left-aligned.
- **Compact layout:** no bar-width padding — each field fits its content.

Migrate: `--branch true` → add `branch` to `--sections` (now on by default); `--model true` → add `model` to `--sections`.


## 1.6.0 (2026-06-26)

### Added
- **`/sl` slash command** — an optional Claude Code command for changing the status line **from inside a session**, no hand-editing of `settings.json`. It edits only the flag you name, preserves the rest, and persists the change (symlink-safe).


## 1.5.0 (2026-06-26)

### Added
- **`--layout expanded|compact`** — `compact` collapses the status line to a **single line**: drops the line-2 bars, and the `branch`/`model` sections show their value (e.g. `main`, `Opus 4.8 (1M)`) in place of the label. `expanded` (default) is the usual two-line view.
- **Colored percentages** — each `%` takes its bar's leading-edge gradient hue (green→red), dimmed a touch so it reads as a value.
- **Highlighted time values** — the 5hr/week reset time/date (`@21:12`, `@Jun03`) get a medium brightness tier, between the dim label and the bright `%`.

### Changed
- Default `--width` is now **16** (was 15), and the weekly reset date is space-free (`@Jun03`) so it never clips, even at 100%.


## 1.4.0 (2026-06-26)

### Added
- **`branch` section** — shows the active git branch, placed **before** the model column and colored blue; shows the short commit hash when detached, and is skipped when the workspace isn't a git repo. On by default (`--branch true`).

### Changed
- The `branch`/`model` columns now **fit their content** instead of padding out to the bar width; the other sections keep their fixed `--width`.


## 1.3.0 (2026-06-20)

### Added
- Initial public release. A drop-in status line for Claude Code: **per-cell green→red gradient bars** for context, 5-hour, and weekly rate limits (brightness shows fill); **`--time reset|remaining|elapsed`** window clocks; **awaiting `•••` placeholders** before the first API response; an optional `model` section; responsive section-dropping to fit the terminal; and always-preserved pipe alignment. Pure `sh` + `jq` + `awk`, 24-bit truecolor (macOS / Linux).
