import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nfsee/data/blocs/bloc.dart';
import 'package:nfsee/data/blocs/provider.dart';
import 'package:nfsee/data/database/database.dart';
import 'package:nfsee/data/nfc_manager.dart';
import 'package:nfsee/data/quickjs_engine.dart';
import 'package:nfsee/data/script_examples.dart';
import 'package:nfsee/l10n/app_localizations.dart';
import 'package:nfsee/utilities.dart';

class ScriptsAct extends StatefulWidget {
  final WebViewManager webview;

  ScriptsAct({required this.webview});

  @override
  State<ScriptsAct> createState() => _ScriptsActState();
}

class _ScriptsActState extends State<ScriptsAct>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final QuickJsScriptEngine _engine = QuickJsScriptEngine();
  final NfcManager _nfcManager = NfcManager();
  StreamSubscription<ScriptState>? _stateSubscription;
  StreamSubscription<ScriptConsoleEntry>? _logSubscription;

  NFSeeAppBloc? get bloc => BlocProvider.provideBloc(context);

  /// Currently running script ID
  int runningScriptId = -1;
  ScriptState _engineState = ScriptState.ready;
  final List<ScriptConsoleEntry> _consoleLogs = [];

  var currentId = -1;
  var currentName = '';
  var currentSource = '';

  ScrollController? scroll;

  @override
  void initState() {
    super.initState();
    scroll = ScrollController();

    _stateSubscription = _engine.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _engineState = state;
          if (state == ScriptState.completed ||
              state == ScriptState.failed ||
              state == ScriptState.cancelled) {
            runningScriptId = -1;
          }
        });
      }
    });

    _logSubscription = _engine.logStream.listen((entry) {
      if (mounted) {
        setState(() {
          _consoleLogs.add(entry);
        });
      }
    });
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _logSubscription?.cancel();
    _engine.dispose();
    scroll?.dispose();
    super.dispose();
  }

  void _runScript(SavedScript script) async {
    setState(() {
      runningScriptId = script.id;
      _consoleLogs.clear();
    });

    await bloc?.updateScriptUseTime(script.id);

    await _engine.executeScript(
      scriptSource: script.source,
      onPoll: () async {
        final tag = await _nfcManager.pollForTag(
          alertMessage: AppLocalizations.of(context)!.waitForCard,
        );
        return tag?.rawJson;
      },
      onTransceive: (capdu) async {
        final res = await _nfcManager.transceiveApdu(capdu);
        if (res.success) {
          return res.responseApdu ?? '';
        } else {
          throw Exception(res.errorMessage);
        }
      },
    );

    try {
      await _nfcManager.finishSession();
    } catch (_) {}
  }

  void _stopScript() {
    _engine.cancelExecution();
  }

  void _clearConsole() {
    setState(() {
      _consoleLogs.clear();
    });
  }

  void _showExamplesModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Built-in Script Examples',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: BuiltInScriptExamples.examples.length,
                  itemBuilder: (c, idx) {
                    final ex = BuiltInScriptExamples.examples[idx];
                    return ListTile(
                      title: Text(ex.title, style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(ex.description),
                      trailing: Icon(Icons.add_to_photos),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        await bloc?.addScript(ex.title, ex.code);
                        _showMessage(context, 'Added example to saved scripts!');
                      },
                    );
                  },
                ),
              )
            ],
          ),
        );
      },
    );
  }

  void _showScriptHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('NFCSee Scripting API Reference'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Available Global Functions:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('• await poll() : Scan NFC tag & return metadata JS object.'),
                Text('• await transceive(hexCapdu) : Send APDU hex string, return response RAPDU.'),
                Text('• print(...) / log(...) : Output informational messages.'),
                Text('• warn(...) : Output warning messages.'),
                Text('• error(...) : Output error messages.'),
                Text('• hex(arrayOrString) : Convert byte array to formatted hex string.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Close'),
            )
          ],
        );
      },
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: Duration(seconds: 2)),
    );
  }

  Widget _buildStateBadge(ScriptState state) {
    Color bg = Colors.grey;
    String label = 'READY';

    switch (state) {
      case ScriptState.ready:
        bg = Colors.blueGrey;
        label = 'READY';
        break;
      case ScriptState.waitingForTag:
        bg = Colors.orange;
        label = 'WAITING FOR TAG';
        break;
      case ScriptState.tagAvailable:
        bg = Colors.blue;
        label = 'TAG AVAILABLE';
        break;
      case ScriptState.running:
        bg = Colors.green;
        label = 'RUNNING';
        break;
      case ScriptState.stopping:
        bg = Colors.deepOrange;
        label = 'STOPPING';
        break;
      case ScriptState.completed:
        bg = Colors.teal;
        label = 'COMPLETED';
        break;
      case ScriptState.failed:
        bg = Colors.red;
        label = 'FAILED';
        break;
      case ScriptState.cancelled:
        bg = Colors.amber.shade800;
        label = 'CANCELLED';
        break;
      case ScriptState.nfcDisabled:
        bg = Colors.grey.shade800;
        label = 'NFC DISABLED';
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildConsoleOutput() {
    return Container(
      height: 180,
      width: double.infinity,
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LIVE SCRIPT CONSOLE',
                style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  _buildStateBadge(_engineState),
                  SizedBox(width: 8),
                  GestureDetector(
                    onTap: _clearConsole,
                    child: Icon(Icons.clear_all, color: Colors.white70, size: 18),
                  ),
                ],
              ),
            ],
          ),
          Divider(color: Colors.white24, height: 12),
          Expanded(
            child: _consoleLogs.isEmpty
                ? Center(
                    child: Text(
                      'Console logs will appear here during execution...',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: _consoleLogs.length,
                    itemBuilder: (c, idx) {
                      final logEntry = _consoleLogs[idx];
                      Color textColor = Colors.white;
                      if (logEntry.level == 'ERROR') textColor = Colors.redAccent;
                      if (logEntry.level == 'WARN') textColor = Colors.amberAccent;
                      if (logEntry.level == 'INFO') textColor = Colors.greenAccent;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Text(
                          logEntry.format(),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: textColor,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return StreamBuilder<List<SavedScript>>(
      stream: bloc!.savedScripts,
      builder: (context, snapshot) {
        final scripts = snapshot.data ?? [];

        return SingleChildScrollView(
          padding: EdgeInsets.only(bottom: 40, top: 100, left: 16, right: 16),
          controller: scroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildConsoleOutput(),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Saved Scripts (${scripts.length})',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton.icon(
                    onPressed: _showExamplesModal,
                    icon: Icon(Icons.library_books, size: 16),
                    label: Text('Examples'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              if (scripts.isEmpty)
                Container(
                  padding: EdgeInsets.all(30),
                  width: double.infinity,
                  child: Column(
                    children: [
                      Image.asset('assets/empty.png', height: 120),
                      SizedBox(height: 10),
                      Text('No custom scripts found. Click + or Examples to start!'),
                    ],
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: scripts.length,
                  itemBuilder: (c, idx) {
                    final script = scripts[idx];
                    final isThisRunning = runningScriptId == script.id;

                    return Card(
                      margin: EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              script.name,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Source Code (${script.source.length} chars)',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (isThisRunning &&
                                    (_engineState == ScriptState.running ||
                                        _engineState == ScriptState.waitingForTag))
                                  TextButton.icon(
                                    onPressed: _stopScript,
                                    icon: Icon(Icons.stop, color: Colors.red),
                                    label: Text('STOP', style: TextStyle(color: Colors.red)),
                                  )
                                else
                                  TextButton.icon(
                                    onPressed: runningScriptId == -1
                                        ? () => _runScript(script)
                                        : null,
                                    icon: Icon(Icons.play_arrow),
                                    label: Text('RUN'),
                                  ),
                                IconButton(
                                  icon: Icon(Icons.edit, size: 20),
                                  onPressed: () => _showScriptDialog(script),
                                ),
                                IconButton(
                                  icon: Icon(Icons.copy, size: 20),
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: script.source));
                                    _showMessage(context, 'Script code copied!');
                                  },
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete, size: 20, color: Colors.red),
                                  onPressed: () async {
                                    await bloc!.delScript(script.id);
                                    _showMessage(context, 'Script deleted.');
                                  },
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _addOrModifyScript() async {
    if (currentSource.trim().isEmpty) return;

    if (currentId == -1) {
      await bloc!.addScript(currentName.isEmpty ? 'New Script' : currentName, currentSource);
    } else {
      await bloc!.updateScriptContent(currentId, currentName.isEmpty ? 'Script' : currentName, currentSource);
    }

    currentId = -1;
    currentName = '';
    currentSource = '';
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _showScriptDialog([SavedScript? script]) {
    currentId = script?.id ?? -1;
    currentName = script?.name ?? '';
    currentSource = script?.source ?? '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text(currentId == -1 ? 'Add Script' : 'Edit Script'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: currentName,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Script Name',
                  ),
                  onChanged: (v) => currentName = v,
                ),
                SizedBox(height: 12),
                TextFormField(
                  initialValue: currentSource,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '// Write JavaScript NFC script here...',
                  ),
                  style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                  minLines: 6,
                  maxLines: 12,
                  onChanged: (v) => currentSource = v,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: _addOrModifyScript,
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('NFCSee Scripting Workspace'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () => _showScriptDialog(),
            tooltip: 'Add Script',
          ),
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: _showScriptHelpDialog,
            tooltip: 'API Help',
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
