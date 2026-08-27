# NFCSee Scripting Engine Documentation

Welcome to the **NFCSee Embedded Scripting Subsystem**! NFCSee provides a high-performance JavaScript environment (powered by QuickJS via native C / Dart FFI) allowing users to interact directly with NFC hardware.

---

## Architecture Overview

```
User Script (JavaScript)
  ↓
QuickJS Engine (C / Dart FFI Environment)
  ↓
NFCSee Script API Bridge
  ↓
Android NFC Reader Mode / FlutterNfcKit
  ↓
Physical NFC Hardware Tag
```

Scripts execute inside an isolated JavaScript context with **zero DOM/WebView overhead**, enabling instant startup (~1ms) and deterministic execution.

---

## Script Execution States

The Scripting UI provides live state indicators for script execution:

| State | Description |
|---|---|
| `READY` | Engine is idle and ready to launch a script. |
| `WAITING FOR TAG` | Script called `poll()` and is waiting for card presence. |
| `TAG AVAILABLE` | NFC tag detected and connected. |
| `RUNNING` | Script logic is active. |
| `STOPPING` | Cancellation request issued by user. |
| `COMPLETED` | Execution finished cleanly without errors. |
| `FAILED` | Script encountered an unhandled error or exception. |
| `CANCELLED` | Execution stopped by user request or timeout. |
| `NFC DISABLED` | Android NFC hardware is disabled in system settings. |

---

## Global API Reference

### 1. Tag Discovery & Metadata

#### `await poll()`
Polls for NFC card presence.
- **Returns**: A JavaScript object containing tag metadata (`standard`, `id`, `technologies`, `atqa`, `sak`, `ndef`, `historicalBytes`, `ats`) or `null` if polling failed.

```javascript
var tag = await poll();
if (tag) {
  print("Tag Standard:", tag.standard);
  print("Tag UID Hex:", hex(tag.id));
}
```

---

### 2. Low-Level NFC Communication

#### `await transceive(hexCapdu)`
Sends a raw Command APDU (in hexadecimal string format) to the connected NFC card and receives the Response APDU.
- **Parameters**: `hexCapdu` (String) — e.g., `"00A404000E325041592E5359532E444446303100"`
- **Returns**: `hexRapdu` (String) — Hexadecimal response string (including Status Words SW1/SW2).

```javascript
var rapdu = await transceive("00A4040000");
print("RX <-", rapdu);
```

---

### 3. Console Logging & Utilities

#### `print(...)` / `log(...)`
Outputs informational log messages to the real-time Script Console UI.

#### `warn(...)`
Outputs yellow warning messages to the Script Console UI.

#### `error(...)`
Outputs red error messages to the Script Console UI.

#### `hex(data)`
Converts byte arrays (`Uint8Array` / Array) or raw binary strings into clean uppercase hexadecimal output.

```javascript
var bytes = [0x00, 0xA4, 0x04, 0x00];
print("APDU:", hex(bytes)); // Outputs: 00A40400
```

---

## Cancellation & Timeout Handling

- **User STOP**: Pressing **STOP** triggers an immediate cancellation signal to the QuickJS execution context, interrupting long-running loops and releasing NFC channel resources cleanly.
- **Default Timeout**: Scripts are subject to a **30-second default execution timeout**. If exceeded, the engine cancels execution, logs a timeout warning, and restores UI to `READY`.

---

## Examples Library

10 built-in diagnostic scripts are available inside the NFCSee Script Workspace under the **Examples** menu:
1. Print Tag Information
2. Dump UID
3. Display Technologies
4. Display ATQA & SAK
5. NDEF Inspection
6. Raw Hexadecimal Output
7. Basic NFC Transceive
8. Error Handling & Timeout Recovery
9. Waiting for a Tag
10. Advanced EMV / PBOC Diagnostic
