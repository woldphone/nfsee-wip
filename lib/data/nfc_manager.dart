import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

enum NfcSessionState {
  idle,
  polling,
  connected,
  error,
  closed,
}

class NfcTag {
  final String standard;
  final String id;
  final List<String> technologies;
  final String? atqa;
  final String? sak;
  final String? historicalBytes;
  final String? ats;
  final Map<String, dynamic> rawJson;

  NfcTag({
    required this.standard,
    required this.id,
    required this.technologies,
    this.atqa,
    this.sak,
    this.historicalBytes,
    this.ats,
    required this.rawJson,
  });

  factory NfcTag.fromNFCTag(NFCTag tag) {
    final json = tag.toJson();
    return NfcTag(
      standard: tag.standard.toString(),
      id: tag.id,
      technologies: (json['technologies'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      atqa: json['atqa']?.toString(),
      sak: json['sak']?.toString(),
      historicalBytes: json['historicalBytes']?.toString(),
      ats: json['ats']?.toString(),
      rawJson: json,
    );
  }
}

class NfcOperationResult {
  final bool success;
  final String? responseApdu;
  final String? errorMessage;

  NfcOperationResult.success(this.responseApdu)
      : success = true,
        errorMessage = null;

  NfcOperationResult.failure(this.errorMessage)
      : success = false,
        responseApdu = null;
}

class NfcManager {
  static final NfcManager _instance = NfcManager._internal();
  factory NfcManager() => _instance;
  NfcManager._internal();

  NfcSessionState _state = NfcSessionState.idle;
  NfcTag? _activeTag;

  NfcSessionState get state => _state;
  NfcTag? get activeTag => _activeTag;

  Future<NfcTag?> pollForTag({String? alertMessage}) async {
    _state = NfcSessionState.polling;
    try {
      final tag = await FlutterNfcKit.poll(iosAlertMessage: alertMessage ?? "");
      _activeTag = NfcTag.fromNFCTag(tag);
      _state = NfcSessionState.connected;
      return _activeTag;
    } catch (e) {
      _state = NfcSessionState.error;
      _activeTag = null;
      rethrow;
    }
  }

  Future<NfcOperationResult> transceiveApdu(String capduHex) async {
    if (_state != NfcSessionState.connected) {
      return NfcOperationResult.failure('No active NFC tag connected.');
    }
    try {
      final rapdu = await FlutterNfcKit.transceive(capduHex);
      return NfcOperationResult.success(rapdu);
    } catch (e) {
      return NfcOperationResult.failure(e.toString());
    }
  }

  Future<void> finishSession({String? errorMessage, String? alertMessage}) async {
    try {
      if (errorMessage != null) {
        await FlutterNfcKit.finish(iosErrorMessage: errorMessage);
      } else {
        await FlutterNfcKit.finish(iosAlertMessage: alertMessage ?? "");
      }
    } finally {
      _state = NfcSessionState.closed;
      _activeTag = null;
    }
  }
}
