#!/bin/bash
# Color options for You vs Glue headers
# Run: bash wip/color_examples.sh

printf '\n'
printf '=== Current (both yellow) ===\n'
printf ' \033[1m\033[33m❯ You\033[0m\n'
printf '    Hello, can you help me?\n'
printf ' \033[1m\033[33m◆ Glue\033[0m\n'
printf '    Sure, I can help with that.\n'
printf '\n'

printf '=== Option A: Blue / Green ===\n'
printf ' \033[1m\033[34m❯ You\033[0m\n'
printf '    Hello, can you help me?\n'
printf ' \033[1m\033[32m◆ Glue\033[0m\n'
printf '    Sure, I can help with that.\n'
printf '\n'

printf '=== Option B: Cyan / Green ===\n'
printf ' \033[1m\033[36m❯ You\033[0m\n'
printf '    Hello, can you help me?\n'
printf ' \033[1m\033[32m◆ Glue\033[0m\n'
printf '    Sure, I can help with that.\n'
printf '\n'

printf '=== Option C: Blue / Yellow (keep Glue) ===\n'
printf ' \033[1m\033[34m❯ You\033[0m\n'
printf '    Hello, can you help me?\n'
printf ' \033[1m\033[33m◆ Glue\033[0m\n'
printf '    Sure, I can help with that.\n'
printf '\n'

printf '=== Option D: White / Magenta ===\n'
printf ' \033[1m\033[37m❯ You\033[0m\n'
printf '    Hello, can you help me?\n'
printf ' \033[1m\033[35m◆ Glue\033[0m\n'
printf '    Sure, I can help with that.\n'
printf '\n'

printf '=== Option E: Cyan / Magenta ===\n'
printf ' \033[1m\033[36m❯ You\033[0m\n'
printf '    Hello, can you help me?\n'
printf ' \033[1m\033[35m◆ Glue\033[0m\n'
printf '    Sure, I can help with that.\n'
printf '\n'
