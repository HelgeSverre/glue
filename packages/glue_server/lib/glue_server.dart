/// Surface adapters that expose Glue's harness over external protocols.
///
/// Today: ACP (Agent Client Protocol). Planned: MCP (Model Context
/// Protocol). See `docs/plans/2026-02-27-acp-webui.md` and
/// `docs/plans/2026-04-29-mcp-server.md`.
///
/// This package depends only on `glue_core` for typed messages — it has
/// **no** runtime dependency on `glue_harness` or `glue_strategies`.
/// The harness wires a server up by feeding `SessionEvent`s into the
/// server's input and reading dispatched `SessionCommand`s from its
/// output. That keeps the protocol surface independent of which
/// harness/runtime is on the other side.
library;

export 'package:glue_server/src/acp/event_mapping.dart';
export 'package:glue_server/src/acp/messages.dart';
export 'package:glue_server/src/jsonrpc/codec.dart';
export 'package:glue_server/src/jsonrpc/messages.dart';
export 'package:glue_server/src/jsonrpc/transport.dart';
