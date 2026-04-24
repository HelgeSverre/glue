import 'package:glue/src/storage/session_store.dart';

class SessionTitleStateController {
  bool _initialRequested = false;
  bool _reevaluationRequested = false;
  bool _manuallyOverridden = false;

  bool get initialRequested => _initialRequested;
  bool get reevaluationRequested => _reevaluationRequested;
  bool get manuallyOverridden => _manuallyOverridden;

  bool get shouldGenerateInitialTitle =>
      !_initialRequested && !_manuallyOverridden;

  bool get blocksReevaluation => _reevaluationRequested || _manuallyOverridden;

  void markInitialRequested() {
    _initialRequested = true;
  }

  void markReevaluationRequested() {
    _reevaluationRequested = true;
  }

  void markManualOverride() {
    _initialRequested = true;
    _reevaluationRequested = true;
    _manuallyOverridden = true;
  }

  void applyResumedSession(SessionMeta session) {
    _initialRequested = session.title != null;
    _reevaluationRequested = session.titleState == SessionTitleState.stable ||
        session.titleGenerationCount >= 2;
    _manuallyOverridden = session.titleSource == SessionTitleSource.user;
  }
}
