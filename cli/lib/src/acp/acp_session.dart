import 'package:acp/acp.dart';
import 'package:glue/src/agent/agent_core.dart';

final class AcpSession {
  final String id;
  final String cwd;
  final AgentCore agent;
  String title;
  DateTime updatedAt;

  AcpSession({
    required this.id,
    required this.cwd,
    required this.agent,
    required this.title,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  SessionInfo toSessionInfo() => SessionInfo(
        cwd: cwd,
        sessionId: id,
        title: title,
        updatedAt: updatedAt.toIso8601String(),
      );
}
