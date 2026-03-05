import 'package:test/test.dart';

import 'package:glue/src/commands/builtin_commands.dart';

void main() {
  group('BuiltinCommands', () {
    test('/skills without args opens panel', () {
      var opened = 0;
      String? activated;

      final registry = BuiltinCommands.create(
        openHelpPanel: () {},
        clearConversation: () => '',
        requestExit: () {},
        openModelPanel: () {},
        switchModelByQuery: (_) => '',
        sessionInfo: () => '',
        listTools: () => '',
        openHistoryPanel: () {},
        openResumePanel: () {},
        openDevTools: () => '',
        toggleDebug: () => '',
        openSkillsPanel: () {
          opened++;
        },
        activateSkillByName: (name) {
          activated = name;
          return 'Activating $name';
        },
        openPlansPanel: () {},
      );

      final result = registry.execute('/skills');
      expect(result, '');
      expect(opened, 1);
      expect(activated, isNull);
    });

    test('/skills with args activates skill directly', () {
      var opened = 0;
      String? activated;

      final registry = BuiltinCommands.create(
        openHelpPanel: () {},
        clearConversation: () => '',
        requestExit: () {},
        openModelPanel: () {},
        switchModelByQuery: (_) => '',
        sessionInfo: () => '',
        listTools: () => '',
        openHistoryPanel: () {},
        openResumePanel: () {},
        openDevTools: () => '',
        toggleDebug: () => '',
        openSkillsPanel: () {
          opened++;
        },
        activateSkillByName: (name) {
          activated = name;
          return 'Activating $name';
        },
        openPlansPanel: () {},
      );

      final result = registry.execute('/skills code-review');
      expect(result, 'Activating code-review');
      expect(opened, 0);
      expect(activated, 'code-review');
    });
  });
}
