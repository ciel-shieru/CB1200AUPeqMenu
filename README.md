# CB1200AU PEQ Menu Bar — v0.0.1

A native Swift/AppKit macOS menu-bar application for controlling the parametric EQ (PEQ) on supported WalkPlay-compatible CB1200AU USB HID devices.

The application is deliberately narrow and security-focused: it talks directly to USB HID through Apple's `IOKit.hid`, requires no network service, runs inside the macOS App Sandbox with Hardened Runtime, stores application data only inside its sandbox container, and uses event-driven HID connection/removal callbacks rather than polling.

## Features

- **PEQ toggle from the menu bar:** left-click the status item to toggle PEQ; the right-click dropdown also contains **Toggle PEQ**.
- **Multiple-device support:** if multiple supported CB1200AU devices are connected at startup, the app presents a picker. Later selections can be changed from the **Device** submenu without restarting.
- **Automatic single-device selection:** one discovered CB1200AU is selected automatically.
- **Hot-plug support:** unplugging the selected device leaves the app running; reconnecting is handled through macOS HID matching callbacks.
- **Built-in PEQ OFF state:** slot 1 is the captured WalkPlay flat/default profile.
- **Device-derived custom PEQ:** custom slot IDs are read from the device and are never hardcoded as a universal slot; tested devices include slot 101 and slot 255.
- **RAM-first custom-profile cache:** all eight filters and DAC/global gain are retained in memory for toggling.
- **DevicePEQ-compatible cache files:** the app writes the DevicePEQ text format plus an application-specific `Slot:` line.
- **Live cache editing:** edits to the sandbox-contained profile files are detected and loaded into RAM automatically.
- **Full verification:** PEQ writes are followed by a complete eight-filter readback and gain verification.
- **Rescan recovery:** **Rescan now** invalidates stale asynchronous work and rebuilds device/application state from scratch.
- **Offline by design:** no network client/server functionality is implemented.
- **Opt-in debug logging:** logging is completely disabled by default. Enable it with `--debug` or `CB1200AU_DEBUG=true`.
- **macOS security hardening:** App Sandbox + Hardened Runtime, with only the USB entitlement needed for sandboxed HID access.

## Supported discovery scope

The App Sandbox USB entitlement is class-wide rather than VID-specific. The application therefore adds a runtime vendor allowlist before probing the WalkPlay protocol:

```text
0104 011B 011D 0661 0663 0666 0762 0909 0D8C
2FC6 3302 34BE 35D8 36A7 373B 60C1 60E1 B445 B44D
```

Only USB devices from those vendors are sent through the protocol-probe path. A device is presented to the user as a supported CB1200AU only after the WalkPlay protocol probe succeeds.

The primary tested device is:

| Property | Tested value |
|---|---|
| Vendor ID | `0x3302` |
| Product ID | `0x12CA` |
| Product | `Hi-MAX` |
| Firmware | `0.1` |
| Transport | USB |
| HID report ID | `0x4B` |

## Version

The release version is stored in [`VERSION`](VERSION) and is currently **0.0.1**. `build-app.sh` uses this value for the bundle version and release fingerprint. Historical `debugXX` labels are development milestones only.

## Requirements

- macOS with an Apple SDK capable of building the package.
- Xcode Command Line Tools or Xcode, providing SwiftPM, `swiftc`, `codesign`, and the Apple SDK.
- A supported WalkPlay-compatible CB1200AU device attached over USB.

`Package.swift` currently declares macOS 13 as the minimum package platform. The security model targets modern sandboxed macOS operation.

## Compile and build

For the command-line binary only:

```sh
swift package clean
swift build -c release
```

For a signed `.app` bundle with App Sandbox and Hardened Runtime:

```sh
./build-app.sh
```

The bundle is emitted as:

```text
./dist/CB1200AUPeqMenu.app
```

For Developer ID signing:

```sh
CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" ./build-app.sh
```

Ad-hoc signing is useful for local development; it is not a substitute for Developer ID signing and notarization for distribution.

## Install

For local testing:

```sh
cp -R ./dist/CB1200AUPeqMenu.app /Applications/
open /Applications/CB1200AUPeqMenu.app
```

The application is an accessory/menu-bar application and does not intentionally create a Dock application window.

## First use

1. Connect one or more supported CB1200AU devices over USB.
2. Launch **CB1200AU PEQ**.
3. If more than one supported device is discovered during startup, choose the device in the startup picker.
4. If exactly one device is discovered, it is selected automatically.
5. The application probes the WalkPlay protocol and reads all eight PEQ filters plus DAC/global gain.
6. When a custom PEQ slot is active, the complete custom profile is cached in RAM and persisted to the sandbox-contained profile file.
7. When built-in slot 1 is active, the previously cached custom profile for that exact device identity is loaded from disk into RAM.

A custom profile must exist before the app can turn PEQ back on from slot 1. Load the desired custom profile with DevicePEQ or the official WalkPlay app at least once, then use **Rescan now** if necessary.

## Menu bar controls

### Left click

Left-click the status item to toggle PEQ:

