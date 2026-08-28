import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nfsee/data/blocs/bloc.dart';
import 'package:nfsee/data/blocs/provider.dart';
import 'package:nfsee/data/nfc_manager.dart';
import 'package:nfsee/models.dart';
import 'package:nfsee/ui/home.dart';
import 'package:nfsee/ui/scripts.dart';
import 'package:nfsee/ui/settings.dart';
import 'package:nfsee/utilities.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:nfsee/l10n/app_localizations.dart';

void main() => runApp(NFSeeApp());

class NFSeeApp extends StatefulWidget {
  @override
  State<NFSeeApp> createState() => _NFSeeAppState();
}

class _NFSeeAppState extends State<NFSeeApp> {
  late NFSeeAppBloc bloc;

  @override
  void initState() {
    bloc = NFSeeAppBloc();
    super.initState();
  }

  @override
  Widget build(context) {
    return BlocProvider(
      bloc: bloc,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        onGenerateTitle: (context) {
          return S(context).homeScreenTitle;
        },
        theme: ThemeData(
          brightness: Brightness.light,
          primarySwatch: Colors.orange,
          platform: TargetPlatform.android,
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.orange,
          platform: TargetPlatform.android,
        ),
        builder: (context, child) {
          var themeData = CupertinoThemeData();
          if (MediaQuery.of(context).platformBrightness == Brightness.dark) {
            themeData =
                CupertinoThemeData(scaffoldBackgroundColor: Colors.grey[850]);
          }
          return CupertinoTheme(
            data: themeData,
            child: Material(child: child),
          );
        },
        home: PlatformAdaptingHomePage(),
      ),
    );
  }
}

class PlatformAdaptingHomePage extends StatefulWidget {
  @override
  State<PlatformAdaptingHomePage> createState() =>
      _PlatformAdaptingHomePageState();
}

class _PlatformAdaptingHomePageState extends State<PlatformAdaptingHomePage> {
  late HomeAct home;
  var _reading = false;
  Exception? error;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final NfcManager _nfcManager = NfcManager();

  PageController? topController;
  WebViewManager webview = WebViewManager();
  StreamSubscription? _webViewListener;
  int currentTop = 1;

  NFSeeAppBloc get bloc => BlocProvider.provideBloc(context);

  @override
  void initState() {
    super.initState();
    _initSelf();
  }

  @override
  void reassemble() {
    super.reassemble();
    _initSelf();
  }

  void _initSelf() {
    _webViewListener =
        webview.stream(WebViewOwner.Main).listen(_onReceivedMessage);
    topController = PageController(
      initialPage: currentTop,
    );
  }

  @override
  void dispose() {
    topController!.dispose();
    super.dispose();
    _webViewListener?.cancel();
    _webViewListener = null;
  }

  void showSnackbar(SnackBar snackBar) {
    if (_scaffoldMessengerKey.currentState != null) {
      _scaffoldMessengerKey.currentState!.showSnackBar(snackBar);
    }
  }

