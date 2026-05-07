part of 'package:glue/src/app.dart';

enum _ToolPhase {
  preparing,
  awaitingApproval,
  running,
  done,
  denied,
  cancelled,
  error,
}

class _ToolCallUiState {
  final ToolCallId id;
  final String name;
  Map<String, dynamic>? args;
  _ToolPhase phase;
  _ToolCallUiState(
      {required this.id,
      required this.name,
      this.phase = _ToolPhase.preparing});

  ToolCallRenderState toRenderState() => ToolCallRenderState(
        name: name,
        args: args,
        phase: switch (phase) {
          _ToolPhase.preparing => ToolCallPhase.preparing,
          _ToolPhase.awaitingApproval => ToolCallPhase.awaitingApproval,
          _ToolPhase.running => ToolCallPhase.running,
          _ToolPhase.done => ToolCallPhase.done,
          _ToolPhase.denied => ToolCallPhase.denied,
          _ToolPhase.cancelled => ToolCallPhase.cancelled,
          _ToolPhase.error => ToolCallPhase.error,
        },
      );
}

class _TitleTarget {
  final ModelRef ref;

  const _TitleTarget({required this.ref});
}
