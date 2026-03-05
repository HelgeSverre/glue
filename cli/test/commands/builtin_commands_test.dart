import 'package:test/test.dart';

import 'package:glue/src/commands/builtin_commands.dart';
import 'package:glue/src/commands/slash_commands.dart';

void main() {
  group('BuiltinCommands', () {
    SlashCommandRegistry createRegistry({
      void Function()? openHistoryPanel,
      String Function(String query)? historyActionByQuery,
      void Function()? openSkillsPanel,
      String Function(String name)? activateSkillByName,
      void Function()? openResumePanel,
      String Function(String query)? resumeSessionByQuery,
      void Function()? openPlansPanel,
      String Function(String query)? openPlanByQuery,
    }) {
      return BuiltinCommands.create(
        openHelpPanel: () {},
        clearConversation: () => '',
        requestExit: () {},
        openModelPanel: () {},
        switchModelByQuery: (_) => '',
        sessionInfo: () => '',
        listTools: () => '',
        openHistoryPanel: openHistoryPanel ?? () {},
        historyActionByQuery: historyActionByQuery ?? (_) => '',
        openResumePanel: openResumePanel ?? () {},
        resumeSessionByQuery: resumeSessionByQuery ?? (_) => '',
        openDevTools: () => '',
        toggleDebug: () => '',
        openSkillsPanel: openSkillsPanel ?? () {},
        activateSkillByName: activateSkillByName ?? (_) => '',
        openPlansPanel: openPlansPanel ?? () {},
        openPlanByQuery: openPlanByQuery ?? (_) => '',
      );
    }

    test('/skills without args opens panel', () {
      var opened = 0;
      String? activated;

      final registry = createRegistry(
        openSkillsPanel: () => opened++,
        activateSkillByName: (name) {
          activated = name;
          return 'Activating $name';
        },
      );

      final result = registry.execute('/skills');
      expect(result, '');
      expect(opened, 1);
      expect(activated, isNull);
    });

    test('/skills with args activates skill directly', () {
      var opened = 0;
      String? activated;

      final registry = createRegistry(
        openSkillsPanel: () => opened++,
        activateSkillByName: (name) {
          activated = name;
          return 'Activating $name';
        },
      );

      final result = registry.execute('/skills code-review');
      expect(result, 'Activating code-review');
      expect(opened, 0);
      expect(activated, 'code-review');
    });

    test('/history without args opens panel', () {
      var opened = 0;
      String? query;
      final registry = createRegistry(
        openHistoryPanel: () => opened++,
        historyActionByQuery: (q) {
          query = q;
          return 'Forking from $q';
        },
      );

      final result = registry.execute('/history');
      expect(result, '');
      expect(opened, 1);
      expect(query, isNull);
    });

    test('/history with args delegates to historyActionByQuery', () {
      var opened = 0;
      String? query;
      final registry = createRegistry(
        openHistoryPanel: () => opened++,
        historyActionByQuery: (q) {
          query = q;
          return 'Forking from $q';
        },
      );

      final result = registry.execute('/history 3');
      expect(result, 'Forking from 3');
      expect(opened, 0);
      expect(query, '3');
    });

    test('/resume without args opens panel', () {
      var opened = 0;
      String? query;
      final registry = createRegistry(
        openResumePanel: () => opened++,
        resumeSessionByQuery: (q) {
          query = q;
          return 'Resuming $q';
        },
      );

      final result = registry.execute('/resume');
      expect(result, '');
      expect(opened, 1);
      expect(query, isNull);
    });

    test('/resume with args delegates to resumeSessionByQuery', () {
      var opened = 0;
      String? query;
      final registry = createRegistry(
        openResumePanel: () => opened++,
        resumeSessionByQuery: (q) {
          query = q;
          return 'Resuming $q';
        },
      );

      final result = registry.execute('/resume abc123');
      expect(result, 'Resuming abc123');
      expect(opened, 0);
      expect(query, 'abc123');
    });

    test('/plans without args opens panel', () {
      var opened = 0;
      String? query;
      final registry = createRegistry(
        openPlansPanel: () => opened++,
        openPlanByQuery: (q) {
          query = q;
          return 'Opening $q';
        },
      );

      final result = registry.execute('/plans');
      expect(result, '');
      expect(opened, 1);
      expect(query, isNull);
    });

    test('/plans with args delegates to openPlanByQuery', () {
      var opened = 0;
      String? query;
      final registry = createRegistry(
        openPlansPanel: () => opened++,
        openPlanByQuery: (q) {
          query = q;
          return 'Opening $q';
        },
      );

      final result = registry.execute('/plans auth split');
      expect(result, 'Opening auth split');
      expect(opened, 0);
      expect(query, 'auth split');
    });
  });
}
