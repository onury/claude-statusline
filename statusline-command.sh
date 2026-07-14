#!/bin/sh
# Claude Code status line  —  v2.3.0
# https://github.com/onury/claude-statusline
#   Line 1 (dim):  context used/total %  |  5hr % reset  |  week % reset  [ | Branch | Model ]
#   Line 2:        per-cell green->red progress bar under each segment   [ | branch | model name ]
#
# Options (pass in settings.json, e.g.
#   "command": "sh ~/.claude/statusline-command.sh --width 20 --sections context,5hr,week,model"):
#   --width N           cells per bar / width of each line-1 field   (default 16)
#   --glyph CHAR        single-column bar cell character             (default ▘)
#   --sections LIST     comma list / order, any subset of            (default context,5hr,week,branch)
#                         context,5hr,week,cost,branch,model,effort  (`tokens` aliases
#                         `context`,
#                         `credit` aliases `cost`). Sections render in the order given.
#                         `cost` shows this session's estimated $ spend (no bar / %) —
#                         it is the only spend signal Claude Code exposes; there is no
#                         usage-credit balance in the status line payload.
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
#   --responsive true|false  drop sections from the right to fit $COLUMNS (default true)
#   --layout expanded|compact  expanded = two lines w/ bars; compact = single line,
#                       no bars, branch/model show their value             (default expanded)
# In the expanded layout, pipe alignment is preserved for any settings: every non-last
# field is rendered to exactly --width columns (overlong text is clipped); only the last
# field may overflow, which never shifts a pipe.  The compact layout is a single line with
# no bars to align to, so its fields fit their content (one space before each %, no padding).

# ---- defaults ----
WIDTH=16
GLYPH="▘"
SECTIONS="context,5hr,week,branch"
TMODE="reset"         # reset | remaining | elapsed
TIMEFMT="%H:%M"       # 5hr reset clock (fixed)
DATEFMT="%b%d"        # weekly reset date, no space so it fits the column (e.g. Jun30)
FH_LEN=18000          # 5-hour window length, seconds
WK_LEN=604800         # 7-day window length, seconds
FILL="0.80"
TRACK="0.22"
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

# ---- session cost (USD) — the running spend estimate, the only $ signal Claude Code
# exposes to the status line (there is no usage-credit balance in the payload) ----
cost_usd=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // empty')

# ---- effort (reasoning depth: low | medium | high | xhigh | max) ----
# Claude Code sends it on every render, and it appears nowhere else in the TUI —
# it changes both how hard the model thinks and what the turn costs.
effort_level=$(printf '%s' "$input" | jq -r '.effort.level // empty')

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
MC_COST="${ESC}[22m${ESC}[38;2;205;165;95m"     # session cost — amber/gold, normal intensity (resists the dim line)
# Effort — the ramp runs cool to hot as the model is told to think harder, so the
# level reads at a glance without being read.  All five are normal-intensity so they
# resist the dim line; only `low` is held back a little, since it is the quiet one.
EC_LOW="${ESC}[22m${ESC}[38;2;198;190;140m"     # low    — white-ish yellow, slightly held back
EC_MED="${ESC}[22m${ESC}[38;2;230;170;80m"      # medium — yellow-ish orange
EC_HIGH="${ESC}[22m${ESC}[38;2;217;119;87m"     # high   — Claude orange
EC_EXTRA="${ESC}[22m${ESC}[38;2;203;71;49m"     # extra  — reddish orange, midway between the two below/above
EC_MAX="${ESC}[22m${ESC}[38;2;190;23;12m"       # max    — red (#BE170C)
EC_ULTRA="${ESC}[22m${ESC}[38;2;255;0;0m"       # ultracode — pure red (#FF0000): hotter than max
EC_AUTO="${ESC}[22m${ESC}[38;2;27;175;84m"      # auto   — green (#1BAF54). Off the ramp on purpose:
                                                # it is not a depth, it is Claude choosing the depth.

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
# Color a model string "Name Ver": orange family, dim-white version.
style_model() {
    rest="$1"
    nm="${rest%% *}"; vr=""
    case "$rest" in *" "*) vr=" ${rest#* }" ;; esac
    printf '%s%s%s%s%s' "$MC_NAME" "$nm" "$MC_VER" "$vr" "$RST"
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
        context|tokens) [ "$ctx_size" -gt 0 ] && avail="$avail context" ;;   # `tokens` = legacy alias
        5hr)    avail="$avail 5hr" ;;
        week)   avail="$avail week" ;;
        branch) [ -n "$git_branch" ]  && avail="$avail branch" ;;
        model)  [ -n "$model_name" ]  && avail="$avail model" ;;
        effort) [ -n "$effort_level" ] && avail="$avail effort" ;;   # the display text is built later
        cost|credit) [ -n "$cost_usd" ] && avail="$avail cost" ;;   # `credit` = alias for cost
    esac
done
set -- $avail
keep=$#

