# Known terminal issues

Glue's interactive UI is a terminal-native TUI. It relies on common xterm-style
features including the alternate screen buffer, hardware scroll regions,
bracketed paste, SGR mouse reporting, cursor addressing, and line clearing.
Most standalone terminals handle these consistently, but embedded terminals and
sessions with inherited terminal-integration variables can report capabilities
that do not match the emulator actually drawing the screen.

## JetBrains IDE embedded terminals (`JetBrains-JediTerm`)

### Symptoms

When Glue runs inside a JetBrains IDE terminal (IntelliJ IDEA, PhpStorm,
WebStorm, PyCharm, GoLand, Rider, etc.), users may see redraw glitches such as:

- stale or duplicated lines in the transcript;
- the status bar or input area moving unexpectedly;
- cursor jumps or cursor positioning errors;
- mouse-selection or paste behavior that differs from standalone terminals;
- rendering corruption after resize, scrolling, or long streaming output.

This is most likely when the environment contains JetBrains terminal markers:

```sh
TERMINAL_EMULATOR=JetBrains-JediTerm
__CFBundleIdentifier=com.jetbrains.<ide>
```

or when a JetBrains-launched shell has inherited another terminal's integration
variables, for example:

```sh
TERM_PROGRAM=ghostty
TERMINFO=/Applications/Ghostty.app/Contents/Resources/terminfo
GHOSTTY_SHELL_FEATURES=...
TERMINAL_EMULATOR=JetBrains-JediTerm
__CFBundleIdentifier=com.jetbrains.PhpStorm
```

That mixed identity means the process is probably running in JetBrains' embedded
terminal while advertising Ghostty-specific environment/capability data.

### Why this matters for Glue

Glue's renderer currently assumes an xterm-compatible terminal and uses:

- alternate screen buffer: `ESC[?1049h` / `ESC[?1049l`
- hardware scroll regions: `ESC[top;bottom r`
- bracketed paste: `ESC[?2004h` / `ESC[?2004l`
- SGR mouse reporting: `ESC[?1000h`, `ESC[?1002h`, `ESC[?1006h`
- DEC save/restore cursor: `ESC7` / `ESC8`
- cursor addressing and line clearing sequences

JetBrains' terminal stack is designed to emulate xterm/VT100, but public reports
show that TUI compatibility has had edge cases around scroll regions, terminal
capability mismatches, alternate buffers, input handling, and mouse/key events.
Glue's pinned status/input layout is particularly sensitive to scroll-region
behavior.

### Workarounds

Prefer running interactive Glue in a standalone terminal:

- Ghostty
- iTerm2
- WezTerm
- Kitty
- Terminal.app

If you must run Glue inside a JetBrains IDE terminal, first try sanitizing
inherited terminal variables:

```sh
unset TERM_PROGRAM TERM_PROGRAM_VERSION TERMINFO \
  GHOSTTY_BIN_DIR GHOSTTY_RESOURCES_DIR GHOSTTY_SHELL_FEATURES FIG_TERM
export TERM=xterm-256color

glue
```

If the glitches disappear after unsetting those variables, the problem is a
terminal identity/capability mismatch rather than the agent loop itself.

Also check the JetBrains terminal engine setting. JetBrains IDEs have shipped
multiple terminal implementations (Classic, Experimental, Reworked). If one
engine glitches, try another engine or a standalone terminal.

### Useful diagnostics

Capture the terminal identity before reporting a Glue rendering issue:

```sh
env | grep -E '^(TERM|TERM_PROGRAM|TERMINAL_EMULATOR|COLORTERM|TERMINFO|GHOSTTY_|FIG_TERM|__CFBundleIdentifier|XPC_SERVICE_NAME)='
tty
stty -a
```

A contradictory report such as `TERMINAL_EMULATOR=JetBrains-JediTerm` together
with `TERM_PROGRAM=ghostty` or Ghostty `TERMINFO` is especially relevant.

### Related public reports

These reports are not Glue-specific, but they document similar terminal/TUI
compatibility problems in JetBrains/JediTerm environments:

- JetBrains' `jediterm` README says JediTerm is the library used by JetBrains
  IDEs and advertises xterm-oriented features: "The library is used by JetBrains
  IDEs like PyCharm, IDEA, PhpStorm, WebStorm, AppCode, CLion, and Rider." It
  also lists "Xterm emulation", "Scrolling", "Mouse support", and terminal
  resizing as features.
- JetBrains' terminal architecture post says the 2023-2024 experimental terminal
  caused "Disruption of TUI programs" and that "Many terminal-based applications
  (Vim, less, tmux, etc.) expect standard terminal I/O sequences. The partial
  interception and rewriting of output frequently led to broken interactive
  interfaces or lost keystrokes." The same post says compatibility is paramount
  and that "TUI applications must all behave exactly like they do in a normal
  terminal."
