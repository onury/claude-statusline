#!/bin/sh
# Claude Code status line  —  v1.0.0
# https://github.com/onury/claude-statusline
#   Line 1 (dim):  tokens used/total %  |  5hr % reset  |  week % reset  [ | Model ]
#   Line 2:        per-cell green->red progress bar under each segment   [ | model name ]
#
# Options (pass in settings.json, e.g.
#   "command": "sh ~/.claude/statusline-command.sh --width 20 --model true"):
#   --width N           cells per bar / width of each line-1 field   (default 15)
#   --glyph CHAR        single-column bar cell character             (default ▘)
#   --sections LIST     comma list / order: tokens,5hr,week,model    (default tokens,5hr,week)
#   --time FMT          strftime for the 5hr reset clock             (default %H:%M)
#   --date FMT          strftime for the weekly reset date           (default %b %d)
#   --fill F            brightness 0..1 of filled cells              (default 0.80)
#   --track F           brightness 0..1 of the unfilled track        (default 0.22)
#   --model true|false  append a Model section (name on line 2)      (default false)
#   --responsive true|false  drop sections from the right to fit $COLUMNS (default true)
# Pipe alignment is preserved for any settings: every non-last field is rendered to
# exactly --width columns (overlong text is clipped); only the last field may overflow,
# which never shifts a pipe.

# ---- defaults ----
WIDTH=15
GLYPH="▘"
SECTIONS="tokens,5hr,week"
TIMEFMT="%H:%M"
DATEFMT="%b %d"
FILL="0.80"
TRACK="0.22"
MODEL="false"
RESPONSIVE="true"

# ---- args ----
while [ $# -gt 0 ]; do
    case "$1" in
        --width)      WIDTH="$2";      shift 2 ;;
        --glyph)      GLYPH="$2";      shift 2 ;;
        --sections)   SECTIONS="$2";   shift 2 ;;
        --time)       TIMEFMT="$2";    shift 2 ;;
        --date)       DATEFMT="$2";    shift 2 ;;
        --fill)       FILL="$2";       shift 2 ;;
        --track)      TRACK="$2";      shift 2 ;;
        --model)      MODEL="$2";      shift 2 ;;
        --responsive) RESPONSIVE="$2"; shift 2 ;;
        *)            shift ;;         # ignore unknown
    esac
done
case "$WIDTH" in *[!0-9]*|"") WIDTH=15 ;; esac   # guard: positive integer
[ "$WIDTH" -lt 1 ] && WIDTH=1
BARW="$WIDTH"
# --model true appends the model section (if not already requested).
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

DIM="${ESC}[2m"
RST="${ESC}[0m"
SEP="${DIM} | ${RST}"
BRIGHT="${ESC}[22m"   # normal intensity — makes the % stand out against the dim line
REDIM="${ESC}[2m"     # back to faint
MID="${ESC}[22m${ESC}[38;2;200;200;200m"   # medium: brighter than dim, dimmer than %
MIDOFF="${ESC}[39m${REDIM}"                 # restore default color + faint
MC_NAME="${ESC}[38;2;190;105;77m"   # model family — Claude orange, a little dim
MC_VER="${ESC}[38;2;205;205;205m"   # version — dimmed white
MC_CTX="${ESC}[38;2;135;135;135m"   # (context) — dimmed gray

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

# Decide which requested sections actually have data, preserving requested order.
avail=""
for s in $(printf '%s' "$SECTIONS" | tr ',' ' '); do
    case "$s" in
        tokens) [ "$ctx_size" -gt 0 ] && avail="$avail tokens" ;;
        5hr)    [ -n "$fh_pct" ]      && avail="$avail 5hr" ;;
        week)   [ -n "$wk_pct" ]      && avail="$avail week" ;;
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
fh_t=""; [ -n "$fh_reset" ] && fh_t=" $(date -r "$fh_reset" +"$TIMEFMT" 2>/dev/null)"
wk_d="";  [ -n "$wk_reset" ] && wk_d=" $(date -r "$wk_reset" +"$DATEFMT" 2>/dev/null)"
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

    if [ "$s" = "model" ]; then
        # Label on line 1; colored model name on line 2 (no % / no bar).
        if [ "$last" -eq 1 ]; then
            seg="Model"; barseg=$(style_model "$model_text")
        else
            seg=$(fit "Model" "$BARW")
            if [ "${#model_text}" -ge "$BARW" ]; then
                barseg="${MC_NAME}$(printf '%.*s' "$BARW" "$model_text")${RST}"
            else
                barseg="$(style_model "$model_text")$(printf '%*s' "$(( BARW - ${#model_text} ))" '')"
            fi
        fi
    else
        case "$s" in
            tokens) lp="${tok_used}/${tok_tot}"; ls="${MID}${tok_used}${MIDOFF}/${tok_tot}"; pct="${tok_pct}%"; bp="$tok_pct" ;;
            5hr)    lp="5hr${fh_t}";  ls="$lp"; pct="${fh_r}%"; bp="$fh_r" ;;
            week)   lp="Week${wk_d}";  ls="$lp"; pct="${wk_r}%"; bp="$wk_r" ;;
        esac
        pad=$(( BARW - ${#lp} - ${#pct} ))
        if [ "$last" -eq 1 ]; then
            [ "$pad" -lt 1 ] && pad=1
        elif [ "$pad" -lt 1 ]; then
            clip=$(( BARW - ${#pct} - 1 )); [ "$clip" -lt 0 ] && clip=0
            lp=$(printf '%.*s' "$clip" "$lp"); ls="$lp"; pad=1
        fi
        spaces=$(printf "%*s" "$pad" "")
        seg="${ls}${spaces}${BRIGHT}${pct}${REDIM}"
        barseg="$(bar "$bp")"
    fi

    if [ -z "$L1" ]; then
        L1="$seg"; L2="$barseg"
    else
        L1="$L1 | $seg"; L2="$L2${SEP}${barseg}"
    fi
done

if [ -n "$L1" ]; then
    printf "%s%s%s\n%s\n" "$DIM" "$L1" "$RST" "$L2"
fi
