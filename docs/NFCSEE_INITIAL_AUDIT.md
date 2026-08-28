# NFCSee Initial Audit Report

**Date**: Baseline Setup Phase
**Project**: NFCSee (NFSee Fork)
**Platform**: Android-Focused Utility App

---

## 1. Overview & Architecture

NFCSee is a cross-platform Android utility app built using **Flutter (Dart 3.11.0)** with native **Android Gradle** bindings.

- **Frontend Frame**: Flutter (Material / Cupertino adapting UI).
- **Database / Persistence**: `drift` (SQLite ORM) managing card scan history (`dumped_records`) and user scripts (`saved_scripts`).
- **NFC Hardware Abstraction**: `flutter_nfc_kit` (v3.6.0) method channels linking Dart to Android `NfcAdapter` / Reader Mode.
- **Current Script Engine (Legacy)**: Headless `WebViewWidget` (`webview_flutter` v4.10.0) running a JS script bridge loaded from `assets/*.js` (`ber-tlv.js`, `crypto-js.js`, `reader.js`, `felica.js`, `codes.js`).
- **Target Platform**: Android (SDK 32 baseline, moving to Android 14 / SDK 34 during modernization).

---

## 2. Component Status Audit

### A. Scripting Subsystem (Legacy vs Target)
- **Current State**: Uses `webview_flutter` running an evaluation loop (`eval(source)` inside webview JS context).
- **Limitations**:
  - Asynchronous webview message passing causes race conditions (`lastRunning`, `running`).
  - No real-time streaming console log UI (logs are accumulated as strings).
  - No cancellation or execution timeout enforcement (hanging scripts freeze NFC session or require app restart).
  - No structured line numbers, syntax error highlighting, or state machine representation.
- **Target (Phase 2)**: Embedded **QuickJS Engine** (via C/FFI or Dart Isolates) providing synchronous/controlled APDU execution, instant C-level interrupt cancellation (`JS_SetInterruptHandler`), strict execution timeout, real-time logging console (`print`, `log`, `warn`, `error`, `hex`), and robust UI state indicators (`READY`, `WAITING FOR TAG`, `TAG AVAILABLE`, `RUNNING`, `STOPPING`, `COMPLETED`, `FAILED`, `CANCELLED`, `NFC DISABLED`).

### B. Application Stability & Lifecycle
- **NFC Reader Mode**: Currently raw `FlutterNfcKit.poll()` calls inside UI streams. Unhandled `TagLostException` or `PlatformException` during `transceive()` causes method channel result re-use bugs or modal sheet lockups.
- **Navigation Duplication**: Rapid tapping on bottom navigation tabs or script edit dialogs can cause state flickering or duplicate modal sheets.
- **State Restoration**: Missing clean lifecycle reset when coming back from background or when NFC hardware state changes.

### C. Build Configuration & Dependencies
- **Flutter SDK**: `3.41.2` (Dart `3.11.0`)
- **Localization**: Local ARB files in `lib/l10n` updated to generate static `app_localizations.dart`.
- **Android NDK**: NDK `27.0.12077973` and CMake `3.22.1` verified and cached in environment.
- **Baseline APK output**: `build/app/outputs/flutter-apk/app-debug.apk` built successfully.

---

## 3. Preserved vs Overhauled Components

| Component | Status | Action |
|---|---|---|
| Card Dump Database (`Drift`) | Working | **Preserve & Enhance** |
| ARB Localization system | Working | **Preserve** |
| WebView Script Execution | Obsolete | **Replace with QuickJS C/Dart FFI Engine** |
| Unhandled Tag Exceptions | Broken | **Contain & Report gracefully** |
| Navigation duplicates | Broken | **Add single-instance route guards & debouncers** |
| Tag Details UI | Partially Works | **Organize into Overview, Tech, APDU, NDEF, Memory** |

---

## 4. Baseline Build & Verification Results

- `flutter analyze`: **Clean** (0 errors).
- `flutter build apk --debug`: **SUCCESS** -> `build/app/outputs/flutter-apk/app-debug.apk`