- JetBrains' embedded terminal SDK documents separate regular and alternative
  output buffers: "regular — used for executing commands and displaying their
  output" and "alternative — usually used by \"fullscreen\" terminal applications
  like vim, nano, mc, and similar". It also documents shell integration injected
  at startup.
- `JetBrains/jediterm#148` reported that tmux/screen in JediTerm caused output to
  get "all messed up" and that scrolling in neovim inside tmux/screen filled the
  terminal with "text artefacts".
- `JetBrains/jediterm#317` fixed a related scrolling-region bug: "JediTerm was
  incorrectly handling cursor movement when the cursor was located outside the
  active scrolling region" and this could cause "visual corruption".
- `JetBrains/jediterm#328` reports a terminfo capability mismatch: JediTerm uses
  `TERM=xterm-256color`, whose terminfo advertises CBT (`CSI Z`), but JediTerm
  did not handle it, causing "corrupted terminal output" in Bubble Tea apps.
- `charmbracelet/ultraviolet#101` added JediTerm detection because "JediTerm
  reports `TERM=xterm-256color` but does not correctly handle Cursor Backward Tab
  (CBT), which can result in invalid rendering". Its detection checks include
  `TERMINAL_EMULATOR == "JetBrains-JediTerm"` and macOS JetBrains bundle markers.
- `google-gemini/gemini-cli#13618` disabled the alternate screen buffer by
  default on terminals "known to have rendering or scrolling issues", explicitly
  including JetBrains detected via `TERMINAL_EMULATOR`.
- `anomalyco/opencode#3941` reports that inside JetBrains IDE built-in terminals,
  OpenCode typing and multiline pasting "do not work correctly", including
  unresponsive input and pasted lines executing immediately.
- `anomalyco/opencode#6517` reports JetBrains Rider/IntelliJ TUI key/input issues
  on Windows 11 in the Reworked 2025 terminal.
- `fish-shell/fish-shell#11042` reports visible prompt/control artifacts in the
  IntelliJ/PyCharm terminal with fish 4.0 beta.

## Reporting new terminal issues

When filing a Glue issue, include:

1. the exact terminal app and version;
2. whether it is embedded in an IDE, multiplexer, SSH client, or remote session;
3. the output of the diagnostics above;
4. whether the same Glue session glitches in a standalone terminal;
5. a short screen recording if the issue is visual.

Do not include API keys or secrets from your full environment dump.

### Dump from infocmp