  void _onReceivedMessage(WebViewEvent ev) async {
    if (ev.reload) return;
    if (ev.message == null) return;

    try {
      var scriptModel = ScriptDataModel.fromJson(json.decode(ev.message!));
      log('[Main] Received action ${scriptModel.action} from script');
      switch (scriptModel.action) {
        case 'poll':
          error = null;
          try {
            final tag = await _nfcManager.pollForTag(
                alertMessage: S(context).waitForCard);
            final json = tag?.rawJson ?? {};

            try {
              final ndef = await _nfcManager.readNdefRawRecords();
              json["ndef"] = ndef;
            } on Exception catch (e) {
              json["ndef"] = null;
              log('Silent readNDEF error: $e');
            }

            await webview.run("pollCallback(${jsonEncode(json)})");
          } on Exception catch (e) {
            error = e;
            log('Poll error: $e');
            _closeReadModal(context);
            showSnackbar(SnackBar(
                content: Text('${S(context).readFailed}: $e')));
            await webview.run("pollErrorCallback('${e.toString()}')");
          }
          break;

        case 'transceive':
          try {
            log('TX: ${scriptModel.data}');
            final res = await _nfcManager.transceiveApdu(scriptModel.data as String);
            if (res.success) {
              log('RX: ${res.responseApdu}');
              await webview.run("transceiveCallback('${res.responseApdu}')");
            } else {
              throw Exception(res.errorMessage);
            }
          } on Exception catch (e) {
            error = e;
            log('Transceive error: $e');
            _closeReadModal(context);
            showSnackbar(SnackBar(
                content: Text('${S(context).readFailed}: $e')));
            await webview.run("transceiveErrorCallback('${e.toString()}')");
          }
          break;

        case 'report':
          _closeReadModal(context);
          await bloc.addDumpedRecord(jsonEncode(scriptModel.data));
          home.scrollToNewCard();
          break;

        case 'finish':
          try {
            await _nfcManager.finishSession(
              errorMessage: error != null ? S(context).readFailed : null,
              alertMessage: error == null ? S(context).readSucceeded : null,
            );
            error = null;
          } catch (e) {
            log('Finish error caught: $e');
          }
          break;

        case 'log':
          log('Log from script: ${scriptModel.data.toString()}');
          break;

        default:
          log('Unknown action ${scriptModel.action}');
          break;
      }
    } catch (e) {
      log('Webview message parse exception caught: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = BottomNavigationBar(
      currentIndex: currentTop,
      onTap: (e) async {
        setState(() {
          currentTop = e;
        });
        if (e == 0) {
          webviewOwner = WebViewOwner.Script;
        } else {
          webviewOwner = WebViewOwner.Main;
        }
        await webview.reload();
        topController!.animateToPage(e,
            duration: Duration(milliseconds: 500), curve: Curves.ease);
      },
      items: <BottomNavigationBarItem>[
        BottomNavigationBarItem(
          icon: Icon(Icons.code),
          label: S(context).scriptTabTitle,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.nfc),
          label: S(context).scanTabTitle,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: S(context).settingsTabTitle,
        ),
      ],
    );

    final top = _buildTop(context);
    final webviewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel("nfsee",
          onMessageReceived: webview.javaScriptCallback)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: webview.onWebviewPageLoad,
      ));
    webview.setWebviewCtrl(webviewController);

    final stack = Stack(children: <Widget>[
      Offstage(
        offstage: true,
        child: WebViewWidget(controller: webviewController),
      ),
      top
    ]);

    return Scaffold(
      body: stack,
      bottomNavigationBar: bottom,
    );
  }

  Widget _buildTop(context) {
    final scripts = ScriptsAct(webview: webview);
    final home = HomeAct(readCard: () {
      return _readTag(this.context);
    });
    this.home = home;
    final settings = SettingsAct();
    return PageView(
      controller: topController,
      physics: NeverScrollableScrollPhysics(),
      children: <Widget>[scripts, home, settings],
      onPageChanged: (page) {
        setState(() {
          currentTop = page;
        });
      },
    );
  }

  Future<bool> _readTag(BuildContext context) async {
    assert(!_reading);

    _reading = true;
    Future modal;
    if (defaultTargetPlatform == TargetPlatform.android) {
      modal = showModalBottomSheet(
        context: context,
        builder: _buildReadModal,
      );
    } else {
      modal = Future.value(true);
    }

    final script = await rootBundle.loadString('assets/read.js');
    await webview.reload();
    await webview.run(script);

    bool cardRead = true;
    if ((await modal) != true) {
      await webview.run("pollErrorCallback('User cancelled operation')");
      cardRead = false;
    }

    _reading = false;
    return cardRead;
  }

  void _closeReadModal(BuildContext context) {
    if (_reading && defaultTargetPlatform != TargetPlatform.iOS) {
      Navigator.of(context).pop(true);
    }
  }

  Widget _buildReadModal(BuildContext context) {
    return Container(
        child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  S(context).waitForCard,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                ),
                SizedBox(height: 10),
                Image.asset('assets/read.webp', height: 200),
              ],
            )));
  }
}

const String DEFAULT_CONFIG = '{}';
