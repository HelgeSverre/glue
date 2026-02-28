#!/usr/bin/env bash
# TUI mockup: /skills command — interactive two-pane skill browser panel
# Fully dynamic: adapts to terminal size, supports keyboard navigation.
# Run in a terminal (≥80 cols recommended).

set -e

# ── ANSI codes ──────────────────────────────────────────────────────────────
DIM=$'\033[2m'
BOLD=$'\033[1m'
REV=$'\033[7m'
UL=$'\033[4m'
RST=$'\033[0m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
GRAY=$'\033[90m'
WHITE=$'\033[97m'
BG_YELLOW=$'\033[43m'
FG_BLACK=$'\033[30m'

HIDE_CURSOR=$'\033[?25l'
SHOW_CURSOR=$'\033[?25h'
CLEAR_SCREEN=$'\033[2J\033[H'
SAVE_POS=$'\033[s'
REST_POS=$'\033[u'

move_to() { printf '\033[%d;%dH' "$1" "$2"; }
clear_line() { printf '\033[2K'; }

# ── Data ────────────────────────────────────────────────────────────────────
NAMES=(
  "code-review"
  "frontend-design"
  "test-driven-dev"
  "systematic-debugging"
  "api-patterns"
  "db-migrations"
  "deploy-helpers"
  "doc-generator"
)
SOURCES=(
  "global"
  "global"
  "global"
  "global"
  "project"
  "project"
  "project"
  "global"
)
DESCRIPTIONS=(
  "Perform a formal code review. Analyzes code for bugs, style issues, security vulnerabilities, and suggests improvements. Use when the user explicitly asks for a code review."
  "Create distinctive, production-grade frontend interfaces with high design quality. Use this skill when the user asks to build web components, pages, or applications."
  "Write failing tests first, then implement code to make them pass. Use when implementing any feature or bugfix, before writing implementation code."
  "Systematically diagnose bugs through hypothesis-driven investigation. Use when encountering any bug, test failure, or unexpected behavior."
  "Apply consistent REST API design patterns including versioning, pagination, error responses, and authentication. Project-specific conventions."
  "Generate and manage database migration files following the project's ORM conventions. Handles schema changes, rollbacks, and seed data."
  "Automate deployment workflows including Docker builds, CI/CD pipeline configuration, and infrastructure-as-code templates."
  "Generate API documentation, README files, and inline code documentation following project style guides and conventions."
)
LICENSES=(
  "Apache-2.0"
  "MIT"
  "Apache-2.0"
  ""
  ""
  "MIT"
  ""
  "Apache-2.0"
)
AUTHORS=(
  "glue-team"
  "glue-team"
  "glue-team"
  "glue-team"
  ""
  "db-tools"
  ""
  "docs-team"
)
VERSIONS=(
  "1.2"
  "2.0"
  "1.0"
  "1.1"
  "0.3"
  "1.0"
  "0.1"
  "1.5"
)
COMPAT=(
  ""
  "Requires Node.js 18+"
  ""
  ""
  ""
  "Requires running database"
  "Requires docker, kubectl"
  ""
)

