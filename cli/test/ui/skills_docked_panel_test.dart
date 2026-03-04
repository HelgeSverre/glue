import 'package:glue/src/skills/skill_parser.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/docked_panel.dart';
import 'package:glue/src/ui/skills_docked_panel.dart';
import 'package:test/test.dart';

SkillMeta _skill(String name, SkillSource source) {
  return SkillMeta(
    name: name,
    description: '$name description',
    skillDir: '/tmp/$name',
    skillMdPath: '/tmp/$name/SKILL.md',
    source: source,
  );
}

void main() {
  group('SkillsDockedPanel', () {
    test('enter selects current skill and closes panel', () async {
      final panel = SkillsDockedPanel(
        skills: [
          _skill('alpha', SkillSource.project),
          _skill('beta', SkillSource.global),
        ],
      );

      panel.show();
      panel.handleEvent(KeyEvent(Key.down));
      panel.handleEvent(KeyEvent(Key.enter));

      final selected = await panel.selection;
      expect(selected, 'beta');
      expect(panel.visible, isFalse);
    });

    test('escape dismisses and completes selection with null', () async {
      final panel = SkillsDockedPanel(
        skills: [_skill('alpha', SkillSource.project)],
      );

      panel.show();
      panel.handleEvent(KeyEvent(Key.escape));

      final selected = await panel.selection;
      expect(selected, isNull);
      expect(panel.visible, isFalse);
    });

    test('render returns requested dimensions and shows title', () {
      final panel = SkillsDockedPanel(
        skills: [_skill('alpha', SkillSource.project)],
        edge: DockEdge.right,
      );

      final lines = panel.render(60, 12);
      expect(lines.length, 12);
      expect(lines.first, contains('SKILLS'));
    });

    test('empty skills enter dismisses with null selection', () async {
      final panel = SkillsDockedPanel(skills: []);
      panel.show();
      panel.handleEvent(KeyEvent(Key.enter));

      final selected = await panel.selection;
      expect(selected, isNull);
      expect(panel.visible, isFalse);
    });
  });
}
