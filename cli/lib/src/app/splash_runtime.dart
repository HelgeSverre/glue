part of 'package:glue/src/app.dart';

void _startSplashAnimationImpl(App app) {
  app._liquidSim ??= LiquidSim();
  if (app._splashTimer != null) return;
  app._splashTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
    if (app._gooExplosion != null) {
      app._gooExplosion!.step();
      if (app._gooExplosion!.isDone) {
        app._stopSplashAnimation();
      }
      app._render();
      return;
    }
    app._liquidSim!.step();
    if (app._liquidSim!.isActive) app._render();
  });
}

void _stopSplashAnimationImpl(App app) {
  app._splashTimer?.cancel();
  app._splashTimer = null;
  app._liquidSim = null;
  app._gooExplosion = null;
}

void _triggerExplosionImpl(App app) {
  final viewH = app.layout.outputBottom - app.layout.outputTop + 1;
  app._gooExplosion = GooExplosion(
    viewportWidth: app.terminal.columns,
    viewportHeight: viewH,
    originX: app._splashOriginCol,
    originY: app._splashOriginRow - app.layout.outputTop,
  );
  app._liquidSim = null;
}

void _handleSplashClickImpl(App app, int screenX, int screenY) {
  if (app._gooExplosion != null) return;
  final sim = app._liquidSim;
  if (sim == null) return;
  final localX = screenX - app._splashOriginCol;
  final localY = screenY - app._splashOriginRow;
  if (localX >= 0 &&
      localX < mascotRenderWidth &&
      localY >= 0 &&
      localY < mascotRenderHeight) {
    sim.impulse(localX, localY);
    if (sim.shouldExplode) {
      app._triggerExplosion();
    }
    app._render();
  }
}

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
