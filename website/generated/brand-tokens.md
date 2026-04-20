<!-- Generated from cli/lib/src/ui/theme_tokens.dart. Do not edit by hand. -->
<!-- Re-run: `just site-generate` (or `dart run tool/generate_site_reference.dart` in cli/) -->

## Terminal design tokens

The TUI ships two theme modes: **minimal** (the default; quiet,
low-contrast) and **highContrast** (for environments where
default ANSI contrast is insufficient). Both modes share the
same token surface; only the ANSI chain differs.

> Tokens are ANSI styling chains — read them as calls on a
> `styled` builder. For example, `bold.yellow` means the text
> is rendered bold and foreground-yellow.

### Brand dot

The brand dot is `●` (U+25CF). It prefixes section headings,
selected list items, and prompt rows.

### Token styling

| Token           | Minimal             | High contrast      | Description                                      |
| --------------- | ------------------- | ------------------ | ------------------------------------------------ |
| `textPrimary`   | `unstyled`          | `brightWhite`      | Main transcript text.                            |
| `textSecondary` | `gray`              | `white`            | Supporting text (timestamps, inline meta).       |
| `textMuted`     | `dim`               | `gray`             | De-emphasised, dim, or placeholder copy.         |
| `accent`        | `bold.yellow`       | `bold.yellow`      | Brand accent — prompts, highlights, active chip. |
| `accentSubtle`  | `fg256(229)`        | `brightYellow`     | Quieter accent — borders, focused backgrounds.   |
| `surfaceBorder` | `gray`              | `brightWhite`      | Panel and divider lines.                         |
| `surfaceMuted`  | `bg256(236).white`  | `bg256(236).white` | Subtle panel fill.                               |
| `focus`         | `underline`         | `inverse`          | Focus indicator.                                 |
| `selection`     | `bg256(236).yellow` | `bgYellow.black`   | Selected text / row.                             |
| `info`          | `cyan`              | `brightCyan`       | Informational messages.                          |
| `success`       | `green`             | `brightGreen`      | Successful tool calls, passing tests.            |
| `warning`       | `yellow`            | `brightYellow`     | Non-fatal warnings.                              |
| `danger`        | `red`               | `brightRed`        | Errors and destructive prompts.                  |

### Tones

`GlueTone` maps each semantic role to one of the tokens above,
so components pick a tone without hardcoding a style.

| Tone      | Backing token | Description            |
| --------- | ------------- | ---------------------- |
| `accent`  | `accent`      | Brand accent.          |
| `info`    | `info`        | Informational.         |
| `success` | `success`     | Success, complete, OK. |
| `warning` | `warning`     | Non-fatal warning.     |
| `danger`  | `danger`      | Error, destructive.    |
| `muted`   | `textMuted`   | De-emphasised.         |
