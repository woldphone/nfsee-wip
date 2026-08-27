class ScriptExample {
  final String title;
  final String description;
  final String code;

  ScriptExample({
    required this.title,
    required this.description,
    required this.code,
  });
}

class BuiltInScriptExamples {
  static final List<ScriptExample> examples = [
    ScriptExample(
      title: '1. Print Tag Information',
      description: 'Reads and displays basic NFC tag metadata.',
      code: '''
// Example 1: Print Tag Information
print("=== NFC Tag Information ===");
var info = await poll();
if (info) {
  print("Tag Standard:", info.standard || "Unknown");
  print("Tag ID (UID):", hex(info.id));
  print("Technologies:", JSON.stringify(info.technologies || []));
} else {
  warn("No NFC tag detected.");
}
''',
    ),
    ScriptExample(
      title: '2. Dump Unique Identifier (UID)',
      description: 'Polls tag and formats UID into colon-separated hex.',
      code: '''
// Example 2: Dump UID
print("Waiting for NFC Tag...");
var tag = await poll();
if (tag && tag.id) {
  var rawUid = hex(tag.id);
  var formattedUid = rawUid.match(/.{1,2}/g).join(':');
  print("Card UID:", formattedUid);
} else {
  error("Failed to read Card UID.");
}
''',
    ),
    ScriptExample(
      title: '3. Display Tag Technologies',
      description: 'Enumerates all active NFC hardware protocols on tag.',
      code: '''
// Example 3: Display Supported Technologies
var tag = await poll();
if (tag && tag.technologies) {
  print("Supported Tech Count:", tag.technologies.length);
  for (var i = 0; i < tag.technologies.length; i++) {
    print(" Tech [" + i + "]:", tag.technologies[i]);
  }
}
''',
    ),
    ScriptExample(
      title: '4. Display ATQA & SAK',
      description: 'Displays ISO 14443-3 Type A ATQA and SAK parameters.',
      code: '''
// Example 4: ATQA and SAK Inspection
var tag = await poll();
if (tag) {
  print("ATQA (Answer To Request A):", tag.atqa || "N/A");
  print("SAK (Select Acknowledge):", tag.sak || "N/A");
}
''',
    ),
    ScriptExample(
      title: '5. NDEF Inspection',
      description: 'Inspects NDEF messaging capabilities and record payload.',
      code: '''
// Example 5: NDEF Inspection
var tag = await poll();
if (tag && tag.ndef) {
  print("NDEF Message Count:", tag.ndef.length);
  print("NDEF Raw Records:", JSON.stringify(tag.ndef));
} else {
  warn("Tag does not contain NDEF records or NDEF is unreadable.");
}
''',
    ),
    ScriptExample(
      title: '6. Raw Hexadecimal Output',
      description: 'Formats arbitrary byte arrays into clean hexadecimal view.',
      code: '''
// Example 6: Raw Hex Utility
var testBytes = [0x00, 0xA4, 0x04, 0x00, 0x0E, 0x32, 0x50, 0x41, 0x59, 0x2E, 0x53, 0x59, 0x53, 0x2E, 0x44, 0x44, 0x46, 0x30, 0x31];
print("Raw APDU Command:", hex(testBytes));
''',
    ),
    ScriptExample(
      title: '7. Basic NFC Transceive',
      description: 'Sends SELECT PPSE APDU command to ISO-DEP payment card.',
      code: '''
// Example 7: Basic APDU Transceive (PPSE Select)
print("Please tap ISO-DEP payment card...");
await poll();
var selectPpse = "00A404000E325041592E5359532E444446303100";
print("TX -> " + selectPpse);
var rapdu = await transceive(selectPpse);
print("RX <- " + rapdu);
''',
    ),
    ScriptExample(
      title: '8. Error Handling & Timeout Recovery',
      description: 'Demonstrates graceful error handling during transceive operations.',
      code: '''
// Example 8: Safe Error Handling
try {
  print("Polling card...");
  await poll();
  var invalidApdu = "00000000";
  print("Sending invalid APDU...");
  var response = await transceive(invalidApdu);
  print("Response:", response);
} catch (e) {
  error("Caught Expected Transceive Error:", e.toString());
} finally {
  print("Cleaned up NFC session resources.");
}
''',
    ),
    ScriptExample(
      title: '9. Waiting for a Tag',
      description: 'Waits for tag presence with status updates.',
      code: '''
// Example 9: Wait for Tag
print(">>> Waiting for NFC Tag. Touch card to phone back...");
var tag = await poll();
if (tag) {
  print(">>> TAG DETECTED! UID:", hex(tag.id));
} else {
  warn(">>> Poll operation returned empty or cancelled.");
}
''',
    ),
    ScriptExample(
      title: '10. Advanced Diagnostic & APDU Dump',
      description: 'Performs multi-step APDU probe against EMV / PBOC transit cards.',
      code: '''
// Example 10: EMV / PBOC Advanced Diagnostic
print("=== EMV / PBOC Probing Diagnostic ===");
await poll();

var apps = [
  { name: "PPSE", apdu: "00A404000E325041592E5359532E444446303100" },
  { name: "1PAY.SYS.DDF01", apdu: "00A404000E315041592E5359532E444446303100" },
  { name: "Visa Credit/Debit", apdu: "00A4040007A000000003101000" },
  { name: "Mastercard", apdu: "00A4040007A000000004101000" }
];

for (var i = 0; i < apps.length; i++) {
  var app = apps[i];
  print("Testing " + app.name + "...");
  try {
    var res = await transceive(app.apdu);
    print(" [" + app.name + "] Response: " + res);
  } catch (err) {
    warn(" [" + app.name + "] Not supported or failed: " + err);
  }
}
print("=== Diagnostic Probing Complete ===");
''',
    ),
  ];
}
