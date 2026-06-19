#!/bin/sh
# Claude Code status line
# https://github.com/onury/claude-statusline
#   Line 1 (dim):  tokens used/total %  |  5hr % reset  |  week % reset
#   Line 2:        per-cell green->red progress bar under each segment
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

BARW=15
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

# Render a 15-cell bar; each cell discretely colored along a green->red ramp.
# Filled cells (< pct) are solid blocks in their color; the rest are dim gray.
bar() {
    awk -v p="$1" -v w="$BARW" -v esc="$ESC" 'BEGIN {
        filled = int(p / 100 * w + 0.5);
        out = "";
        for (i = 0; i < w; i++) {
            # Each cell owns a color from the green(0%)->red(100%) gradient.
            f = (w > 1) ? i / (w - 1) : 0;
            if (f <= 0.5) { r = f * 2 * 255; g = 255 }
            else          { r = 255; g = (1 - f) * 2 * 255 }
            # Filled cells bright; the track keeps the same hue, just dimmer.
            br = (i < filled) ? 0.80 : 0.22;
            out = out esc sprintf("[38;2;%d;%d;0m", int(r * br + 0.5), int(g * br + 0.5)) "▘";
        }
        printf "%s%s[0m", out, esc;
    }'
}

# Build line 1 (text) and line 2 (bars) segment by segment.
L1=""
L2=""
append() {  # $1 = left plain (for width), $2 = left styled, $3 = percent str, $4 = bar pct
    # Left text on the left; percent right-aligned (bright) at the field's end,
    # so the whole segment spans BARW and line-1 pipes align with line-2.
    lp="$1"; ls="$2"; pctp="$3"
    pad=$(( BARW - ${#lp} - ${#pctp} ))
    [ "$pad" -lt 1 ] && pad=1   # always keep a gap before the % (matters for Week at 100%)
    spaces=$(printf "%*s" "$pad" "")
    seg="${ls}${spaces}${BRIGHT}${pctp}${REDIM}"
    if [ -z "$L1" ]; then
        L1="$seg"; L2="$(bar "$4")"
    else
        L1="$L1 | $seg"; L2="$L2${SEP}$(bar "$4")"
    fi
}

if [ "$ctx_size" -gt 0 ]; then
    tok_used=$(fmtk "$total")
    tok_tot=$(fmtk "$ctx_size")
    # Brighten only the used-token count; keep "/total" dim.
    append "${tok_used}/${tok_tot}" "${MID}${tok_used}${MIDOFF}/${tok_tot}" "${tok_pct}%" "$tok_pct"
fi

if [ -n "$fh_pct" ]; then
    fh_r=$(printf "%.0f" "$fh_pct")
    fh_t=""
    [ -n "$fh_reset" ] && fh_t=" $(date -r "$fh_reset" +%H:%M 2>/dev/null)"
    append "5hr${fh_t}" "5hr${fh_t}" "${fh_r}%" "$fh_r"
fi

if [ -n "$wk_pct" ]; then
    wk_r=$(printf "%.0f" "$wk_pct")
    wk_d=""
    [ -n "$wk_reset" ] && wk_d=" $(date -r "$wk_reset" +'%b %d' 2>/dev/null)"
    append "Week${wk_d}" "Week${wk_d}" "${wk_r}%" "$wk_r"
fi

if [ -n "$L1" ]; then
    printf "%s%s%s\n%s\n" "$DIM" "$L1" "$RST" "$L2"
fi