# Model / cost display text — computed here (before the responsive check) so that
# check can measure their real width.  The bar sections are exactly --width, but
# branch/model/cost are sized to their content and must not be over-counted.
# The model section names the model, and nothing else. It used to append the context
# window — "Opus 4.8 (1M)" — but that size is not part of the model: it is a runtime
# setting of the session, read from `.context_window.context_window_size`, and the
# context section already shows it as the denominator ("708k/1M"). Printing it twice
# invited the reading that the window is a property of the model, which it is not.
# Any parenthetical the display name itself carries is dropped for the same reason.
model_text=""
[ -n "$model_name" ] && model_text=$(printf '%s' "$model_name" | sed -e 's/ *([^)]*)//g' -e 's/ *$//')

# Effort display text — "High", "XHigh", "Max".
effort_text=""
case "$effort_level" in
    low)    effort_text="Low";    EC="$EC_LOW" ;;
    medium) effort_text="Medium"; EC="$EC_MED" ;;
    high)   effort_text="High";   EC="$EC_HIGH" ;;
    # Claude's own UI calls this level "Extra"; the API calls it "xhigh". Accept both,
    # and show the name the user sees in the app.
    xhigh|extra) effort_text="Extra"; EC="$EC_EXTRA" ;;
    max)    effort_text="Max";    EC="$EC_MAX" ;;
    ultracode) effort_text="Ultracode"; EC="$EC_ULTRA" ;;
    # `auto` is not a rung on the ladder — Claude picks the depth per turn — so it is
    # colored apart from the cool-to-hot ramp rather than at one end of it.
    auto)   effort_text="Auto";   EC="$EC_AUTO" ;;
    "")     : ;;
    # An effort level this version has never heard of still gets shown, uncolored,
    # rather than silently dropped — Anthropic can add one at any time.
    *)      effort_text=$(printf '%s' "$effort_level" | tr '[:lower:]' '[:upper:]' | cut -c1)$(printf '%s' "$effort_level" | cut -c2-)
            EC="$BRIGHT" ;;
esac
cost_text=""
[ -n "$cost_usd" ] && cost_text=$(printf '$%.2f' "$cost_usd" 2>/dev/null)
[ -z "$cost_text" ] && [ -n "$cost_usd" ] && cost_text="\$$cost_usd"   # fallback if not numeric

