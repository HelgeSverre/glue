part of 'package:glue/src/app.dart';

/// Kick off the "pull this model?" confirmation flow for an Ollama tag.
///
/// Flow:
///   1. Ask Ollama which tags are already installed (cached; fail-soft).
///   2. If [tag] is already present, invoke [onPull] directly — no modal.
///   3. Otherwise show a [ConfirmModal]; on **Yes** stream `POST /api/pull`
///      and post progress as system messages, then invoke [onPull].
///   4. On **No** post a single "aborted" system message and leave state
///      unchanged.
///
/// Discovery failures (daemon down) skip the modal and proceed — we can't
/// confirm the model is missing, and false-positive prompts are worse
/// than an eventual 404 from the inference call.
void _confirmAndPullOllamaModelImpl(
  App app, {
  required String tag,
  required OllamaDiscovery discovery,
  required void Function() onPull,
}) {
  unawaited(() async {
    final installed = await discovery.listInstalled();
    final isPresent = installed.any((m) => m.tag == tag);
    if (installed.isEmpty || isPresent) {
      // Either we can't check (fail-soft), or it's already here — proceed.
      onPull();
      return;
    }

    app._mode = AppMode.confirming;
    app._activeModal = ConfirmModal(
      title: "Pull '$tag' from Ollama?",
      bodyLines: const [
        'Model is not installed locally.',
        'This downloads several GB and may take a while.',
      ],
      choices: const [
        ModalChoice('Yes', 'y'),
        ModalChoice('No', 'n'),
      ],
    );
    app._render();

    final idx = await app._activeModal!.result;
    app._activeModal = null;
    app._mode = AppMode.idle;

    if (idx != 0) {
      app._addSystemMessage('Pull aborted — model not switched.');
      app._render();
      return;
    }

    app._addSystemMessage("Pulling '$tag' from Ollama…");
    app._render();

    discovery.invalidateCache();

    String? lastStatus;
    OllamaPullProgress? finalFrame;
    try {
      await for (final frame in discovery.pullModel(tag)) {
        finalFrame = frame;
        if (frame.hasError) break;
        if (frame.status != lastStatus) {
          lastStatus = frame.status;
          app._addSystemMessage('  ${frame.status}');
          app._render();
        }
      }
    } catch (e) {
      app._addSystemMessage('Pull failed: $e');
      app._render();
      return;
    }

    if (finalFrame == null || finalFrame.hasError) {
      final err = finalFrame?.error ?? 'unknown error';
      app._addSystemMessage('Pull failed: $err');
      app._render();
      return;
    }

    if (!finalFrame.isSuccess) {
      app._addSystemMessage(
        'Pull ended without success (last status: ${finalFrame.status}).',
      );
      app._render();
      return;
    }

    discovery.invalidateCache();
    onPull();
  }());
}
