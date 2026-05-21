/// Sealed types describing what the user must do to connect a provider.
///
/// `/provider add` inspects the flow returned by
/// [ProviderAdapter.beginInteractiveAuth] and picks the right UI:
/// [ApiKeyFlow] → masked single-input modal,
/// [DeviceCodeFlow] → URL + short code + polling spinner,
/// [PkceFlow] → (scaffolded; not implemented this pass).
library;

import 'package:glue_core/glue_core.dart';

sealed class AuthFlow {
  const AuthFlow({required this.providerId, required this.providerName});

  final String providerId;
  final String providerName;
}

/// User pastes an API key. Most providers use this.
class ApiKeyFlow extends AuthFlow {
  const ApiKeyFlow({
    required super.providerId,
    required super.providerName,
    this.envVar,
    this.envPresent,
    this.helpUrl,
  });

  /// Name of the env var that can back this key, if declared in catalog.
  final String? envVar;

  /// Current env value when [envVar] is set at runtime (for the "[using $ENV]"
  /// hint). Never logged; never displayed beyond a placeholder note.
  final String? envPresent;

  final String? helpUrl;
}

/// OAuth 2.0 device authorization grant — what GitHub Copilot uses. The user
/// visits [verificationUri], enters [userCode], and approves; we poll.
class DeviceCodeFlow extends AuthFlow {
  const DeviceCodeFlow({
    required super.providerId,
    required super.providerName,
    required this.verificationUri,
    required this.userCode,
    required this.pollInterval,
    required this.expiresAt,
    required this.progress,
  });

  final String verificationUri;
  final String userCode;
  final Duration pollInterval;
  final DateTime expiresAt;

  /// Emits [AuthFlowPolling] while waiting, then terminates with
  /// [AuthFlowSucceeded] (with the stored fields) or [AuthFlowFailed].
  final Stream<AuthFlowProgress> progress;

  /// Builds the typed proposed-core [DeviceCodeRequestedEvent] for this
  /// flow. Future surfaces (ACP server, web UI) consume this event from
  /// the session event stream rather than reading the [DeviceCodeFlow]
  /// fields directly. Today's CLI still uses the legacy fields; this
  /// method exists so new surfaces can build on the typed contract.
  DeviceCodeRequestedEvent toRequestEvent({
    required TurnId turnId,
    required int sequence,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();
    final expiresIn = expiresAt.isAfter(now)
        ? expiresAt.difference(now)
        : Duration.zero;
    return DeviceCodeRequestedEvent(
      turnId: turnId,
      timestamp: now,
      sequence: sequence,
      code: userCode,
      verificationUrl: verificationUri,
      expiresIn: expiresIn,
    );
  }
}

/// OAuth 2.0 Authorization Code + PKCE. Opens a browser to [authUrl]; a local
/// loopback HTTP server on [redirectPort] receives the callback.
///
/// Scaffolded for Gemini / Google accounts — no adapter implements it yet.
class PkceFlow extends AuthFlow {
  const PkceFlow({
    required super.providerId,
    required super.providerName,
    required this.authUrl,
    required this.state,
    required this.redirectPort,
  });

  final String authUrl;
  final String state;
  final int redirectPort;
}

/// Events emitted on [DeviceCodeFlow.progress] while the UI is waiting for
/// the user to approve in their browser.
sealed class AuthFlowProgress {
  const AuthFlowProgress();
}

class AuthFlowPolling extends AuthFlowProgress {
  const AuthFlowPolling();
}

class AuthFlowSucceeded extends AuthFlowProgress {
  const AuthFlowSucceeded({required this.fields});

  /// The credentials to store under this provider — the exact key/value shape
  /// is adapter-defined (e.g. `{github_token, copilot_token,
  /// copilot_token_expires_at}` for Copilot).
  final Map<String, String> fields;
}

class AuthFlowFailed extends AuthFlowProgress {
  const AuthFlowFailed({required this.reason});

  /// User-facing reason string. Must not include secrets.
  final String reason;
}

/// Bridge from the legacy [AuthFlowProgress] stream into the typed
/// proposed-core [DeviceCodeResolvedEvent].
///
/// Returns `null` for [AuthFlowPolling] (heartbeat — nothing to forward).
/// [AuthFlowSucceeded] becomes a success event; [AuthFlowFailed] becomes
/// a failure event carrying [AuthFlowFailed.reason].
extension AuthFlowProgressTypedEvent on AuthFlowProgress {
  DeviceCodeResolvedEvent? toResolvedEvent({
    required TurnId turnId,
    required int sequence,
    DateTime? timestamp,
  }) {
    final progress = this;
    return switch (progress) {
      AuthFlowPolling() => null,
      AuthFlowSucceeded() => DeviceCodeResolvedEvent(
        turnId: turnId,
        timestamp: timestamp ?? DateTime.now(),
        sequence: sequence,
        success: true,
      ),
      AuthFlowFailed(:final reason) => DeviceCodeResolvedEvent(
        turnId: turnId,
        timestamp: timestamp ?? DateTime.now(),
        sequence: sequence,
        success: false,
        errorMessage: reason,
      ),
    };
  }
}
