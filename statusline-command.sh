#!/bin/sh
# Claude Code status line  —  v1.1.0
# https://github.com/onury/claude-statusline
#   Line 1 (dim):  tokens used/total %  |  5hr % reset  |  week % reset
#   Line 2:        per-cell green->red progress bar under each segment
#
# Options (pass in settings.json, e.g.
#   "command": "sh ~/.claude/statusline-command.sh --width 20 --sections tokens,week"):
#   --width N        cells per bar / width of each line-1 field   (default 15)
#   --glyph CHAR     single-column bar cell character             (default ▘)
#   --sections LIST  comma list / order: tokens,5hr,week          (default tokens,5hr,week)
#   --time FMT       strftime for the 5hr reset clock             (default %H:%M)
#   --date FMT       strftime for the weekly reset date           (default %b %d)
#   --fill F         brightness 0..1 of filled cells              (default 0.80)
#   --track F        brightness 0..1 of the unfilled track        (default 0.22)
# Pipe alignment is preserved for any settings: every non-last field is rendered to
# exactly --width columns (overlong reset text is clipped); only the last field may
# overflow, which never shifts a pipe.

# ---- defaults ----
WIDTH=15
GLYPH="▘"
SECTIONS="tokens,5hr,week"
TIMEFMT="%H:%M"
DATEFMT="%b %d"
FILL="0.80"
TRACK="0.22"

# ---- args ----
while [ $# -gt 0 ]; do
    case "$1" in
        --width)    WIDTH="$2";    shift 2 ;;
        --glyph)    GLYPH="$2";    shift 2 ;;
        --sections) SECTIONS="$2"; shift 2 ;;
        --time)     TIMEFMT="$2";  shift 2 ;;
        --date)     DATEFMT="$2";  shift 2 ;;
        --fill)     FILL="$2";     shift 2 ;;
        --track)    TRACK="$2";    shift 2 ;;
        *)          shift ;;       # ignore unknown
    esac
done
case "$WIDTH" in *[!0-9]*|"") WIDTH=15 ;; esac   # guard: positive integer
[ "$WIDTH" -lt 1 ] && WIDTH=1
BARW="$WIDTH"

input=$(cat)
ESC=$(printf '\033')

# ---- context window (tokens) ----
total_input=$(printf '%s' "$input"  | jq -r '.context_window.total_input_tokens // 0')
total_output=$(printf '%s' "$input" | jq -r '.context_window.total_output_tokens // 0')
ctx_size=$(printf '%s' "$input"     | jq -r '.context_window.context_window_size // 0')
total=$((total_input + total_output))

if [ "$ctx_size" -gt 0 ]; then
    tok_pct=$(( (total * 100 + ctx_size / 2) / ctx_size ))
else
    tok_pct=0
fi

# ---- rate limits (absent for API-key sessions / before first response) ----
fh_pct=$(printf '%s' "$input"   | jq -r '.rate_limits.five_hour.used_percentage // empty')
fh_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
wk_pct=$(printf '%s' "$input"   | jq -r '.rate_limits.seven_day.used_percentage // empty')
wk_reset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

DIM="${ESC}[2m"
RST="${ESC}[0m"
SEP="${DIM} | ${RST}"
BRIGHT="${ESC}[22m"   # normal intensity — makes the % stand out against the dim line
REDIM="${ESC}[2m"     # back to faint
MID="${ESC}[22m${ESC}[38;2;200;200;200m"   # medium: brighter than dim, dimmer than %
MIDOFF="${ESC}[39m${REDIM}"                 # restore default color + faint

# Abbreviate token counts to "k" (rounded)
fmtk() {
    n=$1
    if [ "$n" -ge 1000 ]; then
        echo "$(( (n + 500) / 1000 ))k"
    else
        echo "$n"
    fi
}

# Render a BARW-cell bar; each cell owns a green(0%)->red(100%) gradient color.
# Filled cells are bright; the unfilled track keeps the same hue but dim.
bar() {
    awk -v p="$1" -v w="$BARW" -v esc="$ESC" -v glyph="$GLYPH" -v fill="$FILL" -v track="$TRACK" 'BEGIN {
        filled = int(p / 100 * w + 0.5);
        out = "";
        for (i = 0; i < w; i++) {
            f = (w > 1) ? i / (w - 1) : 0;
            if (f <= 0.5) { r = f * 2 * 255; g = 255 }
            else          { r = 255; g = (1 - f) * 2 * 255 }
            br = (i < filled) ? fill : track;
            out = out esc sprintf("[38;2;%d;%d;0m", int(r * br + 0.5), int(g * br + 0.5)) glyph;
        }
        printf "%s%s[0m", out, esc;
    }'
}

# Decide which requested sections actually have data, preserving requested order.
avail=""
for s in $(printf '%s' "$SECTIONS" | tr ',' ' '); do
    case "$s" in
        tokens) [ "$ctx_size" -gt 0 ] && avail="$avail tokens" ;;
        5hr)    [ -n "$fh_pct" ]      && avail="$avail 5hr" ;;
        week)   [ -n "$wk_pct" ]      && avail="$avail week" ;;
    esac
done
set -- $avail
count=$#

# Precompute per-section reset strings.
fh_t=""; [ -n "$fh_reset" ] && fh_t=" $(date -r "$fh_reset" +"$TIMEFMT" 2>/dev/null)"
wk_d="";  [ -n "$wk_reset" ] && wk_d=" $(date -r "$wk_reset" +"$DATEFMT" 2>/dev/null)"
[ -n "$fh_pct" ] && fh_r=$(printf "%.0f" "$fh_pct")
[ -n "$wk_pct" ] && wk_r=$(printf "%.0f" "$wk_pct")
if [ "$ctx_size" -gt 0 ]; then tok_used=$(fmtk "$total"); tok_tot=$(fmtk "$ctx_size"); fi

# Build line 1 (text) and line 2 (bars), one section at a time.
L1=""; L2=""; idx=0
for s in $avail; do
    idx=$((idx + 1))
    case "$s" in
        tokens) lp="${tok_used}/${tok_tot}"; ls="${MID}${tok_used}${MIDOFF}/${tok_tot}"; pct="${tok_pct}%"; bp="$tok_pct" ;;
        5hr)    lp="5hr${fh_t}";  ls="$lp"; pct="${fh_r}%"; bp="$fh_r" ;;
        week)   lp="Week${wk_d}";  ls="$lp"; pct="${wk_r}%"; bp="$wk_r" ;;
    esac

    pad=$(( BARW - ${#lp} - ${#pct} ))
    if [ "$idx" -eq "$count" ]; then
        # Last field: may overflow (no pipe follows), just keep a 1-space gap.
        [ "$pad" -lt 1 ] && pad=1
    elif [ "$pad" -lt 1 ]; then
        # Non-last: clip left text so the field stays exactly BARW -> pipes stay aligned.
        keep=$(( BARW - ${#pct} - 1 )); [ "$keep" -lt 0 ] && keep=0
        lp=$(printf '%.*s' "$keep" "$lp"); ls="$lp"
        pad=1
    fi
    spaces=$(printf "%*s" "$pad" "")
    seg="${ls}${spaces}${BRIGHT}${pct}${REDIM}"

    if [ -z "$L1" ]; then
        L1="$seg"; L2="$(bar "$bp")"
    else
        L1="$L1 | $seg"; L2="$L2${SEP}$(bar "$bp")"
    fi
done

if [ -n "$L1" ]; then
    printf "%s%s%s\n%s\n" "$DIM" "$L1" "$RST" "$L2"
fi
