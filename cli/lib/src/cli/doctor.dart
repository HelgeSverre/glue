import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/doctor/doctor.dart';

class DoctorCommand extends Command<int> {
  DoctorCommand() {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Include informational findings (e.g., empty session directories).',
    );
  }

  @override
  String get name => 'doctor';

  @override
  String get description => 'Inspect Glue installation and config health.';

  @override
  Future<int> run() async {
    final report = runDoctor(Environment.detect());
    stdout.write(renderDoctorReport(
      report,
      verbose: argResults!.flag('verbose'),
    ));
    return report.hasErrors ? 1 : 0;
  }
}
