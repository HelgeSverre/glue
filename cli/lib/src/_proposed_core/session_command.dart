/// Sealed command hierarchy dispatched from a surface into a session.
///
/// **Status:** proposed (PR 2 of harness-layers plan). Not yet wired to
/// consumers — see `docs/plans/2026-04-29-harness-layers.md`.
///
/// The full surface→harness contract is two stream types: a [Stream] of
/// [SessionEvent]s out, a stream of [SessionCommand]s in. ACP can implement
/// it as one JSON-RPC method. Tests can replay command logs.
library;

import 'package:glue/src/_proposed_core/ids.dart';
import 'package:glue/src/_proposed_core/session_event.dart';
import 'package:glue/src/catalog/model_ref.dart';

/// Base type for all surface→harness commands.
sealed class SessionCommand {
  const SessionCommand();
}

/// Send a user message into the session.
class SendMessageCommand extends SessionCommand {
  const SendMessageCommand({
    required this.text,
    this.attachments = const [],
  });

  final String text;
  final List<Attachment> attachments;
}

/// Soft interrupt — let the current LLM call finish, but don't start
/// another tool round.
class InterruptCommand extends SessionCommand {
  const InterruptCommand();
}

/// Hard cancel — kill any in-flight tool processes and abort the turn.
class CancelCommand extends SessionCommand {
  const CancelCommand();
}

/// Resolve a pending [PermissionRequestedEvent].
class ResolvePermissionCommand extends SessionCommand {
  const ResolvePermissionCommand({
    required this.requestId,
    required this.granted,
    required this.scope,
  });

  final PermissionRequestId requestId;
  final bool granted;
  final PermissionScope scope;
}

/// Resolve a pending [DeviceCodeRequestedEvent] — the surface tells the
/// harness whether the user completed the OAuth flow in their browser.
class ResolveDeviceCodeCommand extends SessionCommand {
  const ResolveDeviceCodeCommand({required this.userCompletedFlow});

  final bool userCompletedFlow;
}

/// Switch the model used by this session for subsequent turns.
class SwitchModelCommand extends SessionCommand {
  const SwitchModelCommand({required this.model});

  final ModelRef model;
}

/// Rewind to the start of [fromTurn] and re-run from there.
class RegenerateCommand extends SessionCommand {
  const RegenerateCommand({required this.fromTurn});

  final TurnId fromTurn;
}
