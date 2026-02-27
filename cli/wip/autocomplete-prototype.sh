#!/bin/bash
# Slash command autocomplete prototype — animated
# Simulates the interaction step by step

cols=$(tput cols)
rows=$(tput lines)

# Dark gray background for overlay rows
# \033[48;5;236m = 256-color bg (dark gray)
BG="\033[48;5;236m"
SEL="\033[48;5;24m\033[97m"  # selected: dark blue bg, bright white text
DIM="\033[48;5;236m\033[37m" # unselected: dark gray bg, light gray text
RST="\033[0m"

pad_line() {
  # Print a line padded to terminal width with background color
  local color="$1"
  local text="$2"
  local stripped
  stripped=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
  local len=${#stripped}
  local padding=$((cols - len))
  if [ "$padding" -lt 0 ]; then padding=0; fi
  printf "${color}${text}%${padding}s${RST}\n" ""
}

draw_screen() {
  local input="$1"
  local overlay_state="$2"  # none, all, filtered_cl, filtered_cl_down, filtered_he, accepted

  printf "\033[H\033[J"  # clear screen, home

  # Output content
  printf "\n"
  printf " \033[1m\033[33m◆ Glue\033[0m\n"
  printf "    Sure, I can help with that. I've written the config parser\n"
  printf "    and it handles all the edge cases we discussed.\n"
  printf "\n"
  printf " \033[1m\033[32m✓ Tool result\033[0m\n"
  printf "    \033[90mFile written successfully.\033[0m\n"
  printf "\n"

  # Compute how many blank lines we need to push overlay to bottom
  local overlay_lines=0
  case "$overlay_state" in
    all) overlay_lines=5 ;;
    filtered_cl|filtered_cl_down) overlay_lines=2 ;;
    filtered_he) overlay_lines=1 ;;
    *) overlay_lines=0 ;;
  esac

  local content_lines=10  # lines of content above
  local bottom_lines=$((1 + 1 + overlay_lines))  # status + input + overlay
  local spacer=$((rows - content_lines - bottom_lines - 1))
  if [ "$spacer" -lt 0 ]; then spacer=0; fi
  for ((i=0; i<spacer; i++)); do printf "\n"; done

  # Overlay
  case "$overlay_state" in
    all)
      pad_line "$SEL" "   /help         Show available commands and keybindings"
      pad_line "$DIM" "   /clear        Clear conversation history"
      pad_line "$DIM" "   /model        Show or change the current model"
      pad_line "$DIM" "   /compact      Toggle compact mode"
      pad_line "$DIM" "   /exit         Exit the application"
      ;;
    filtered_cl)
      pad_line "$SEL" "   /clear        Clear conversation history"
      pad_line "$DIM" "   /compact      Toggle compact mode"
      ;;
    filtered_cl_down)
      pad_line "$DIM" "   /clear        Clear conversation history"
      pad_line "$SEL" "   /compact      Toggle compact mode"
      ;;
    filtered_he)
      pad_line "$SEL" "   /help         Show available commands and keybindings"
      ;;
  esac

  # Status bar
  local status_left=" Ready  claude-sonnet-4-6  ~/code/glue/cli"
  local status_right="tok 1234 "
  local status_pad=$((cols - ${#status_left} - ${#status_right}))
  if [ "$status_pad" -lt 0 ]; then status_pad=0; fi
  printf "\033[7m%s%${status_pad}s%s\033[0m\n" "$status_left" "" "$status_right"

  # Input line
  printf " \033[33m❯ \033[0m%s" "$input"
}

label() {
  # Show a small label at top-right corner
  local msg="$1"
  printf "\033[1;1H\033[90m%s\033[0m" "$msg"
}

# ─── Animation ───────────────────────────────────────────────────────

# Start clean
draw_screen "" "none"
label "idle — type / to begin"
sleep 2

# Type "/"
draw_screen "/" "all"
label "typed \"/\" — all commands shown"
sleep 2.5

# Type "/c"
draw_screen "/c" "filtered_cl"
label "typed \"/c\" — filtered to 2 matches"
sleep 2

# Type "/cl"
draw_screen "/cl" "filtered_cl"
label "typed \"/cl\" — still 2 matches"
sleep 1.5

# Arrow down
draw_screen "/cl" "filtered_cl_down"
label "pressed ↓ — selected /compact"
sleep 2

# Arrow up
draw_screen "/cl" "filtered_cl"
label "pressed ↑ — back to /clear"
sleep 1.5

# Backspace to "/"
draw_screen "/" "all"
label "backspaced to \"/\" — all commands again"
sleep 2

# Type "/he"
draw_screen "/he" "filtered_he"
label "typed \"/he\" — single match"
sleep 2

# Accept with Enter
draw_screen "/help" "none"
label "pressed Enter — accepted /help, overlay gone"
sleep 2.5

# Submit
draw_screen "" "none"
label "pressed Enter again — command executed"
sleep 1

# Show result
printf "\033[H\033[J"
printf "\n"
printf " \033[1m\033[33m◆ Glue\033[0m\n"
printf "    Sure, I can help with that. I've written the config parser\n"
printf "    and it handles all the edge cases we discussed.\n"
printf "\n"
printf " \033[90mAvailable commands:\033[0m\n"
printf " \033[90m  /help — Show available commands and keybindings\033[0m\n"
printf " \033[90m  /clear — Clear conversation history\033[0m\n"
printf " \033[90m  /model — Show or change the current model\033[0m\n"
printf " \033[90m  /compact — Toggle compact mode\033[0m\n"
printf " \033[90m  /exit — Exit the application\033[0m\n"
printf "\n"

# Status + input at bottom
tput cup $((rows - 2)) 0
local status_left=" Ready  claude-sonnet-4-6  ~/code/glue/cli"
local status_right="tok 1234 "
local status_pad=$((cols - 43 - 9))
printf "\033[7m Ready  claude-sonnet-4-6  ~/code/glue/cli%${status_pad}stok 1234 \033[0m\n" ""
printf " \033[33m❯ \033[0m"

sleep 3
