import 'dart:io';

import 'package:glue/src/core/environment.dart';
import 'package:glue/src/plans/plan_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('PlanStore', () {
    late Directory tempDir;
    late String home;
    late String cwd;
    late Environment environment;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('glue-plan-store-');
      home = p.join(tempDir.path, 'home');
      cwd = p.join(tempDir.path, 'workspace');
      Directory(home).createSync(recursive: true);
      Directory(cwd).createSync(recursive: true);
      environment = Environment.test(home: home, cwd: cwd);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('discovers plans from global and workspace locations', () {
      final globalPlan = File(p.join(environment.plansDir, 'global-plan.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('# Global Plan\n\nbody');
      final docsPlan = File(p.join(cwd, 'docs', 'plans', 'docs-plan.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('# Docs Plan\n\nbody');
      final rootPlan = File(p.join(cwd, 'PLAN.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('# Root Plan\n\nbody');

      globalPlan.setLastModifiedSync(DateTime(2026, 3, 2, 10));
      docsPlan.setLastModifiedSync(DateTime(2026, 3, 3, 10));
      rootPlan.setLastModifiedSync(DateTime(2026, 3, 4, 10));

      final store = PlanStore(environment: environment, cwd: cwd);
      final plans = store.listPlans();

      expect(plans.length, 3);
      expect(plans.first.title, 'Root Plan');
      expect(plans.map((p) => p.source), containsAll(['global', 'workspace']));
    });

    test('reads plan content by path', () {
      final plan = File(p.join(cwd, 'plans', 'my-plan.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('# Heading\n\nStep 1');

      final store = PlanStore(environment: environment, cwd: cwd);
      final content = store.readPlan(plan.path);

      expect(content, contains('Heading'));
      expect(content, contains('Step 1'));
    });
  });
}
