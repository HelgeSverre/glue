#!/bin/bash
# Variant 4: No box, just a ▸ selector inline (Amp/cargo/inquirer style)
# Lightest weight — blends into conversation flow

clear

printf "\n"
printf " \033[1m\033[33m◆ Glue\033[0m\n"
printf "    I'll write a helper function to parse the config file.\n"
printf "\n"
printf " \033[1m\033[33m▶ Tool: write_file\033[0m\n"
printf "    \033[90mpath: lib/src/config/parser.dart\033[0m\n"
printf "\n"

printf " \033[1m\033[33m? Approve: write_file\033[0m\n"
printf "    \033[90mpath:\033[0m lib/src/config/parser.dart\n"
printf "    \033[90mcontent:\033[0m 47 lines\n"
printf "\n"
printf "    \033[32m\033[1m▸ Yes\033[0m   No   Always     \033[2m(y/n/a)\033[0m\n"
printf "\n"

printf "\033[90m── 'No' focused: ──\033[0m\n\n"

printf " \033[1m\033[33m? Approve: write_file\033[0m\n"
printf "    \033[90mpath:\033[0m lib/src/config/parser.dart\n"
printf "    \033[90mcontent:\033[0m 47 lines\n"
printf "\n"
printf "    Yes   \033[31m\033[1m▸ No\033[0m   Always     \033[2m(y/n/a)\033[0m\n"
printf "\n"

printf "\033[90m── 'Always' focused: ──\033[0m\n\n"

printf " \033[1m\033[33m? Approve: write_file\033[0m\n"
printf "    \033[90mpath:\033[0m lib/src/config/parser.dart\n"
printf "    \033[90mcontent:\033[0m 47 lines\n"
printf "\n"
printf "    Yes   No   \033[36m\033[1m▸ Always\033[0m     \033[2m(y/n/a)\033[0m\n"
printf "\n"

printf "\033[90m── bash tool: ──\033[0m\n\n"

printf " \033[1m\033[33m? Approve: bash\033[0m\n"
printf "    \033[90mcommand:\033[0m dart test --reporter compact\n"
printf "\n"
printf "    \033[32m\033[1m▸ Yes\033[0m   No   Always     \033[2m(y/n/a)\033[0m\n"

printf "\n"
