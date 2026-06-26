#!/bin/sh
# Claude Code status line  —  v1.5.0
# https://github.com/onury/claude-statusline
#   Line 1 (dim):  tokens used/total %  |  5hr % reset  |  week % reset  [ | Branch | Model ]
#   Line 2:        per-cell green->red progress bar under each segment   [ | branch | model name ]
#
# Options (pass in settings.json, e.g.
#   "command": "sh ~/.claude/statusline-command.sh --width 20 --model true"):
#   --width N           cells per bar / width of each line-1 field   (default 16)
#   --glyph CHAR        single-column bar cell character             (default ▘)
#   --sections LIST     comma list / order: tokens,5hr,week,branch,model (default tokens,5hr,week)
#   --time MODE         what the 5hr/week time field shows           (default reset)
#                         reset      reset point          @23:00   @Jun25
#                         remaining  time left, ticks down -04:30   -6days
#                         elapsed    time used, ticks up   +00:30   +1day
#                       (@ = at, - = before reset / down, + = since start / up;
#                        week switches to the -HH:MM/+HH:MM clock under 1 day.
#                        Shows an animated ••• once the last-known reset has passed
#                        — data only refreshes on session activity, so an idle
#                        countdown awaits fresh data instead of freezing at -00:00.
#                        The dots advance one step per render at any
#                        refreshInterval; pair with a low one for a faster spin.)
#   --fill F            brightness 0..1 of filled cells              (default 0.80)
#   --track F           brightness 0..1 of the unfilled track        (default 0.22)
#   --branch true|false append a Branch section (git branch, line 2) (default true)
#   --model true|false  append a Model section (name on line 2)      (default false)
#   --responsive true|false  drop sections from the right to fit $COLUMNS (default true)
#   --layout expanded|compact  expanded = two lines w/ bars; compact = single line,
#                       no bars, branch/model show their value             (default expanded)
# Pipe alignment is preserved for any settings: every non-last field is rendered to
# exactly --width columns (overlong text is clipped); only the last field may overflow,
# which never shifts a pipe.

# ---- defaults ----
WIDTH=16
GLYPH="▘"
SECTIONS="tokens,5hr,week"
TMODE="reset"         # reset | remaining | elapsed
TIMEFMT="%H:%M"       # 5hr reset clock (fixed)
DATEFMT="%b%d"        # weekly reset date, no space so it fits the column (e.g. Jun30)
FH_LEN=18000          # 5-hour window length, seconds
WK_LEN=604800         # 7-day window length, seconds
FILL="0.80"
TRACK="0.22"
BRANCH="true"
MODEL="false"
RESPONSIVE="true"
LAYOUT="expanded"     # expanded | compact

# ---- args ----
while [ $# -gt 0 ]; do
    case "$1" in
        --width)      WIDTH="$2";      shift 2 ;;
        --glyph)      GLYPH="$2";      shift 2 ;;
        --sections)   SECTIONS="$2";   shift 2 ;;
        --time)       TMODE="$2";      shift 2 ;;
        --fill)       FILL="$2";       shift 2 ;;
        --track)      TRACK="$2";      shift 2 ;;
        --branch)     BRANCH="$2";     shift 2 ;;
        --model)      MODEL="$2";      shift 2 ;;
        --responsive) RESPONSIVE="$2"; shift 2 ;;
        --layout)     LAYOUT="$2";     shift 2 ;;
        *)            shift ;;         # ignore unknown
    esac
done
case "$WIDTH" in *[!0-9]*|"") WIDTH=16 ;; esac   # guard: positive integer
[ "$WIDTH" -lt 1 ] && WIDTH=1
BARW="$WIDTH"
case "$TMODE" in reset|remaining|elapsed) ;; *) TMODE="reset" ;; esac   # guard
case "$LAYOUT" in expanded|compact) ;; *) LAYOUT="expanded" ;; esac      # guard
# --branch / --model append their sections (if not already requested).
# Branch is appended first so it lands before model when both flags are set.
if [ "$BRANCH" = "true" ]; then
    case ",$SECTIONS," in *,branch,*) ;; *) SECTIONS="$SECTIONS,branch" ;; esac
fi
if [ "$MODEL" = "true" ]; then
    case ",$SECTIONS," in *,model,*) ;; *) SECTIONS="$SECTIONS,model" ;; esac
fi

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

# ---- model ----
model_name=$(printf '%s' "$input" | jq -r '.model.display_name // empty')