# Display width of one section.  Bar sections (context/5hr/week) occupy exactly
# --width; the branch/model/cost columns fit their content — in compact, branch/model
# show just the value and cost shows "Cost <value>"; in expanded a label/value column
# is the wider of its label and value.  Counting these as a full bar (the old estimate)
# over-stated the line and dropped sections that actually fit.
sec_w() {
    case "$1" in
        branch) if [ "$LAYOUT" = compact ]; then _w=${#git_branch}
                else _w=6; [ "${#git_branch}" -gt "$_w" ] && _w=${#git_branch}; fi ;;   # "Branch"=6
        model)  if [ "$LAYOUT" = compact ]; then _w=${#model_text}
                else _w=5; [ "${#model_text}" -gt "$_w" ] && _w=${#model_text}; fi ;;   # "Model"=5
        cost)   if [ "$LAYOUT" = compact ]; then _w=$(( 7 + ${#cost_text} ))            # "S.Cost <value>"
                else _w=6; [ "${#cost_text}" -gt "$_w" ] && _w=${#cost_text}; fi ;;     # "S.Cost"=6
        effort) if [ "$LAYOUT" = compact ]; then _w=${#effort_text}
                else _w=6; [ "${#effort_text}" -gt "$_w" ] && _w=${#effort_text}; fi ;; # "Effort"=6
        *)      _w=$BARW ;;
    esac
    printf '%s' "$_w"
}

# Responsive: drop sections from the right until the real line width fits $COLUMNS.
case "$COLUMNS" in *[!0-9]*|"") cols=0 ;; *) cols="$COLUMNS" ;; esac
if [ "$RESPONSIVE" = "true" ] && [ "$cols" -gt 0 ]; then
    while [ "$keep" -gt 1 ]; do
        sum=$(( 3 * (keep - 1) )); n=0        # 3 columns per " | " separator
        for w in $avail; do
            n=$(( n + 1 )); [ "$n" -gt "$keep" ] && break
            sum=$(( sum + $(sec_w "$w") ))
        done
        [ "$sum" -le "$cols" ] && break
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

# Build line 1 (text) and line 2 (bars / model name), one section at a time.
L1=""; L2=""; idx=0
for s in $avail; do
    idx=$((idx + 1))
    [ "$idx" -gt "$keep" ] && break
    last=0; [ "$idx" -eq "$keep" ] && last=1

    if [ "$s" = "model" ] || [ "$s" = "branch" ] || [ "$s" = "cost" ] || [ "$s" = "effort" ]; then
        # Label on line 1; colored value on line 2 (no % / no bar).
        # These columns fit their content: width is the longer of label/value,
        # never padded out to the bar width.  Only the shorter of the two lines
        # gets trailing spaces, so the column's pipes still align vertically.
        if [ "$s" = "model" ]; then
            label="Model"; valtext="$model_text"; styled=$(style_model "$valtext")
        elif [ "$s" = "effort" ]; then
            label="Effort"; valtext="$effort_text"; styled="${EC}${valtext}${RST}"
        elif [ "$s" = "cost" ]; then
            label="S.Cost"; valtext="$cost_text"; styled="${MC_COST}${valtext}${RST}"
        else
            label="Branch"; valtext="$git_branch"; styled="${MC_BRANCH}${valtext}${RST}"
        fi
        if [ "$LAYOUT" = "compact" ]; then
            # Single line: the value itself stands in (no label, no second line) — except
            # cost keeps its "Cost" label, since a bare "$0.41" reads less clearly than a
            # branch/model name.  Re-assert dim after the value's reset so the next
            # separator stays dim.
            if [ "$s" = "cost" ]; then seg="${label} ${styled}${DIM}"; else seg="${styled}${DIM}"; fi
        else
            colw=${#label}; [ "${#valtext}" -gt "$colw" ] && colw=${#valtext}
            seg=$(printf '%-*s' "$colw" "$label")
            barseg="${styled}$(printf '%*s' "$(( colw - ${#valtext} ))" '')"
        fi
    else
        # core = left-pinned label; rt = the time value that can move to the right
        # when the % is hidden (empty for context and while awaiting).  lp/ls = the
        # full left block (core + time) used when the % is shown.
        case "$s" in
            context) core="${tok_used}/${tok_tot}"; cstyled="${MID}${tok_used}${MIDOFF}/${tok_tot}"
                     rt=""; rstyled=""; lp="$core"; ls="$cstyled"; pct="${tok_pct}%"; bp="$tok_pct" ;;
            5hr)    if [ -z "$fh_pct" ]; then core="5hr"; cstyled="5hr"; rt=""; rstyled=""
                        lp="5hr$(awaiting)"; ls="$lp"; pct=""; bp=0
                    else t="${fh_t# }"; core="5hr"; cstyled="5hr"; rt="$t"; rstyled="${MID}${t}${MIDOFF}"
                        lp="5hr $t"; ls="5hr${MID} ${t}${MIDOFF}"; pct="${fh_r}%"; bp="$fh_r"; fi ;;
            week)   if [ -z "$wk_pct" ]; then core="Week"; cstyled="Week"; rt=""; rstyled=""
                        lp="Week$(awaiting)"; ls="$lp"; pct=""; bp=0
                    else t="${wk_d# }"; core="Week"; cstyled="Week"; rt="$t"; rstyled="${MID}${t}${MIDOFF}"
                        lp="Week $t"; ls="Week${MID} ${t}${MIDOFF}"; pct="${wk_r}%"; bp="$wk_r"; fi ;;
        esac
        if [ "$LAYOUT" = "compact" ]; then
            # Single line: no bars to align to — one space before the %, none if absent.
            if [ -n "$pct" ]; then seg="${ls} $(pct_color "$bp")${pct}${MIDOFF}"; else seg="${ls}"; fi
        else
            # Expanded.  Hide the % when BARW can't hold the left block + a space + %.
            hid=0
            if [ -n "$pct" ] && [ $(( ${#lp} + 1 + ${#pct} )) -gt "$BARW" ]; then pct=""; hid=1; fi
            if [ -n "$pct" ]; then
                # % shown: left block on the left, % flush right within BARW.
                pad=$(( BARW - ${#lp} - ${#pct} ))
                if [ "$last" -eq 1 ]; then
                    [ "$pad" -lt 1 ] && pad=1
                elif [ "$pad" -lt 1 ]; then
                    clip=$(( BARW - ${#pct} - 1 )); [ "$clip" -lt 0 ] && clip=0
                    lp=$(printf '%.*s' "$clip" "$lp"); ls="$lp"; pad=1
                fi
                seg="${ls}$(printf "%*s" "$pad" "")$(pct_color "$bp")${pct}${MIDOFF}"
            elif [ "$hid" -eq 1 ] && [ -n "$rt" ]; then
                # % hidden for room: keep the label left, right-align only the time.
                pad=$(( BARW - ${#core} - ${#rt} ))
                if [ "$pad" -lt 1 ]; then
                    if [ "$last" -eq 1 ]; then pad=1            # overflow ok, keep a gap
                    else
                        clip=$(( BARW - ${#core} )); [ "$clip" -lt 0 ] && clip=0
                        rt=$(printf '%.*s' "$clip" "$rt"); rstyled="$rt"
                        pad=$(( BARW - ${#core} - ${#rt} )); [ "$pad" -lt 0 ] && pad=0
                    fi
                fi
                seg="${cstyled}$(printf "%*s" "$pad" "")${rstyled}${MIDOFF}"
            else
                # Awaiting placeholder, or the context section: left-align the value.
                pad=$(( BARW - ${#lp} ))
                if [ "$last" -ne 1 ] && [ "$pad" -lt 0 ]; then lp=$(printf '%.*s' "$BARW" "$lp"); ls="$lp"; fi
                [ "$pad" -lt 0 ] && pad=0
                seg="${ls}$(printf "%*s" "$pad" "")"
            fi
            barseg="$(bar "$bp")"
        fi
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
