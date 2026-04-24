/// Events that flow through the application event bus — the unified
/// channel App uses to react to user input the [InputRouter] pre-processed
/// into intent (submit a message, cancel the current turn, scroll, resize).
sealed class AppEvent {}

class UserSubmit extends AppEvent {
  final String text;
  UserSubmit(this.text);
}

class UserCancel extends AppEvent {}

class UserScroll extends AppEvent {
  final int delta;
  UserScroll(this.delta);
}

class UserResize extends AppEvent {
  final int cols;
  final int rows;
  UserResize(this.cols, this.rows);
}
