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
      String Function()? pathsReport,
      String Function(List<String> args)? openGlueTarget,
      String Function(List<String> args)? sessionAction,
    }) {
      return BuiltinCommands.create(
        openHelpPanel: () {},
        clearConversation: () => '',
        requestExit: () {},
        openModelPanel: () {},
        switchModelByQuery: (_) => '',
        sessionInfo: () => '',
        sessionAction: sessionAction ?? (_) => '',
        listTools: () => '',
        openHistoryPanel: openHistoryPanel ?? () {},
        historyActionByQuery: historyActionByQuery ?? (_) => '',
        openResumePanel: openResumePanel ?? () {},
        resumeSessionByQuery: resumeSessionByQuery ?? (_) => '',
        toggleDebug: () => '',
        openSkillsPanel: openSkillsPanel ?? () {},
        activateSkillByName: activateSkillByName ?? (_) => '',
        toggleApproval: () => '',
        runProviderCommand: (_) => '',
        pathsReport: pathsReport ?? () => '',
        openGlueTarget: openGlueTarget ?? (_) => '',
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

    test('/paths invokes pathsReport', () {
      var calls = 0;
      final registry = createRegistry(
        pathsReport: () {
          calls++;
          return 'GLUE_HOME  /tmp/.glue';
        },
      );

      final result = registry.execute('/paths');
      expect(result, 'GLUE_HOME  /tmp/.glue');
      expect(calls, 1);
    });

    test('/where is a hidden alias for /paths', () {
      var calls = 0;
      final registry = createRegistry(
        pathsReport: () {
          calls++;
          return 'report';
        },
      );

      final result = registry.execute('/where');
      expect(result, 'report');
      expect(calls, 1);
    });

    test('/open forwards args to openGlueTarget', () {
      List<String>? received;
      final registry = createRegistry(
        openGlueTarget: (args) {
          received = args;
          return 'Opening ${args.join(' ')}';
        },
      );

      final result = registry.execute('/open home');
      expect(result, 'Opening home');
      expect(received, ['home']);
    });

    test('/open without args still invokes openGlueTarget for usage', () {
      List<String>? received;
      final registry = createRegistry(
        openGlueTarget: (args) {
          received = args;
          return 'Usage: /open <target>';
        },
      );

      final result = registry.execute('/open');
      expect(result, 'Usage: /open <target>');
      expect(received, isEmpty);
    });

    test('/session without args delegates to sessionAction with empty list', () {
      List<String>? received;
      final registry = createRegistry(
        sessionAction: (args) {
          received = args;
          return 'Session Info';
        },
      );

      final result = registry.execute('/session');
      expect(result, 'Session Info');
      expect(received, isEmpty);
    });

    test('/session copy delegates to sessionAction with [copy]', () {
      List<String>? received;
      final registry = createRegistry(
        sessionAction: (args) {
          received = args;
          return '';
        },
      );

      registry.execute('/session copy');
      expect(received, ['copy']);
    });
  });
}