```
#	Reconstructed via infocmp from file: /usr/share/terminfo/78/xterm-256color
xterm-256color|xterm with 256 colors,
	am, bce, ccc, km, mc5i, mir, msgr, npc, xenl,
	colors#256, cols#80, it#8, lines#24, pairs#32767,
	acsc=``aaffggiijjkkllmmnnooppqqrrssttuuvvwwxxyyzz{{||}}~~,
	bel=^G, blink=\E[5m, bold=\E[1m, cbt=\E[Z, civis=\E[?25l,
	clear=\E[H\E[2J, cnorm=\E[?12l\E[?25h, cr=^M,
	csr=\E[%i%p1%d;%p2%dr, cub=\E[%p1%dD, cub1=^H,
	cud=\E[%p1%dB, cud1=^J, cuf=\E[%p1%dC, cuf1=\E[C,
	cup=\E[%i%p1%d;%p2%dH, cuu=\E[%p1%dA, cuu1=\E[A,
	cvvis=\E[?12;25h, dch=\E[%p1%dP, dch1=\E[P, dim=\E[2m,
	dl=\E[%p1%dM, dl1=\E[M, ech=\E[%p1%dX, ed=\E[J, el=\E[K,
	el1=\E[1K, flash=\E[?5h$<100/>\E[?5l, home=\E[H,
	hpa=\E[%i%p1%dG, ht=^I, hts=\EH, ich=\E[%p1%d@,
	il=\E[%p1%dL, il1=\E[L, ind=^J, indn=\E[%p1%dS,
	initc=\E]4;%p1%d;rgb\:%p2%{255}%*%{1000}%/%2.2X/%p3%{255}%*%{1000}%/%2.2X/%p4%{255}%*%{1000}%/%2.2X\E\\,
	invis=\E[8m, is2=\E[!p\E[?3;4l\E[4l\E>, kDC=\E[3;2~,
	kEND=\E[1;2F, kHOM=\E[1;2H, kIC=\E[2;2~, kLFT=\E[1;2D,
	kNXT=\E[6;2~, kPRV=\E[5;2~, kRIT=\E[1;2C, kb2=\EOE, kbs=^H,
	kcbt=\E[Z, kcub1=\EOD, kcud1=\EOB, kcuf1=\EOC, kcuu1=\EOA,
	kdch1=\E[3~, kend=\EOF, kent=\EOM, kf1=\EOP, kf10=\E[21~,
	kf11=\E[23~, kf12=\E[24~, kf13=\E[1;2P, kf14=\E[1;2Q,
	kf15=\E[1;2R, kf16=\E[1;2S, kf17=\E[15;2~, kf18=\E[17;2~,
	kf19=\E[18;2~, kf2=\EOQ, kf20=\E[19;2~, kf21=\E[20;2~,
	kf22=\E[21;2~, kf23=\E[23;2~, kf24=\E[24;2~,
	kf25=\E[1;5P, kf26=\E[1;5Q, kf27=\E[1;5R, kf28=\E[1;5S,
	kf29=\E[15;5~, kf3=\EOR, kf30=\E[17;5~, kf31=\E[18;5~,
	kf32=\E[19;5~, kf33=\E[20;5~, kf34=\E[21;5~,
	kf35=\E[23;5~, kf36=\E[24;5~, kf37=\E[1;6P, kf38=\E[1;6Q,
	kf39=\E[1;6R, kf4=\EOS, kf40=\E[1;6S, kf41=\E[15;6~,
	kf42=\E[17;6~, kf43=\E[18;6~, kf44=\E[19;6~,
	kf45=\E[20;6~, kf46=\E[21;6~, kf47=\E[23;6~,
	kf48=\E[24;6~, kf49=\E[1;3P, kf5=\E[15~, kf50=\E[1;3Q,
	kf51=\E[1;3R, kf52=\E[1;3S, kf53=\E[15;3~, kf54=\E[17;3~,
	kf55=\E[18;3~, kf56=\E[19;3~, kf57=\E[20;3~,
	kf58=\E[21;3~, kf59=\E[23;3~, kf6=\E[17~, kf60=\E[24;3~,
	kf61=\E[1;4P, kf62=\E[1;4Q, kf63=\E[1;4R, kf7=\E[18~,
	kf8=\E[19~, kf9=\E[20~, khome=\EOH, kich1=\E[2~,
	kind=\E[1;2B, kmous=\E[M, knp=\E[6~, kpp=\E[5~,
	kri=\E[1;2A, mc0=\E[i, mc4=\E[4i, mc5=\E[5i, meml=\El,
	memu=\Em, op=\E[39;49m, rc=\E8, rev=\E[7m, ri=\EM,
	rin=\E[%p1%dT, ritm=\E[23m, rmacs=\E(B, rmam=\E[?7l,
	rmcup=\E[?1049l, rmir=\E[4l, rmkx=\E[?1l\E>,
	rmm=\E[?1034l, rmso=\E[27m, rmul=\E[24m, rs1=\Ec,
	rs2=\E[!p\E[?3;4l\E[4l\E>, sc=\E7,
	setab=\E[%?%p1%{8}%<%t4%p1%d%e%p1%{16}%<%t10%p1%{8}%-%d%e48;5;%p1%d%;m,
	setaf=\E[%?%p1%{8}%<%t3%p1%d%e%p1%{16}%<%t9%p1%{8}%-%d%e38;5;%p1%d%;m,
	sgr=%?%p9%t\E(0%e\E(B%;\E[0%?%p6%t;1%;%?%p5%t;2%;%?%p2%t;4%;%?%p1%p3%|%t;7%;%?%p4%t;5%;%?%p7%t;8%;m,
	sgr0=\E(B\E[m, sitm=\E[3m, smacs=\E(0, smam=\E[?7h,
	smcup=\E[?1049h, smir=\E[4h, smkx=\E[?1h\E=,
	smm=\E[?1034h, smso=\E[7m, smul=\E[4m, tbc=\E[3g,
	u6=\E[%i%d;%dR, u7=\E[6n, u8=\E[?1;2c, u9=\E[c,
	vpa=\E[%i%p1%dd,
```

### Dump from `stty -a`

```
speed 9600 baud; 39 rows; 261 columns;
lflags: icanon isig iexten echo echoe -echok echoke -echonl echoctl
	-echoprt -altwerase -noflsh -tostop -flusho pendin -nokerninfo
	-extproc
iflags: -istrip icrnl -inlcr -igncr ixon -ixoff ixany imaxbel -iutf8
	-ignbrk brkint -inpck -ignpar -parmrk
oflags: opost onlcr -oxtabs -onocr -onlret
cflags: cread cs8 -parenb -parodd hupcl -clocal -cstopb -crtscts -dsrflow
	-dtrflow -mdmbuf
cchars: discard = ^O; dsusp = ^Y; eof = ^D; eol = <undef>;
	eol2 = <undef>; erase = ^?; intr = ^C; kill = ^U; lnext = ^V;
	min = 1; quit = ^\; reprint = ^R; start = ^Q; status = ^T;
	stop = ^S; susp = ^Z; time = 0; werase = ^W;

```

### References

- https://blog.jetbrains.com/platform/2025/07/the-reworked-terminal-becomes-the-default-in-2025-2/
- https://blog.jetbrains.com/idea/2025/04/jetbrains-terminal-a-new-architecture/
- https://platform.jetbrains.com/t/reworked-terminal-api-is-available-in-2025-3/3159