# ---- git branch (of the active workspace dir; empty when not a repo) ----
work_dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$work_dir" ] && work_dir="."
git_branch=$(git -C "$work_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
# Detached HEAD reports "HEAD" — fall back to the short commit hash.
[ "$git_branch" = "HEAD" ] && git_branch=$(git -C "$work_dir" rev-parse --short HEAD 2>/dev/null)

DIM="${ESC}[2m"
RST="${ESC}[0m"
SEP="${DIM} | ${RST}"
BRIGHT="${ESC}[22m"   # normal intensity — makes the % stand out against the dim line
REDIM="${ESC}[2m"     # back to faint
MID="${ESC}[22m${ESC}[38;2;200;200;200m"   # medium: brighter than dim, dimmer than %
MIDOFF="${ESC}[39m${REDIM}"                 # restore default color + faint
MC_NAME="${ESC}[22m${ESC}[38;2;190;105;77m"   # model family — Claude orange, normal intensity (resists the dim line)
MC_VER="${ESC}[38;2;205;205;205m"   # version — dimmed white
MC_CTX="${ESC}[38;2;135;135;135m"   # (context) — dimmed gray
MC_BRANCH="${ESC}[22m${ESC}[38;2;97;160;235m"   # git branch — blue, normal intensity (resists the dim line)

# Abbreviate token counts to "k" (rounded)
fmtk() {
    n=$1
    if [ "$n" -ge 1000 ]; then echo "$(( (n + 500) / 1000 ))k"; else echo "$n"; fi
}
# Abbreviate a context-window size to a 1M / 200K style label
fmtctx() {
    n=$1
    if   [ "$n" -ge 1000000 ]; then echo "$(( n / 1000000 ))M"
    elif [ "$n" -ge 1000 ];    then echo "$(( n / 1000 ))K"
    else echo "$n"; fi
}
# A signed "HH:MM" clock for a duration in seconds.  $1=seconds (clamped >=0) $2=sign
clock_hm() {
    s=$1; [ "$s" -lt 0 ] && s=0
    printf -- '%s%02d:%02d' "$2" "$(( s / 3600 ))" "$(( (s % 3600) / 60 ))"
}
# A signed day count with singular/plural word.  $1=days $2=sign  ->  "-6days" / "+1day"
day_word() {
    if [ "$1" -eq 1 ]; then printf -- '%s1day' "$2"; else printf -- '%s%ddays' "$2" "$1"; fi
}
# Awaiting-reset indicator: a dot sliding across three slots.  Advances by the
# per-render counter SPIN (not the wall clock), so it never aliases — it steps
# once every render regardless of refreshInterval (no value can freeze it).
awaiting() {
    case "$(( SPIN % 3 ))" in
        0) printf ' \342\200\242\302\267\302\267' ;;   # •··
        1) printf ' \302\267\342\200\242\302\267' ;;   # ·•·
        *) printf ' \302\267\302\267\342\200\242' ;;   # ··•
    esac
}
# 5hr time field for the active --time mode (leading space included).  $1=resets_at $2=now
# Once the last-known reset has passed (stale data while idle), show the indicator.
fh_field() {
    rem=$(( $1 - $2 ))
    [ "$rem" -le 0 ] && { awaiting; return; }
    case "$TMODE" in
        reset)     printf ' @%s' "$(date -r "$1" +"$TIMEFMT" 2>/dev/null)" ;;
        remaining) printf ' %s'  "$(clock_hm "$rem" '-')" ;;
        elapsed)   printf ' %s'  "$(clock_hm "$(( FH_LEN - rem ))" '+')" ;;
    esac
}
# Weekly time field: whole days while >=1 day away, else the signed clock.  $1=resets_at $2=now
wk_field() {
    rem=$(( $1 - $2 ))
    [ "$rem" -le 0 ] && { awaiting; return; }
    case "$TMODE" in
        reset)     printf ' @%s' "$(date -r "$1" +"$DATEFMT" 2>/dev/null)" ;;
        remaining) if [ "$rem" -ge 86400 ]; then printf ' %s' "$(day_word "$(( (rem + 86399) / 86400 ))" '-')"
                   else printf ' %s' "$(clock_hm "$rem" '-')"; fi ;;
        elapsed)   el=$(( WK_LEN - rem )); [ "$el" -lt 0 ] && el=0
                   if [ "$el" -ge 86400 ]; then printf ' %s' "$(day_word "$(( el / 86400 ))" '+')"
                   else printf ' %s' "$(clock_hm "$el" '+')"; fi ;;
    esac
}
# Left-align text to exactly N columns (pad with spaces, or clip if too long)
fit() {
    if [ "${#1}" -gt "$2" ]; then printf '%.*s' "$2" "$1"; else printf '%-*s' "$2" "$1"; fi
}
# Color a model string "Name Ver (Ctx)": orange family, dim-white version, dim-gray context.
style_model() {
    mt="$1"; ctxp=""; rest="$mt"
    case "$mt" in *\ \(*\)) ctxp=" ${mt##* }"; rest="${mt% *}" ;; esac
    nm="${rest%% *}"; vr=""
    case "$rest" in *" "*) vr=" ${rest#* }" ;; esac
    printf '%s%s%s%s%s%s%s' "$MC_NAME" "$nm" "$MC_VER" "$vr" "$MC_CTX" "$ctxp" "$RST"
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

