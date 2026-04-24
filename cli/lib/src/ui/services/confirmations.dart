import 'package:glue/src/ui/components/modal.dart';

abstract interface class Confirmations {
  Future<bool> confirm({
    required String title,
    required List<String> bodyLines,
    List<ModalChoice> choices,
  });
}
