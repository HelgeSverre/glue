#!/bin/bash
# Variant 2: Bottom-anchored compact bar (vim/emacs command area style)
# Approval sits at the bottom like a status prompt

clear
cols=$(tput cols)

printf "\n"
printf " \033[1m\033[33m◆ Glue\033[0m\n"
printf "    I'll write a helper function to parse the config file.\n"
printf "\n"
printf " \033[1m\033[33m▶ Tool: write_file\033[0m\n"
printf "    \033[90mpath: lib/src/config/parser.dart\033[0m\n"
printf "\n"
printf " \033[1m\033[33m▶ Tool: bash\033[0m\n"
printf "    \033[90mcommand: dart test\033[0m\n"
printf "\n"
printf " \033[1m\033[33m◆ Glue\033[0m\n"
printf "    The tests are passing. Let me also add error handling.\n"
printf "\n\n"

printf "\033[90m"
printf '%*s' "$cols" '' | tr ' ' '─'
printf "\033[0m\n"
printf " \033[1m\033[33m?\033[0m Approve \033[1mbash\033[0m  \033[90m·\033[0m  \033[7m y \033[0m Yes  \033[90m│\033[0m  n No  \033[90m│\033[0m  a Always\n"
printf "   \033[90mcommand: dart test\033[0m\n"

printf "\n\033[90m── 'No' focused: ──\033[0m\n\n"

printf "\033[90m"
printf '%*s' "$cols" '' | tr ' ' '─'
printf "\033[0m\n"
printf " \033[1m\033[33m?\033[0m Approve \033[1mbash\033[0m  \033[90m·\033[0m  y Yes  \033[90m│\033[0m  \033[7m n \033[0m No  \033[90m│\033[0m  a Always\n"
printf "   \033[90mcommand: dart test\033[0m\n"

printf "\n"
