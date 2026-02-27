#!/bin/bash
# Variant 1: Inline bar — no box, sits in the content flow
# Like VS Code inline prompts, GitHub CLI confirmations

clear

printf "\n"
printf " \033[1m\033[33m◆ Glue\033[0m\n"
printf "    I'll write a helper function to parse the config file.\n"
printf "\n"
printf " \033[1m\033[33m▶ Tool: write_file\033[0m\n"
printf "    \033[90mpath: lib/src/config/parser.dart\033[0m\n"
printf "\n"

printf " \033[43m\033[30m ? Approve write_file \033[0m"
printf "  \033[90mpath: lib/src/config/parser.dart\033[0m\n"
printf "\n"
printf "   \033[7m  (y) Yes  \033[0m   (n) No    (a) Always \n"
printf "\n"
printf "   \033[2m←/→ navigate · Enter confirm · y/n/a hotkey\033[0m\n"

printf "\n\033[90m── 'No' focused: ──\033[0m\n\n"

printf " \033[43m\033[30m ? Approve write_file \033[0m"
printf "  \033[90mpath: lib/src/config/parser.dart\033[0m\n"
printf "\n"
printf "    (y) Yes   \033[7m  (n) No  \033[0m   (a) Always \n"

printf "\n"