- **ON → OFF:** write the captured built-in slot-1 flat profile, flush/apply, set gain, wait the required Flash interval, commit, and verify.
- **OFF → ON:** write the cached custom profile for the selected device, flush/apply, set cached gain, commit, and verify.

### Right click

The dropdown contains:

- current PEQ state;
- **Toggle PEQ**;
- **Device** submenu with all currently discovered supported CB1200AU devices;
- **Rescan now**;
- **Quit**.

The Device submenu can be used to switch which connected CB1200AU the application controls. Switching devices is blocked while a PEQ read/write operation is in progress.

## Cached profile files

All runtime application data is stored inside the App Sandbox container. The profile directory is resolved from the sandboxed Application Support location:

```text
Library/Application Support/CB1200AUPeqMenu/DevicePEQ Profiles/
```

The application never falls back to the real user's home directory and does not intentionally access arbitrary files outside the sandbox.

A typical file name is:

```text
Hi-MAX_VID-3302_PID-12CA_SERIAL-330212CA241009.txt
```

See [`docs/PROFILE_FORMAT.md`](docs/PROFILE_FORMAT.md) for the exact format and numeric conversions.

## Live profile-file editing

Advanced users can treat the cache as a lightweight text-file PEQ source:

1. Edit the current device's `.txt` file inside the app sandbox.
2. Save the file normally.
3. The application detects the file/directory change.
4. A valid profile is decoded and replaced in RAM without relaunching.
5. An invalid edit is rejected while the previous valid in-memory profile remains available.

The cache is primarily a persistence/control interface for this application; editing it does **not** immediately write the new PEQ to the device. The updated in-memory profile is used by the next PEQ enable operation.

## Debug logging

No application debug log is produced unless debugging is explicitly enabled.

Enable it from Terminal with either:

```sh
./dist/CB1200AUPeqMenu.app/Contents/MacOS/CB1200AUPeqMenu --debug
```

or:

```sh
CB1200AU_DEBUG=true /Applications/CB1200AUPeqMenu.app/Contents/MacOS/CB1200AUPeqMenu
```

When enabled, the log is stored inside the app sandbox under:

```text
Library/Application Support/CB1200AUPeqMenu/Logs/CB1200AUPeqMenu.log
```

Neither switch enabled means the application's own debug logger does nothing.

## Rescan and recovery

**Rescan now** is intentionally stronger than an ordinary device refresh. It:

- invalidates outstanding application operation generations;
- clears PEQ state and cached transient errors;
- stops the active profile watcher target;
- closes the selected HID device;
- clears the discovered device selection state;
- restarts HID discovery;
- automatically selects a newly discovered single device;
- leaves multiple-device selection to the Device menu (without repeatedly showing the startup dialog).

This is the primary recovery path for transient HID/protocol errors.

## Security at a glance

- **App Sandbox:** enabled.
- **Hardened Runtime:** enabled.
- **USB entitlement:** `com.apple.security.device.usb` only functional entitlement.
- **Network entitlements:** absent.
- **User-selected-files/all-files entitlements:** absent.
- **Apple Events, camera, microphone, Bluetooth, debugger, JIT, DYLD injection, unsigned executable memory:** no entitlement exceptions requested.
- **Persistent runtime storage:** sandbox container only.
- **HID discovery:** USB transport + runtime vendor allowlist + successful WalkPlay protocol probe.
- **Broad IORegistry fallback:** absent.
- **Debug logging:** disabled by default.

See [`docs/SECURITY.md`](docs/SECURITY.md) for the detailed security model and verification procedure.

## Troubleshooting

### More than one device is connected

Choose the desired device in the startup picker, or later from the **Device** submenu.

### A device was unplugged

The app should remain open. Reconnect the CB1200AU and let macOS deliver the HID matching event.

### The menu is stuck in an error state

Choose **Rescan now**. It is designed to invalidate stale work and restart discovery without requiring an application restart.

### The app cannot enable PEQ

The selected device needs either a readable custom profile currently active on the device or a valid cached profile inside the app sandbox. Load a custom profile with DevicePEQ/WalkPlay, then Rescan.

### Debugging a protocol problem

Launch with `--debug` or set `CB1200AU_DEBUG=true`. Without one of these, the application's debug logger is intentionally silent.

## Documentation map

- [`AGENTS.md`](AGENTS.md) — rules and invariants for future contributors/agents.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — architecture, threading, lifecycle, multi-device handling, and recovery.
- [`docs/HID_PROTOCOL.md`](docs/HID_PROTOCOL.md) — detailed WalkPlay HID protocol and exact packet rules.
- [`docs/PROFILE_FORMAT.md`](docs/PROFILE_FORMAT.md) — DevicePEQ cache schema and numeric conversions.
- [`docs/SECURITY.md`](docs/SECURITY.md) — sandbox, Hardened Runtime, USB scope, logging, and threat model.
- [`docs/PITFALLS.md`](docs/PITFALLS.md) — protocol and engineering pitfalls discovered during development.
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md) — release and development history.
- [`docs/TESTING.md`](docs/TESTING.md) — build and regression checklist.
- [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) — guidance for extending the project safely.
- [`SECURITY.md`](SECURITY.md) — concise security summary.
