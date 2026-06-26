---
description: Toggle Claude Code statusline options, e.g. /sl compact
---

Adjust the `statusLine.command` string in `~/.claude/settings.json` per this request: "$ARGUMENTS".

That command invokes `sh ~/.claude/statusline-command.sh` with flags. Map the request to flags:

- `compact` / `expanded` → set `--layout <value>`
- a bare comma-list of section names (any of `context`, `5hr`, `week`, `branch`, `model`,
  e.g. `context,branch,model`) → set `--sections <list>` (sections render in the order given;
  `tokens` is a legacy alias for `context`)
- `sections <list>` → set `--sections <list>`
- `model on|off`, `branch on|off` → add/remove that section in `--sections` (there are no
  `--model`/`--branch` flags). `on` appends the section if absent; `off` removes it. If
  `--sections` isn't present yet, start from the default `context,5hr,week,branch`.
- `time reset|remaining|elapsed` → `--time <value>`
- `width N` → `--width N`
- `responsive on|off` → `--responsive true|false`
- anything else: interpret sensibly, or pass literal `--flag value` pairs through.

Then:

1. Read `.statusLine.command` from `~/.claude/settings.json`.
2. Add or replace **only** the relevant flag(s); preserve every other flag already present.
3. Write the result back **in place**, so a symlinked `settings.json` keeps its link —
   e.g. `new=$(jq '…' "$f") && printf '%s\n' "$new" > "$f"`. Do **not** `mv`/`cp` a temp
   file over it (that replaces the symlink and the edit can later be clobbered). Then print
   the new command.
4. Change nothing else in `settings.json`.

The change takes effect on the next statusline refresh (on activity, or within `refreshInterval`).

Special cases — do NOT edit settings.json for these, just print:

- `$ARGUMENTS` is empty → print the current `statusLine.command` and the supported options below.
- `$ARGUMENTS` is `help` → print this usage list:

  ```
  /sl                       show current config + options
  /sl help                  this list
  /sl compact | expanded    switch layout
  /sl context,branch,model  set sections (comma list: context,5hr,week,branch,model)
  /sl model on|off          add/remove the model section
  /sl branch on|off         add/remove the branch section
  /sl time reset|remaining|elapsed
  /sl width N               bar / field width
  /sl responsive on|off     drop sections to fit the terminal
  ```
