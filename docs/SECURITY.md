# Security Architecture and Hardening

## Security goals

The application is designed as a least-privilege local USB utility. Its security goals are:

- no network communication;
- no cloud services;
- no external helper or daemon;
- no arbitrary file access;
- no broad HID enumeration beyond the historical vendor allowlist, USB transport, and successful WalkPlay probe;
- no factory-reset capability in normal PEQ operation;
- strong code-signing/runtime protections;
- containment of persistent application data inside the App Sandbox;
- resilience against malformed HID responses and stale asynchronous operations.

## App Sandbox

The application enables:

```xml
com.apple.security.app-sandbox = true
```

All explicit file I/O is rooted at `FileManager`'s Application Support URL, which in a sandboxed app resolves inside the app container. There is no code path that falls back to a real home-directory path.

The application uses two subdirectories:

```text
CB1200AUPeqMenu/
├── DevicePEQ Profiles/
└── Logs/
```

No external profile path is supported by design.

### Why there is no user-selected-file entitlement

The app has no UI that asks the user to grant arbitrary filesystem access. The advanced-edit workflow is intentionally limited to the app-owned cached profile file in the sandbox.

## USB entitlement

The application enables:

```xml
com.apple.security.device.usb = true
```

This is the required App Sandbox capability for the USB HID interaction used by the app. The entitlement itself is broader than one VID/PID, so the application adds a second restriction in code.

## HID boundary

The manager uses `IOHIDManagerSetDeviceMatchingMultiple` with the historical vendor allowlist and USB transport. The current runtime vendor allowlist is:

```text
0104 011B 011D 0661 0663 0666 0762 0909 0D8C
2FC6 3302 34BE 35D8 36A7 373B 60C1 60E1 B445 B44D
```

This is a runtime restriction layered on top of the class-wide USB sandbox entitlement. It is deliberately not reduced to only the currently tested `0x3302:0x12CA` identity.

The previous broad IORegistry fallback has been removed. A `nil` result from `IOHIDManagerCopyDevices` is treated as an empty/not-ready state, not as a reason to enumerate the entire IORegistry.

The app then requires a successful WalkPlay version probe before selecting an interface. Multiple confirmed devices remain visible in the Device submenu and can be switched deliberately by the user.

## Hardened Runtime

The build uses:

```text
codesign --options runtime
```

No Hardened Runtime exceptions are requested.

In particular, the app does not request exceptions for:

- JIT/writable+executable memory;
- unsigned executable memory;
- DYLD environment variables;
- library-validation bypass;
- debugger/task-port access;
- Apple Events;
- camera/microphone;
- Bluetooth;
- location;
- address-book/calendar/photos/media libraries;
- all-files access;
- user-selected files;
- network client/server access.

## Signing

Local testing may use ad-hoc signing. Distribution should use a Developer ID Application identity and the normal notarization/Gatekeeper process.

Commands worth checking on a real macOS build include:

```sh
codesign -d --entitlements :- ./dist/CB1200AUPeqMenu.app/Contents/MacOS/CB1200AUPeqMenu
codesign -d -vvv ./dist/CB1200AUPeqMenu.app
codesign --verify --strict --verbose=2 ./dist/CB1200AUPeqMenu.app
```

For a distribution build, also validate the notarized artifact rather than assuming local codesign success implies notarization success.

## File-system hardening

The profile directory and files are reduced to:

- directory: `0700`
- file: `0600`

The profile writer uses a temporary file and replacement/move within the same sandbox-owned directory to minimize partial-file exposure.

Filenames are generated from sanitized device product/serial metadata. The sanitization allows only alphanumerics, `-`, `_`, and `.`, removes leading/trailing dots, and length-bounds the result.

## Input validation

HID responses are untrusted input. The parser:

- verifies minimum/expected lengths;
- verifies command IDs and filter indices;
- verifies that all eight filter records are present;
- constrains frequency, gain, and Q ranges when constructing packets from text;
- rejects unsupported filter types;
- rejects invalid custom slot IDs;
- rejects inconsistent slot IDs across filters;
- rejects ambiguous slot `0` unless the full known flat-profile pattern is present.

## Protocol safety

The app deliberately does not expose factory reset functionality.

The `0x17` command is excluded from PEQ toggling even though an earlier development build temporarily experimented with extra control commands. Those experiments were removed after the authoritative WalkPlay capture showed the required flat-profile sequence did not contain them.

## Concurrency and stale-state protection

Disconnects and manual rescans invalidate generation counters. Results from stale asynchronous operations are ignored.

This prevents a late HID response from an old connection from repopulating the state of a new connection.

The selected HID device's close path avoids main-thread self-synchronization during removal callbacks.

When multiple supported devices are connected, the startup picker and Device submenu make target selection explicit rather than silently assigning the first HID match. Menu switching is blocked while a PEQ read/write operation is active.

## File watcher security

The live profile watcher only opens paths generated by `DevicePEQProfileStore` inside the sandbox profile directory. It does not follow arbitrary user-provided paths.

The current watcher uses vnode dispatch sources rather than a broad filesystem monitor. Debounced reloads reduce repeated parsing during atomic-save sequences.

## Logging/privacy

Application debug logging is opt-in. It is enabled only when the process receives `--debug` or `CB1200AU_DEBUG=true`. If neither condition is present, `DebugLog.info` returns before opening or writing the log file.

When enabled, explicit application logs are written inside the sandbox. The log contains device identifiers and packet bytes for debugging protocol behavior, so it should be treated as diagnostic data.

The application does not intentionally log credentials, network secrets, or arbitrary external file contents.

## Threats this design reduces

- accidental access to unrelated user files;
- accidental network egress;
- accidental access to unrelated HID devices;
- persistence of data outside the app container;
- injection through common dynamic-library/runtime paths;
- stale asynchronous state after USB disconnect/reconnect;
- misuse of destructive protocol commands;
- malformed text profiles causing out-of-range protocol values.

## Remaining trust assumptions

The design does not claim to make the firmware trustworthy. The USB device and its firmware remain outside the process trust boundary.

The application must also trust Apple's HID and sandbox enforcement and the integrity of its own signed executable.
