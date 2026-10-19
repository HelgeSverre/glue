# Run from the repository root with VHS, Glue, and JetBrains Mono installed.
# Set GLUE_DEMO_CWD to a demo project and GLUE_DEMO_SESSION to its saved session ID.
# Set GLUE_HOME too if the session uses an isolated Glue home.
# Real Glue TUI; palette copied from Helge's Ghostty themes/fleet-dark.
# The README GIF is a 5.8-second excerpt; MP4 includes the model picker.
Output "docs/assets/glue-demo-full.gif"
Output "docs/assets/glue-demo.mp4"
Set Shell "bash"
Set Width 1400
Set Height 920
Set FontSize 22
Set FontFamily "JetBrains Mono"
Set Padding 20
Set Framerate 15
Set Theme {"name": "Helge Fleet Dark", "background": "#111111", "foreground": "#BCBEC4", "cursor": "#FFFEF8", "selection": "#2D4F7C", "black": "#2B2B2B", "red": "#E05252", "green": "#6A8759", "yellow": "#D9A74A", "blue": "#6897BB", "magenta": "#94558D", "cyan": "#287BDE", "white": "#A9B7C6", "brightBlack": "#606366", "brightRed": "#FF6B6B", "brightGreen": "#6AAF6A", "brightYellow": "#FFC66D", "brightBlue": "#9CDCFE", "brightMagenta": "#CC7832", "brightCyan": "#4D78CC", "brightWhite": "#BCBEC4"}
Env GLUE_TITLE_GENERATION_ENABLED "false"
Hide
Type@1ms `cd "$GLUE_DEMO_CWD" && glue --resume "$GLUE_DEMO_SESSION"`
Enter
Sleep 5s
Show
Sleep 2s
Type@150ms "/"
Sleep 2s
Down
Sleep 800ms
Down
Sleep 800ms
Backspace
Type@150ms "/model"
Sleep 1s
Enter
Sleep 300ms
Enter
Sleep 2s
Type@180ms "haiku"
Sleep 2s
Escape
Sleep 300ms
Ctrl+U
Sleep 1s
