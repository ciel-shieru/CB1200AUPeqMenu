# AGENTS.md — CB1200AU PEQ Menu Bar

## Project purpose

`CB1200AUPeqMenu` is a native Swift/AppKit macOS menu-bar application for controlling PEQ on supported WalkPlay-compatible CB1200AU USB HID devices.

The project is intentionally narrow:

- no network functionality;
- no helper daemon;
- no browser/WebHID dependency;
- direct Apple `IOKit.hid` access;
- App Sandbox + Hardened Runtime;
- runtime USB vendor allowlist followed by WalkPlay protocol probing;
- profile data only inside the App Sandbox container.

The current release is **v0.0.1**. `VERSION` is the single release-version source of truth. Do not reintroduce `debugXX` release naming.

## Non-negotiable protocol invariants

1. The built-in slot-1 flat-profile packets must remain exactly the captured 36-byte logical payloads.
2. A PEQ filter write is 36 bytes of payload plus report ID `0x4B`, therefore the IOKit output length is exactly **37 bytes**.
3. Never append a trailing `0x00` to a filter write.
4. Do not reintroduce the debug27 fixed-64-byte output padding.
5. Keep the established 1-second delay before the `01 01 00` Flash commit.
6. Do not send the destructive factory-reset command `0x17` as part of normal PEQ toggling.
7. Custom slot IDs are device-derived. Slot `101` and slot `255` are known examples, not universal constants.
8. Preserve the established PEQ read normalization semantics documented in `docs/HID_PROTOCOL.md` and `docs/PITFALLS.md`.

## Device discovery invariants

- Use `IOHIDManagerSetDeviceMatchingMultiple` for the complete runtime vendor allowlist.
- Require USB transport.
- Require a successful WalkPlay protocol probe before exposing a device as a selectable CB1200AU.
- Do not restore a broad `IORegistry` fallback.
- Device selection must remain event-driven; do not add periodic HID polling.
- One confirmed device at startup is auto-selected.
- Multiple confirmed devices at startup require one picker dialog.
- The right-click Device submenu must always expose currently discovered selectable devices.
- After startup, device switching is performed through the Device submenu without repeating the startup picker dialog.
- Unplugging the selected device must not terminate the process.

## Logging invariant

The project's application logger is **opt-in** only.

Debug logging is enabled only by either:

```text
--debug
```

or:

```text
CB1200AU_DEBUG=true
```

When neither is present, the application's debug logger must perform no output and must not create/write the debug log file.

Do not add direct `NSLog`/`print` debugging outside `DebugLog` without an explicit reason.

## Security invariants

Runtime application data must remain inside the App Sandbox container.

Do not add:

- network client/server capabilities;
- user-selected-file or all-files entitlements;
- Apple Events automation;
- camera/microphone/Bluetooth access;
- Hardened Runtime exceptions unless a demonstrated implementation requirement exists;
- arbitrary filesystem fallbacks such as absolute paths under `/Users/...`, `/tmp`, Downloads, or Desktop;
- privileged helpers;
- shelling out at runtime to manipulate HID state.

The only functional sandbox entitlement currently required is:

```xml
com.apple.security.device.usb = true
```

The USB entitlement itself is broad; keep the additional runtime VID/transport restriction in code.

## Profile-file invariants

The DevicePEQ cache:

- lives under the sandboxed Application Support `CB1200AUPeqMenu/DevicePEQ Profiles` directory;
- uses a sanitized product/VID/PID/serial-based filename;
- stores exactly eight filters, preamp/global gain, and `Slot: <0-255>`;
- is live-reloaded when the selected device's file changes;
- rejects malformed files without destroying the last known-good in-memory profile;
- is never written outside the sandbox.

## Rescan invariant

`Rescan now` is a full state reset, not a lightweight refresh. It must invalidate stale operation generations, close/release the current HID device, clear transient application state, stop the selected profile watcher target, rebuild discovery state, and recover without requiring an application restart.

## Verification before merging protocol changes

At minimum:

1. `swiftc -parse Sources/CB1200AUPeqMenu/CB1200AUPeqMenu.swift`
2. Verify all eight slot-1 writes are exactly the captured frames.
3. Verify filter writes are exactly 37 bytes including report ID.
4. Test custom → flat and flat → custom audibly.
5. Verify full eight-filter readback and gain.
6. Test one-device startup.
7. Test multiple-device startup picker.
8. Test switching devices from the menu.
9. Unplug/replug the selected device without quitting the app.
10. Exercise Rescan now during a transient error.
11. Test live profile-file editing and invalid-file recovery.
12. Verify debug logging is silent unless explicitly enabled.
13. On macOS, inspect the final entitlements and Hardened Runtime signature before distribution.

## Documentation requirements

Any protocol, security, UI, lifecycle, persistence, or device-discovery change must update the relevant documentation. Keep `README.md` user-oriented and move deep technical material into `docs/`.
