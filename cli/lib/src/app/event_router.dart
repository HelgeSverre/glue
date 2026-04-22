part of 'package:glue/src/app.dart';

void _handleAppEventImpl(App app, AppEvent event) {
  switch (event) {
    case UserSubmit(:final text):
      if (app._bashMode) {
        app._handleBashSubmit(text);
      } else if (text.startsWith('/')) {
        final result = app._commands.execute(text);
        if (result != null && result.isNotEmpty) {
          app._blocks.add(_ConversationEntry.system(result));
        }
        app._render();
      } else {
        final expanded = expandFileRefs(text);
        app._ensureSessionStore();
        app._sessionManager.logEvent('user_message', {'text': expanded});
        if (!app._titleInitialRequested && !app._titleManuallyOverridden) {
          app._titleInitialRequested = true;
          app._generateTitle(expanded);
        }
        app._startAgent(
          text,
          expandedMessage: expanded != text ? expanded : null,
        );
      }

    case UserCancel():
      app._cancelAgent();

    case UserScroll(:final delta):
      app._scrollOffset = (app._scrollOffset + delta).clamp(0, 999999);
      app._render();

    case UserResize():
      app.layout.apply();
      app.terminal.clearScreen();
      // Preserve the user's scroll position across resize. The render
      // pipeline clamps out-of-range offsets, so we don't need to recompute
      // here — worst case the user drifts by a few lines because wrapping
      // changed, which is much less jarring than snapping back to the tail.
      app._render();
  }
}
