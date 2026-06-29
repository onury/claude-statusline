---
description: Toggle Claude Code statusline options, e.g. /sl compact
---

Run the bundled config helper with the user's request and print its output **verbatim**:

```sh
sh ~/.claude/sl-config.sh "$ARGUMENTS"
```

`sl-config.sh` owns all the logic: it maps the request (`compact`/`expanded`, a section
comma-list, `model on|off`, `branch on|off`, `time …`, `width N`, `responsive on|off`,
`help`, or empty) to the right `--flag`, edits **only** that flag on `statusLine.command`
in `~/.claude/settings.json` — preserving every other flag and writing in place so a
symlinked `settings.json` keeps its link — then prints the new command. Don't reimplement
any of that here; just run it and relay stdout. The change applies on the next status line
refresh.
