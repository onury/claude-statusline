#!/bin/sh
# claude-statusline — /sl config helper  —  v1.1.0
# https://github.com/onury/claude-statusline
#
# Deterministically edits the `--flag`s on your `statusLine.command` in settings.json,
# changing only what you named and preserving every other flag. Drives the /sl slash
# command (commands/sl.md), but is runnable directly too:
#
#   sh ~/.claude/sl-config.sh                       # print current config + options
#   sh ~/.claude/sl-config.sh compact               # switch layout
#   sh ~/.claude/sl-config.sh context,branch,model  # set sections (order preserved)
#   sh ~/.claude/sl-config.sh model off             # add/remove one section
#   sh ~/.claude/sl-config.sh time remaining        # time mode
#   sh ~/.claude/sl-config.sh width 18              # bar / field width
#   sh ~/.claude/sl-config.sh responsive on         # on|off
#
# Requires jq. Honors $CLAUDE_CONFIG_DIR (defaults to ~/.claude).

set -eu

SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
BASE="sh ~/.claude/statusline-command.sh"
DEFAULT_SECTIONS="context,5hr,week,branch"

usage() {
  cat <<'EOF'
/sl                       show current config + options
/sl help                  this list
/sl compact | expanded    switch layout
/sl context,branch,model  set sections (comma list: context,5hr,week,cost,branch,model)
/sl model on|off          add/remove the model section
/sl branch on|off         add/remove the branch section
/sl cost on|off           add/remove the cost section (this session's $ spend)
/sl time reset|remaining|elapsed
/sl width N               bar / field width
/sl responsive on|off     drop sections to fit the terminal
EOF
}

command -v jq >/dev/null 2>&1 || { echo "sl-config: jq is required" >&2; exit 1; }

# Current command, falling back to the default invocation if none is set yet.
CMD=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null || true)
[ -n "$CMD" ] || CMD="$BASE"

# Value of a --flag in CMD (space form); empty if the flag is absent.
flag_value() {
  printf '%s\n' "$CMD" | sed -n "s/.*$1 \\([^ ]*\\).*/\\1/p"
}

# Set or replace a --flag's value in CMD, preserving every other flag.
set_flag() {
  _f=$1; _v=$2
  if printf '%s\n' "$CMD" | grep -q -- "$_f "; then
    CMD=$(printf '%s\n' "$CMD" | sed "s|$_f [^ ]*|$_f $_v|")
  else
    CMD="$CMD $_f $_v"
  fi
}

# Write CMD back in place (preserving a symlinked settings.json) and print it.
commit() {
  [ -f "$SETTINGS" ] || { echo "sl-config: no settings.json at $SETTINGS" >&2; exit 1; }
  _new=$(jq --arg c "$CMD" '.statusLine.command = $c' "$SETTINGS")
  printf '%s\n' "$_new" > "$SETTINGS"
  printf '%s\n' "$CMD"
}

REQ=$(printf '%s' "$*" | sed 's/^ *//;s/ *$//')

case "$REQ" in
  "")  printf '%s\n\n' "$CMD"; usage; exit 0 ;;
  help) usage; exit 0 ;;

  compact|expanded)        set_flag --layout "$REQ"; commit ;;
  time\ *)                 set_flag --time "${REQ#time }"; commit ;;
  width\ *)                set_flag --width "${REQ#width }"; commit ;;
  responsive\ on)          set_flag --responsive true; commit ;;
  responsive\ off)         set_flag --responsive false; commit ;;
  sections\ *)             set_flag --sections "${REQ#sections }"; commit ;;

  model\ on|model\ off|branch\ on|branch\ off|cost\ on|cost\ off|credit\ on|credit\ off)
    _name=${REQ% *}; _state=${REQ#* }
    [ "$_name" = credit ] && _name=cost   # `credit` is an alias for the cost section
    _secs=$(flag_value --sections); [ -n "$_secs" ] || _secs=$DEFAULT_SECTIONS
    # Rebuild the list without _name (so `off` drops it and `on` re-adds it last).
    _out=""; _present=0; _oifs=$IFS; IFS=,
    for _s in $_secs; do
      if [ "$_s" = "$_name" ]; then _present=1; else _out="${_out:+$_out,}$_s"; fi
    done
    IFS=$_oifs
    if [ "$_state" = on ]; then
      if [ "$_present" = 1 ]; then _out=$_secs; else _out="${_secs},${_name}"; fi
    fi
    set_flag --sections "$_out"; commit ;;

  --*)
    # Literal flag passthrough: `--glyph ▘`, `--fill 0.5`, or a lone `--flag`.
    if [ "$REQ" = "${REQ#* }" ]; then
      printf '%s\n' "$CMD" | grep -q -- "$REQ" || CMD="$CMD $REQ"
      commit
    else
      set_flag "${REQ%% *}" "${REQ#* }"; commit
    fi ;;

  *)
    # A bare comma-list (or single section name) sets --sections directly.
    if printf '%s' "$REQ" | grep -Eq '^[a-z0-9]+(,[a-z0-9]+)*$'; then
      set_flag --sections "$REQ"; commit
    else
      printf 'sl-config: unrecognized request: %s\n\n' "$REQ" >&2
      usage >&2; exit 1
    fi ;;
esac
