import 'package:flutter_test/flutter_test.dart';
import 'package:nfsee/data/nfc_manager.dart';
import 'package:nfsee/data/quickjs_engine.dart';
import 'package:nfsee/data/script_examples.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScriptConsoleEntry & ScriptExecutionResult Unit Tests', () {
    test('ScriptConsoleEntry formatting', () {
      final now = DateTime(2025, 1, 1, 14, 30, 45);
      final entry = ScriptConsoleEntry(
        timestamp: now,
        level: 'INFO',
        message: 'Test log message',
      );

      expect(entry.format(), equals('[14:30:45] [INFO] Test log message'));
    });

    test('ScriptExecutionResult properties', () {
      final now = DateTime.now();
      final entry = ScriptConsoleEntry(timestamp: now, level: 'INFO', message: 'OK');
      final result = ScriptExecutionResult(
        finalState: ScriptState.completed,
        consoleLogs: [entry],
        duration: const Duration(milliseconds: 150),
      );

      expect(result.finalState, equals(ScriptState.completed));
      expect(result.consoleLogs.length, equals(1));
      expect(result.duration.inMilliseconds, equals(150));
    });
  });

  group('NfcManager Abstraction Tests', () {
    test('NfcManager initial state should be idle', () {
      final nfcManager = NfcManager();
      expect(nfcManager.state, equals(NfcSessionState.idle));
      expect(nfcManager.activeTag, isNull);
    });

    test('NfcOperationResult success and failure formatting', () {
      final successResult = NfcOperationResult.success('9000');
      expect(successResult.success, isTrue);
      expect(successResult.responseApdu, equals('9000'));
      expect(successResult.errorMessage, isNull);

      final failResult = NfcOperationResult.failure('Tag Lost');
      expect(failResult.success, isFalse);
      expect(failResult.errorMessage, equals('Tag Lost'));
    });
  });

  group('BuiltInScriptExamples Sanity Check', () {
    test('Should ship 10 valid example scripts', () {
      expect(BuiltInScriptExamples.examples.length, equals(10));
      for (final example in BuiltInScriptExamples.examples) {
        expect(example.title.isNotEmpty, isTrue);
        expect(example.description.isNotEmpty, isTrue);
        expect(example.code.isNotEmpty, isTrue);
      }
    });
  });
}
