/// Formatter for `glue mcp auth status` — one row per configured server
/// showing what credentials are stored and whether they're complete.
library;

import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue/src/terminal/brand.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/terminal/tty_style.dart';

enum McpAuthState { stored, missing, notLoggedIn, none }

/// Classifies a server's stored credentials into a `(kind, state)` pair.
///
/// The auth kind is read from [spec] (stdio servers are always `none`).
/// [hasBearer]/[hasOAuth] report whether the corresponding credential is
/// present in the store. Shared by `glue mcp auth status` and the `/mcp auth
/// status` slash command so the bearer/oauth → stored/missing mapping lives
/// in one place.
(String kind, McpAuthState state) classifyMcpCredential({
  required McpServerSpec spec,
  required bool hasBearer,
  required bool hasOAuth,
}) {
  final authKind = spec is McpUrlServerSpec ? spec.auth : const McpNoAuth();
  return switch (authKind) {
    McpBearerAuth() => (
      'bearer',
      hasBearer ? McpAuthState.stored : McpAuthState.missing,
    ),
    McpOAuthAuth() => (
      'oauth',
      hasOAuth ? McpAuthState.stored : McpAuthState.notLoggedIn,
    ),
    McpNoAuth() => ('none', McpAuthState.none),
  };
}

class McpAuthStatusRow {
  const McpAuthStatusRow({
    required this.id,
    required this.kind,
    required this.state,
  });
  final String id;

  /// Free-form auth kind label: 'bearer' | 'oauth' | 'none'.
  final String kind;
  final McpAuthState state;
}

String formatMcpAuthStatus(List<McpAuthStatusRow> rows, {bool? ansiEnabled}) {
  if (rows.isEmpty) return 'No MCP servers configured.';
  final ansi = ansiEnabled ?? stdoutSupportsAnsi();
  final idWidth = rows
      .map((r) => r.id.length)
      .fold<int>(0, (a, b) => a > b ? a : b);
  final dot = ansi ? '$brandDot ' : '';
  return [
    '$dot${styledOrPlain('MCP credentials', (s) => s.bold, ansiEnabled: ansi)}',
    ...rows.map((r) => _formatRow(r, idWidth, ansi: ansi)),
  ].join('\n');
}

String _formatRow(McpAuthStatusRow r, int idWidth, {required bool ansi}) {
  final id = styledOrPlain(
    r.id.padRight(idWidth),
    (s) => s.bold,
    ansiEnabled: ansi,
  );
  final marker = ansi ? '${_markerFor(r.state)} ' : '';
  final tag = styledOrPlain(
    _tagFor(r),
    _tagStyleFor(r.state),
    ansiEnabled: ansi,
  );
  return '  $id  $marker$tag';
}

String _markerFor(McpAuthState s) {
  return switch (s) {
    McpAuthState.stored => markerOk,
    McpAuthState.missing => markerWarn,
    McpAuthState.notLoggedIn => markerWarn,
    McpAuthState.none => markerInfo,
  };
}

Styled Function(Styled) _tagStyleFor(McpAuthState s) {
  return switch (s) {
    McpAuthState.stored => (x) => x.green,
    McpAuthState.missing => (x) => x.yellow,
    McpAuthState.notLoggedIn => (x) => x.yellow,
    McpAuthState.none => (x) => x.gray,
  };
}

String _tagFor(McpAuthStatusRow r) {
  return switch (r.state) {
    McpAuthState.stored => '${r.kind} (stored)',
    McpAuthState.missing => '${r.kind} (missing)',
    McpAuthState.notLoggedIn => '${r.kind} (not logged in)',
    McpAuthState.none => 'none',
  };
}
