import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/context/context_budget.dart';
import 'package:glue/src/context/context_config.dart';
import 'package:test/test.dart';

void main() {
  group('ContextBudget', () {
    test('computes inputBudget as contextWindow minus reservedHeadroom', () {
      const budget = ContextBudget(
        contextWindowTokens: 100000,
        maxOutputTokens: 8192,
        reservedHeadroom: 9216,
      );
      expect(budget.inputBudget, 100000 - 9216);
    });

    test('compactAt is 80% of inputBudget by default', () {
      const budget = ContextBudget(
        contextWindowTokens: 100000,
        maxOutputTokens: 8192,
        reservedHeadroom: 9216,
      );
      expect(budget.compactAt, (budget.inputBudget * 0.80).round());
    });

    test('criticalAt is 95% of inputBudget by default', () {
      const budget = ContextBudget(
        contextWindowTokens: 100000,
        maxOutputTokens: 8192,
        reservedHeadroom: 9216,
      );
      expect(budget.criticalAt, (budget.inputBudget * 0.95).round());
    });

    test('fromModelDef uses contextWindow and maxOutputTokens from ModelDef',
        () {
      const def = ModelDef(
        id: 'test-model',
        name: 'Test Model',
        contextWindow: 200000,
        maxOutputTokens: 4096,
      );
      final budget = ContextBudget.fromModelDef(def);
      expect(budget.contextWindowTokens, 200000);
      expect(budget.maxOutputTokens, 4096);
      // headroom = maxOutput (4096) + 1024
      expect(budget.reservedHeadroom, 4096 + 1024);
    });

    test('fromModelDef falls back to defaultContextWindow when null', () {
      const def = ModelDef(id: 'local', name: 'Local');
      final budget = ContextBudget.fromModelDef(def);
      expect(budget.contextWindowTokens, defaultContextWindow);
    });

    test('fromModelDef applies ContextConfig thresholds', () {
      const def = ModelDef(
        id: 'model',
        name: 'Model',
        contextWindow: 32768,
      );
      const cfg =
          ContextConfig(compactThreshold: 0.70, criticalThreshold: 0.90);
      final budget = ContextBudget.fromModelDef(def, config: cfg);
      expect(budget.compactThreshold, 0.70);
      expect(budget.criticalThreshold, 0.90);
    });
  });
}
