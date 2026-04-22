/// Tests for the pure-function candidate producers in
/// `lib/src/commands/arg_completers.dart`. The App class delegates to
/// these, so exercising the functions directly gives us coverage of the
/// same code that runs in production without spinning up a full App.
library;

import 'package:glue/glue.dart';
import 'package:glue/src/commands/arg_completers.dart';
import 'package:test/test.dart';

ModelDef _model(String id, String name) => ModelDef(id: id, name: name);

ProviderDef _provider(
  String id,
  String name, {
  Map<String, ModelDef> models = const {},
}) {
  return ProviderDef(
    id: id,
    name: name,
    adapter: 'openai',
    auth: const AuthSpec(kind: AuthKind.apiKey),
    models: models,
  );
}

SkillMeta _skill(String name, String description) => SkillMeta(
      name: name,
      description: description,
      skillDir: '/tmp/$name',
      skillMdPath: '/tmp/$name/SKILL.md',
      source: SkillSource.global,
    );

void main() {
  group('openArgCandidates', () {
    test('empty partial returns all 7 targets', () {
      final candidates = openArgCandidates(const [], '');
      expect(candidates, hasLength(7));
      expect(
        candidates.map((c) => c.value).toSet(),
        {'home', 'session', 'sessions', 'logs', 'skills', 'plans', 'cache'},
      );
    });

    test('prefix "s" narrows to session, sessions, skills', () {
      final candidates = openArgCandidates(const [], 's');
      expect(candidates.map((c) => c.value).toList(),
          ['session', 'sessions', 'skills']);
    });

    test('prefix with no match returns empty', () {
      expect(openArgCandidates(const [], 'xyz'), isEmpty);
    });

    test('non-empty priorArgs returns empty', () {
      expect(openArgCandidates(['home'], ''), isEmpty);
    });

    test('candidates default continues=false (arg terminal)', () {
      for (final c in openArgCandidates(const [], '')) {
        expect(c.continues, isFalse);
      }
    });
  });

  group('providerSubcommandCandidates', () {
    test('empty partial returns all 4 subcommands', () {
      final candidates = providerSubcommandCandidates('');
      expect(candidates.map((c) => c.value).toSet(),
          {'list', 'add', 'remove', 'test'});
    });

    test('list has continues=false, others have continues=true', () {
      final byValue = {
        for (final c in providerSubcommandCandidates('')) c.value: c,
      };
      expect(byValue['list']!.continues, isFalse);
      expect(byValue['add']!.continues, isTrue);
      expect(byValue['remove']!.continues, isTrue);
      expect(byValue['test']!.continues, isTrue);
    });

    test('prefix narrows to matching subcommands', () {
      expect(providerSubcommandCandidates('r').map((c) => c.value).toList(),
          ['remove']);
    });

    test('prefix with no match returns empty', () {
      expect(providerSubcommandCandidates('xyz'), isEmpty);
    });
  });

  group('providerIdCandidates', () {
    final providers = {
      'anthropic': _provider('anthropic', 'Anthropic'),
      'openai': _provider('openai', 'OpenAI'),
      'ollama': _provider('ollama', 'Ollama'),
    };

    test('empty partial returns all providers', () {
      expect(providerIdCandidates(providers, '').map((c) => c.value).toSet(),
          {'anthropic', 'openai', 'ollama'});
    });

    test('prefix "o" narrows to openai, ollama', () {
      expect(providerIdCandidates(providers, 'o').map((c) => c.value).toSet(),
          {'openai', 'ollama'});
    });

    test('descriptions carry display names', () {
      final anthropic = providerIdCandidates(providers, 'anth').first;
      expect(anthropic.description, 'Anthropic');
    });
  });

  group('modelRefCandidates', () {
    final providers = {
      'anthropic': _provider('anthropic', 'Anthropic', models: {
        'claude-sonnet-4-7': _model('claude-sonnet-4-7', 'Claude Sonnet 4.7'),
        'claude-opus-4-7': _model('claude-opus-4-7', 'Claude Opus 4.7'),
      }),
      'openai': _provider('openai', 'OpenAI', models: {
        'gpt-5': _model('gpt-5', 'GPT-5'),
      }),
    };

    test('empty partial returns empty (min-chars gate)', () {
      expect(modelRefCandidates(providers, ''), isEmpty);
    });

    test('substring "son" finds anthropic/claude-sonnet-*', () {
      final out = modelRefCandidates(providers, 'son');
      expect(out.any((c) => c.value == 'anthropic/claude-sonnet-4-7'), isTrue);
    });

    test('provider prefix "ant" finds all anthropic models', () {
      final out = modelRefCandidates(providers, 'ant');
      final values = out.map((c) => c.value).toList();
      expect(values, contains('anthropic/claude-sonnet-4-7'));
      expect(values, contains('anthropic/claude-opus-4-7'));
    });

    test('display-name substring "Opus" finds the model', () {
      final out = modelRefCandidates(providers, 'opus');
      expect(out.first.value, 'anthropic/claude-opus-4-7');
    });

    test('no match returns empty', () {
      expect(modelRefCandidates(providers, 'gemini'), isEmpty);
    });

    test('result cap enforced on large catalogs', () {
      final bigProviders = {
        'big': _provider('big', 'Big Provider', models: {
          for (var i = 0; i < 100; i++) 'model-$i': _model('model-$i', 'M$i'),
        }),
      };
      final out = modelRefCandidates(bigProviders, 'model', cap: 20);
      expect(out, hasLength(20));
    });
  });

  group('skillCandidates', () {
    final skills = [
      _skill('code-review', 'Review code changes'),
      _skill('brainstorming', 'Turn ideas into designs'),
      _skill('code-architecture-review', 'Audit structural fit'),
    ];

    test('empty partial returns all skills', () {
      expect(skillCandidates(skills, '').map((c) => c.value).toSet(),
          {'code-review', 'brainstorming', 'code-architecture-review'});
    });

    test('prefix "code" narrows to code-* skills', () {
      final out = skillCandidates(skills, 'code');
      expect(out.map((c) => c.value).toSet(),
          {'code-review', 'code-architecture-review'});
    });

    test('empty registry returns empty', () {
      expect(skillCandidates(const [], 'code'), isEmpty);
    });
  });

  group('shareArgCandidates', () {
    test('empty partial returns all share formats', () {
      final candidates = shareArgCandidates(const [], '');
      expect(
        candidates.map((c) => c.value).toList(),
        ['html', 'md', 'gist'],
      );
    });

    test('prefix narrows to matching formats', () {
      expect(shareArgCandidates(const [], 'h').map((c) => c.value).toList(),
          ['html']);
      expect(shareArgCandidates(const [], 'm').map((c) => c.value).toList(),
          ['md']);
      expect(shareArgCandidates(const [], 'g').map((c) => c.value).toList(),
          ['gist']);
    });

    test('non-empty priorArgs returns empty', () {
      expect(shareArgCandidates(['html'], ''), isEmpty);
    });
  });
}
