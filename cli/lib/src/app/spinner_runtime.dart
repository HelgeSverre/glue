part of 'package:glue/src/app.dart';

void _startSpinnerImpl(App app) {
  if (app._spinnerTimer != null) return;
  app._spinnerFrame = 0;
  app._spinnerTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
    app._spinnerFrame = (app._spinnerFrame + 1) % App._spinnerFrames.length;
    app._render();
  });
}

void _stopSpinnerImpl(App app) {
  app._spinnerTimer?.cancel();
  app._spinnerTimer = null;
}
