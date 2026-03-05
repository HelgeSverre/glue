part of 'app.dart';

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
        if (!app._titleGenerated) {
          app._titleGenerated = true;
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
      app._scrollOffset = 0;
      app._render();
  }
}