# Truecolor escape for the % label: the bar's leading-edge gradient color at p%,
# dimmed a touch below the filled-bar brightness so it reads as a value, not a cell.
pct_color() {
    awk -v p="$1" -v w="$BARW" -v esc="$ESC" -v fill="$FILL" 'BEGIN {
        br = fill * 0.78;                       # a dimmed version of the bar color
        filled = int(p / 100 * w + 0.5);
        front = filled - 1;                     # the leading (last filled) cell
        if (front < 0) front = 0; if (front > w - 1) front = w - 1;
        f = (w > 1) ? front / (w - 1) : 0;
        if (f <= 0.5) { r = f * 2 * 255; g = 255 }
        else          { r = 255; g = (1 - f) * 2 * 255 }
        printf "%s[22m%s[38;2;%d;%d;0m", esc, esc, int(r * br + 0.5), int(g * br + 0.5);
    }'
}

# Decide which requested sections to show, preserving requested order.
# The 5hr/week rate sections always show once requested: with no data yet (new
# session, before the first API response) they render the awaiting indicator.
avail=""
for s in $(printf '%s' "$SECTIONS" | tr ',' ' '); do
    case "$s" in
        tokens) [ "$ctx_size" -gt 0 ] && avail="$avail tokens" ;;
        5hr)    avail="$avail 5hr" ;;
        week)   avail="$avail week" ;;
        branch) [ -n "$git_branch" ]  && avail="$avail branch" ;;
        model)  [ -n "$model_name" ]  && avail="$avail model" ;;
    esac
done
set -- $avail
keep=$#

# Responsive: drop sections from the right until the line fits $COLUMNS.
case "$COLUMNS" in *[!0-9]*|"") cols=0 ;; *) cols="$COLUMNS" ;; esac
if [ "$RESPONSIVE" = "true" ] && [ "$cols" -gt 0 ]; then
    while [ "$keep" -gt 1 ] && [ $(( keep * BARW + 3 * (keep - 1) )) -gt "$cols" ]; do
        keep=$(( keep - 1 ))
    done
fi

# Precompute per-section content.
NOW=$(date +%s)
# Spin counter for the awaiting animation: advance ONCE per render (so it steps
# regardless of refreshInterval), and only while an indicator is on screen, so
# normal renders touch no files.  An indicator shows for a requested rate section
# that has no data yet OR whose last-known reset has already passed.
spin=0
for s in 5hr week; do
    case ",$SECTIONS," in *",$s,"*) ;; *) continue ;; esac
    if [ "$s" = "5hr" ]; then p="$fh_pct"; r="$fh_reset"; else p="$wk_pct"; r="$wk_reset"; fi
    if [ -z "$p" ]; then spin=1
    elif [ -n "$r" ] && [ "$r" -le "$NOW" ]; then spin=1; fi
done
SPIN=0
if [ "$spin" = 1 ]; then
    sf="${TMPDIR:-/tmp}/.cc-statusline-spin"
    [ -f "$sf" ] && read -r SPIN < "$sf" 2>/dev/null
    case "$SPIN" in *[!0-9]*|"") SPIN=0 ;; esac
    printf '%s' "$(( (SPIN + 1) % 2999997 ))" > "$sf" 2>/dev/null   # wrap stays a multiple of 3
