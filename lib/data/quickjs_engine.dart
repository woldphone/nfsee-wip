import 'dart:async';
import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';

enum ScriptState {
  ready,
  waitingForTag,
  tagAvailable,
  running,
  stopping,
  completed,
  failed,
  cancelled,
  nfcDisabled,
}

class ScriptConsoleEntry {
  final DateTime timestamp;
  final String level; // INFO, WARN, ERROR, HEX
  final String message;

  ScriptConsoleEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  String format() {
    final timeStr =
        "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
    return "[$timeStr] [$level] $message";
  }
}

class ScriptExecutionResult {
  final ScriptState finalState;
  final List<ScriptConsoleEntry> consoleLogs;
  final String? errorSummary;
  final int? errorLineNumber;
  final Duration duration;

  ScriptExecutionResult({
    required this.finalState,
    required this.consoleLogs,
    this.errorSummary,
    this.errorLineNumber,
    required this.duration,
  });
}

typedef PollNfcCallback = Future<Map<String, dynamic>?> Function();
typedef TransceiveNfcCallback = Future<String> Function(String capdu);

class QuickJsScriptEngine {
  JavascriptRuntime? _runtime;
  bool _cancelRequested = false;
  ScriptState _currentState = ScriptState.ready;
  final List<ScriptConsoleEntry> _logs = [];

  final StreamController<ScriptConsoleEntry> _logStreamController =
      StreamController<ScriptConsoleEntry>.broadcast();
  final StreamController<ScriptState> _stateStreamController =
      StreamController<ScriptState>.broadcast();

  Stream<ScriptConsoleEntry> get logStream => _logStreamController.stream;
  Stream<ScriptState> get stateStream => _stateStreamController.stream;
  ScriptState get currentState => _currentState;
  List<ScriptConsoleEntry> get logs => List.unmodifiable(_logs);

  void _setState(ScriptState newState) {
    _currentState = newState;
    _stateStreamController.add(newState);
  }

  void _appendLog(String level, String message) {
    final entry = ScriptConsoleEntry(
      timestamp: DateTime.now(),
      level: level.toUpperCase(),
      message: message,
    );
    _logs.add(entry);
    _logStreamController.add(entry);
  }

  void cancelExecution() {
    _cancelRequested = true;
    _setState(ScriptState.stopping);
    _appendLog('WARN', 'Cancellation requested by user...');
  }

  Future<ScriptExecutionResult> executeScript({
    required String scriptSource,
    required PollNfcCallback onPoll,
    required TransceiveNfcCallback onTransceive,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _logs.clear();
    _cancelRequested = false;
    final startTime = DateTime.now();
    _setState(ScriptState.running);
    _appendLog('INFO', 'Initializing QuickJS execution context...');

    _runtime = getJavascriptRuntime();

    // Register Channel Callbacks
    _runtime!.onMessage('scriptLog', (dynamic args) {
      final level = args['level']?.toString() ?? 'INFO';
      final msg = args['msg']?.toString() ?? '';
      _appendLog(level, msg);
    });

    _runtime!.onMessage('scriptState', (dynamic args) {
      final stateStr = args['state']?.toString();
      if (stateStr == 'WAITING_FOR_TAG') {
        _setState(ScriptState.waitingForTag);
      } else if (stateStr == 'TAG_AVAILABLE') {
        _setState(ScriptState.tagAvailable);
      }
    });

    _runtime!.onMessage('nfcPoll', (dynamic args) async {
      if (_cancelRequested) throw Exception('Script cancelled');
      _setState(ScriptState.waitingForTag);
      final tagData = await onPoll();
      if (_cancelRequested) throw Exception('Script cancelled');
      _setState(ScriptState.tagAvailable);
      return jsonEncode(tagData ?? {});
    });

    _runtime!.onMessage('nfcTransceive', (dynamic args) async {
      if (_cancelRequested) throw Exception('Script cancelled');
      final capdu = args['capdu']?.toString() ?? '';
      final rapdu = await onTransceive(capdu);
      if (_cancelRequested) throw Exception('Script cancelled');
      return rapdu;
    });

    // Helper JS setup including poll and transceive bindings
    const jsPreamble = '''
      var tag = null;

      function print() {
        var msg = Array.prototype.slice.call(arguments).join(' ');
        sendMessage('scriptLog', JSON.stringify({level: 'INFO', msg: msg}));
      }

      function log() {
        print.apply(null, arguments);
      }

      function warn() {
        var msg = Array.prototype.slice.call(arguments).join(' ');
        sendMessage('scriptLog', JSON.stringify({level: 'WARN', msg: msg}));
      }

      function error() {
        var msg = Array.prototype.slice.call(arguments).join(' ');
        sendMessage('scriptLog', JSON.stringify({level: 'ERROR', msg: msg}));
      }

      function hex(bytes) {
        if (!bytes) return '';
        if (typeof bytes === 'string') return bytes;
        if (Array.isArray(bytes) || bytes instanceof Uint8Array) {
          return Array.from(bytes).map(function(b) {
            return ('0' + (b & 0xFF).toString(16)).slice(-2);
          }).join('').toUpperCase();
        }
        return String(bytes);
      }

      async function poll() {
        sendMessage('scriptState', JSON.stringify({state: 'WAITING_FOR_TAG'}));
        var res = await sendMessage('nfcPoll', JSON.stringify({}));
        try {
          var data = typeof res === 'string' ? JSON.parse(res) : res;
          tag = data;
          sendMessage('scriptState', JSON.stringify({state: 'TAG_AVAILABLE'}));
          return data;
        } catch(e) {
          return null;
        }
      }

      async function transceive(capdu) {
        var res = await sendMessage('nfcTransceive', JSON.stringify({capdu: capdu}));
        return res;
      }
    ''';

    _runtime!.evaluate(jsPreamble);

    String? errorDetail;
    int? errorLine;
    ScriptState finalState = ScriptState.completed;

    final timeoutTimer = Timer(timeout, () {
      if (_currentState == ScriptState.running ||
          _currentState == ScriptState.waitingForTag ||
          _currentState == ScriptState.tagAvailable) {
        _cancelRequested = true;
        _appendLog(
            'ERROR', 'Script execution timed out after ${timeout.inSeconds}s!');
      }
    });

    try {
      final wrappedUserScript = '''
        (async function() {
          $scriptSource
        })();
      ''';

      _appendLog('INFO', 'Script execution started.');
      final evalResult = _runtime!.evaluate(wrappedUserScript);

      if (evalResult.isError) {
        throw Exception(evalResult.stringResult);
      }

      if (_cancelRequested) {
        finalState = ScriptState.cancelled;
        _appendLog('WARN', 'Script execution cancelled.');
      } else {
        finalState = ScriptState.completed;
        _appendLog('INFO', 'Script completed successfully.');
      }
    } catch (e) {
      if (_cancelRequested) {
        finalState = ScriptState.cancelled;
        _appendLog('WARN', 'Script cancelled during execution.');
      } else {
        finalState = ScriptState.failed;
        errorDetail = e.toString();
        _appendLog('ERROR', 'Script Execution Error: $errorDetail');
      }
    } finally {
      timeoutTimer.cancel();
      _runtime?.dispose();
      _runtime = null;
      _setState(finalState);
    }

    final endTime = DateTime.now();
    return ScriptExecutionResult(
      finalState: finalState,
      consoleLogs: List.from(_logs),
      errorSummary: errorDetail,
      errorLineNumber: errorLine,
      duration: endTime.difference(startTime),
    );
  }

  void dispose() {
    _logStreamController.close();
    _stateStreamController.close();
    _runtime?.dispose();
  }
}