NUM_SKILLS=${#NAMES[@]}
SELECTED=0
SCROLL=0

# ── Helpers ─────────────────────────────────────────────────────────────────

# Pad or truncate string to exact width (plain text only)
pad() {
  local str="$1" w="$2"
  local len=${#str}
  if (( len >= w )); then
    printf '%s' "${str:0:$w}"
  else
    printf '%s%*s' "$str" $(( w - len )) ""
  fi
}

# Word-wrap plain text to width, output lines into array ref
wrap_text() {
  local text="$1" width="$2" out_var="$3"
  local -a result=()
  local line="" word
  for word in $text; do
    if (( ${#line} == 0 )); then
      line="$word"
    elif (( ${#line} + 1 + ${#word} <= width )); then
      line="$line $word"
    else
      result+=("$line")
      line="$word"
    fi
  done
  [[ -n "$line" ]] && result+=("$line")
  eval "$out_var=(\"\${result[@]}\")"
}

source_color() {
  if [[ "$1" == "global" ]]; then
    printf '%s' "$CYAN"
  else
    printf '%s' "$GREEN"
  fi
}

# ── Render ──────────────────────────────────────────────────────────────────

render() {
  local cols lines
  cols=$(tput cols)
  lines=$(tput lines)

  # Panel dimensions — 90% width, 70% height, centered
  local panel_w=$(( cols * 90 / 100 ))
  local panel_h=$(( lines * 70 / 100 ))
  (( panel_w < 60 )) && panel_w=60
  (( panel_w > cols - 2 )) && panel_w=$(( cols - 2 ))
  (( panel_h < 12 )) && panel_h=12
  (( panel_h > lines - 4 )) && panel_h=$(( lines - 4 ))

  local content_w=$(( panel_w - 2 ))   # inside border
  local content_h=$(( panel_h - 2 ))   # inside border
  local left_w=$(( content_w * 35 / 100 ))
  (( left_w < 24 )) && left_w=24
  (( left_w > content_w - 30 )) && left_w=$(( content_w - 30 ))
  local right_w=$(( content_w - left_w - 1 ))  # 1 for divider

  local start_row=$(( (lines - panel_h) / 2 ))
  local start_col=$(( (cols - panel_w) / 2 ))
  (( start_row < 1 )) && start_row=1
  (( start_col < 1 )) && start_col=1

  local visible_items=$(( content_h - 2 ))  # -2 for header + separator

  # Adjust scroll
  if (( SELECTED < SCROLL )); then
    SCROLL=$SELECTED
  elif (( SELECTED >= SCROLL + visible_items )); then
    SCROLL=$(( SELECTED - visible_items + 1 ))
  fi

  # ── Build right-pane detail lines for selected skill ──
  local -a detail_lines=()
  local idx=$SELECTED
  local name="${NAMES[$idx]}"
  local src="${SOURCES[$idx]}"
  local desc="${DESCRIPTIONS[$idx]}"
  local lic="${LICENSES[$idx]}"
  local author="${AUTHORS[$idx]}"
  local ver="${VERSIONS[$idx]}"
  local compat="${COMPAT[$idx]}"

  local detail_text_w=$(( right_w - 2 ))  # 1 padding each side

  detail_lines+=("${BOLD}${name}${RST}")
  detail_lines+=("")

  # Wrap description
  local -a desc_wrapped=()
  wrap_text "$desc" "$detail_text_w" desc_wrapped
  for dl in "${desc_wrapped[@]}"; do
    detail_lines+=("$dl")
  done
  detail_lines+=("")

  # Metadata table
  local src_path
  if [[ "$src" == "global" ]]; then
    src_path="~/.glue/skills/${name}/"
  else
    src_path=".glue/skills/${name}/"
  fi

  detail_lines+=("${GREEN}Source${RST}       ${DIM}${src_path}${RST}")
  if [[ -n "$lic" ]]; then
    detail_lines+=("${GREEN}License${RST}     ${DIM}${lic}${RST}")
  fi
  if [[ -n "$compat" ]]; then
    detail_lines+=("${GREEN}Requires${RST}    ${DIM}${compat}${RST}")
  fi
  if [[ -n "$author" ]]; then
    detail_lines+=("${GREEN}Author${RST}      ${DIM}${author}${RST}")
  fi
  if [[ -n "$ver" ]]; then
    detail_lines+=("${GREEN}Version${RST}     ${DIM}${ver}${RST}")
  fi

  local num_detail=${#detail_lines[@]}

  # ── Draw background (dimmed) ──
  printf '%s' "$CLEAR_SCREEN"
  local bg_lines=(
    ""
    "  ${YELLOW}●${RST} claude-sonnet-4-20250514 · ~/projects/myapp"
    ""
    "  ${GRAY}>${RST} explain the auth flow"
    ""
    "  The authentication flow starts with the user submitting"
    "  credentials to the /api/login endpoint. The server validates"
    "  the credentials against the user store and issues a JWT."
    ""
    "  ${GRAY}>${RST} refactor the user model"
    ""
    "  I'll restructure the User class to separate concerns..."
    ""
    "  ${GRAY}>${RST} /skills"
  )
  for (( r=1; r<=lines; r++ )); do
    move_to "$r" 1
    clear_line
    local bg_idx=$(( r - 1 ))
    if (( bg_idx < ${#bg_lines[@]} )); then
      printf '%s' "${DIM}${bg_lines[$bg_idx]}${RST}"
    fi
  done

  # ── Draw panel border ──
  local title=" SKILLS "
  local title_len=${#title}
  local top_fill=$(( panel_w - title_len - 4 ))

  # Top border
  move_to "$start_row" "$start_col"
  printf '%s' "${DIM}┌─${RST}${YELLOW}${title}${RST}${DIM}"
  printf '%0.s─' $(seq 1 $top_fill)
  printf '┐%s' "$RST"

  # Bottom border
  local bot_row=$(( start_row + panel_h - 1 ))
  move_to "$bot_row" "$start_col"
  printf '%s└' "$DIM"
  printf '%0.s─' $(seq 1 $(( panel_w - 2 )))
  printf '┘%s' "$RST"

  # Page indicator
  local total_pages=$(( (NUM_SKILLS + visible_items - 1) / visible_items ))
  local cur_page=$(( SCROLL / visible_items + 1 ))
  if (( total_pages > 1 )); then
    local page_str="${cur_page}/${total_pages}"
    local page_col=$(( start_col + panel_w - ${#page_str} - 2 ))
    move_to "$bot_row" "$page_col"
    printf '%s%s%s' "$GRAY" "$page_str" "$RST"
  fi

  # Side borders + content
  for (( r=1; r<panel_h-1; r++ )); do
    local row=$(( start_row + r ))
    move_to "$row" "$start_col"
    printf '%s│%s' "$DIM" "$RST"
    # Fill interior with spaces
    printf '%*s' "$content_w" ""
    printf '%s│%s' "$DIM" "$RST"
  done

  # ── Content area ──
  local content_start_col=$(( start_col + 1 ))
  local divider_col=$(( content_start_col + left_w ))
  local right_start_col=$(( divider_col + 1 ))

  # Draw vertical divider
  for (( r=1; r<panel_h-1; r++ )); do
    move_to $(( start_row + r )) "$divider_col"
    printf '%s│%s' "$GRAY" "$RST"
  done

  # ── Left pane: header ──
  local header_row=$(( start_row + 1 ))
  move_to "$header_row" $(( content_start_col + 1 ))
  printf '%s' "${BOLD} SKILL$(pad "" $(( left_w - 7 )))${RST}"

  local sep_row=$(( start_row + 2 ))
  move_to "$sep_row" $(( content_start_col + 1 ))
  local sep_str=""
  for (( s=0; s < left_w - 2; s++ )); do sep_str="${sep_str}─"; done
  printf '%s%s%s' "$GRAY" "$sep_str" "$RST"

  # ── Left pane: skill list ──
  for (( i=0; i<visible_items; i++ )); do
    local skill_idx=$(( SCROLL + i ))
    local row=$(( start_row + 3 + i ))
    move_to "$row" $(( content_start_col + 1 ))

    if (( skill_idx >= NUM_SKILLS )); then
      printf '%*s' $(( left_w - 2 )) ""
      continue
    fi

    local sname="${NAMES[$skill_idx]}"
    local ssrc="${SOURCES[$skill_idx]}"
    local scol
    scol=$(source_color "$ssrc")

    # Build the line content: " name      source "
    local name_field tag_field line_content
    local tag_w=7
    local name_w=$(( left_w - tag_w - 4 ))
    name_field=$(pad "$sname" "$name_w")
    tag_field=$(pad "$ssrc" "$tag_w")

    if (( skill_idx == SELECTED )); then
      # Reverse video for selection — render without ANSI inside to keep it clean
      printf '%s %s %s %s' "$REV" "$name_field" "$tag_field" "$RST"
    else
      printf '  %s %s%s%s' "$name_field" "$scol" "$tag_field" "$RST"
    fi
  done

  # ── Right pane: header ──
  move_to "$header_row" $(( right_start_col + 1 ))
  printf '%s' "${BOLD} DETAILS$(pad "" $(( right_w - 9 )))${RST}"

  move_to "$sep_row" $(( right_start_col + 1 ))
  sep_str=""
  for (( s=0; s < right_w - 2; s++ )); do sep_str="${sep_str}─"; done
  printf '%s%s%s' "$GRAY" "$sep_str" "$RST"

  # ── Right pane: detail content ──
  for (( i=0; i<visible_items; i++ )); do
    local row=$(( start_row + 3 + i ))
    move_to "$row" $(( right_start_col + 1 ))

    if (( i < num_detail )); then
      # Truncate to right_w - 2 (1 pad each side)
      local dline="${detail_lines[$i]}"
      # Strip ANSI for length check, but print with ANSI
      local plain
      plain=$(echo -e "$dline" | sed 's/\x1b\[[0-9;]*m//g')
      local max_w=$(( right_w - 2 ))
      if (( ${#plain} > max_w )); then
        # Rough truncation (good enough for mockup)
        printf ' %s' "${dline:0:$(( max_w + (${#dline} - ${#plain}) ))}"
      else
        printf ' %s%*s' "$dline" $(( max_w - ${#plain} )) ""
      fi
    else
      printf '%*s' $(( right_w - 1 )) ""
    fi
  done

  # ── Footer hints ──
  local hint_row=$(( start_row + panel_h - 2 ))
  local hint="${GRAY}  ↑↓ navigate   Enter activate   Esc close${RST}"
  move_to "$hint_row" $(( right_start_col + 1 ))
  printf ' %s' "$hint"

  # ── Input prompt ──
  local prompt_row=$(( lines - 1 ))
  move_to "$prompt_row" 1
  clear_line
  printf '  %s▶%s ' "$YELLOW" "$RST"

  # Park cursor
  move_to "$prompt_row" 5
}

# ── Main loop ───────────────────────────────────────────────────────────────

cleanup() {
  printf '%s' "$SHOW_CURSOR"
  stty echo 2>/dev/null
  stty -raw 2>/dev/null
  tput cnorm 2>/dev/null
  printf '\033[?1000l' 2>/dev/null  # disable mouse
  clear
}
trap cleanup EXIT

printf '%s' "$HIDE_CURSOR"
stty raw -echo 2>/dev/null

render

while true; do
  # Read a single byte
  IFS= read -rsn1 key
  case "$key" in
    $'\033')
      # Escape sequence
      IFS= read -rsn1 -t 0.05 k2
      if [[ -z "$k2" ]]; then
        # Plain Escape — exit
        break
      fi
      IFS= read -rsn1 -t 0.05 k3
      case "$k2$k3" in
        '[A') # Up
          (( SELECTED > 0 )) && (( SELECTED-- ))
          render
          ;;
        '[B') # Down
          (( SELECTED < NUM_SKILLS - 1 )) && (( SELECTED++ ))
          render
          ;;
        '[5') # Page Up (read trailing ~)
          IFS= read -rsn1 -t 0.05 _
          local page_sz=$(( $(tput lines) * 70 / 100 - 4 ))
          (( SELECTED -= page_sz ))
          (( SELECTED < 0 )) && SELECTED=0
          render
          ;;
        '[6') # Page Down (read trailing ~)
          IFS= read -rsn1 -t 0.05 _
          local page_sz=$(( $(tput lines) * 70 / 100 - 4 ))
          (( SELECTED += page_sz ))
          (( SELECTED >= NUM_SKILLS )) && SELECTED=$(( NUM_SKILLS - 1 ))
          render
          ;;
      esac
      ;;
    'q'|'Q')
      break
      ;;
    '')
      # Enter
      printf '%s' "$SHOW_CURSOR"
      stty echo 2>/dev/null
      stty -raw 2>/dev/null
      clear
      echo "Activated skill: ${NAMES[$SELECTED]}"
      exit 0
      ;;
  esac
done