fi
fh_t=""; [ -n "$fh_reset" ] && fh_t=$(fh_field "$fh_reset" "$NOW")
wk_d=""; [ -n "$wk_reset" ] && wk_d=$(wk_field "$wk_reset" "$NOW")
[ -n "$fh_pct" ] && fh_r=$(printf "%.0f" "$fh_pct")
[ -n "$wk_pct" ] && wk_r=$(printf "%.0f" "$wk_pct")
if [ "$ctx_size" -gt 0 ]; then tok_used=$(fmtk "$total"); tok_tot=$(fmtk "$ctx_size"); fi
model_text="$model_name"
if [ -n "$model_name" ]; then
    # Names may already carry a context label, e.g. "Opus 4.8 (1M context)";
    # tidy that to "(1M)". Only append a derived size if there's no parenthetical.
    model_text=$(printf '%s' "$model_name" | sed 's/ context//g')
    case "$model_text" in
        *\(*\)*) : ;;
        *) [ "$ctx_size" -gt 0 ] && model_text="$model_text ($(fmtctx "$ctx_size"))" ;;
    esac
fi

# Build line 1 (text) and line 2 (bars / model name), one section at a time.
L1=""; L2=""; idx=0
for s in $avail; do
    idx=$((idx + 1))
    [ "$idx" -gt "$keep" ] && break
    last=0; [ "$idx" -eq "$keep" ] && last=1

    if [ "$s" = "model" ] || [ "$s" = "branch" ]; then
        # Label on line 1; colored value on line 2 (no % / no bar).
        # These columns fit their content: width is the longer of label/value,
        # never padded out to the bar width.  Only the shorter of the two lines
        # gets trailing spaces, so the column's pipes still align vertically.
        if [ "$s" = "model" ]; then
            label="Model"; valtext="$model_text"; styled=$(style_model "$valtext")
        else
            label="Branch"; valtext="$git_branch"; styled="${MC_BRANCH}${valtext}${RST}"
        fi
        if [ "$LAYOUT" = "compact" ]; then
            # Single line: the value itself stands in (no label, no second line).
            # Re-assert dim after the value's reset so the next separator stays dim.
            seg="${styled}${DIM}"
        else
            colw=${#label}; [ "${#valtext}" -gt "$colw" ] && colw=${#valtext}
            seg=$(printf '%-*s' "$colw" "$label")
            barseg="${styled}$(printf '%*s' "$(( colw - ${#valtext} ))" '')"
        fi
    else
        case "$s" in
            tokens) lp="${tok_used}/${tok_tot}"; ls="${MID}${tok_used}${MIDOFF}/${tok_tot}"; pct="${tok_pct}%"; bp="$tok_pct" ;;
            5hr)    if [ -z "$fh_pct" ]; then lp="5hr$(awaiting)"; ls="$lp"; pct=""; bp=0
                    else lp="5hr${fh_t}"; ls="5hr${MID}${fh_t}${MIDOFF}"; pct="${fh_r}%"; bp="$fh_r"; fi ;;
            week)   if [ -z "$wk_pct" ]; then lp="Week$(awaiting)"; ls="$lp"; pct=""; bp=0
                    else lp="Week${wk_d}"; ls="Week${MID}${wk_d}${MIDOFF}"; pct="${wk_r}%"; bp="$wk_r"; fi ;;
        esac
        pad=$(( BARW - ${#lp} - ${#pct} ))
        if [ "$last" -eq 1 ]; then
            [ "$pad" -lt 1 ] && pad=1
        elif [ "$pad" -lt 1 ]; then
            clip=$(( BARW - ${#pct} - 1 )); [ "$clip" -lt 0 ] && clip=0
            lp=$(printf '%.*s' "$clip" "$lp"); ls="$lp"; pad=1
        fi
        spaces=$(printf "%*s" "$pad" "")
        if [ -n "$pct" ]; then pcol="$(pct_color "$bp")"; else pcol="$BRIGHT"; fi
        seg="${ls}${spaces}${pcol}${pct}${MIDOFF}"
        [ "$LAYOUT" = "compact" ] || barseg="$(bar "$bp")"
    fi

    if [ -z "$L1" ]; then
        L1="$seg"; L2="$barseg"
    else
        L1="$L1 | $seg"; L2="$L2${SEP}${barseg}"
    fi
done

if [ -n "$L1" ]; then
    if [ "$LAYOUT" = "compact" ]; then
        printf "%s%s%s\n" "$DIM" "$L1" "$RST"
    else
        printf "%s%s%s\n%s\n" "$DIM" "$L1" "$RST" "$L2"
    fi
fi
