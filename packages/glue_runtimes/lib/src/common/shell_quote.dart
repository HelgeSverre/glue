/// Single-quote escape for safe interpolation into POSIX shell
/// commands. Used by sandbox-side shell-out helpers so paths
/// containing spaces or quotes don't break the surrounding command,
/// and so user-controlled values can't inject additional commands.
///
/// Example: `shQuote("/work'space")` → `'/work'\''space'`.
String shQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";
