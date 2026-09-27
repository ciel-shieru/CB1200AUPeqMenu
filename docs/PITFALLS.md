# Development Pitfalls and Lessons Learned

This project required several rounds of protocol and lifecycle correction. These are the most important traps for future maintenance and for anyone implementing another native client for the same device family.

## 1. A one-byte packet-length error can corrupt the PEQ

The built-in flat-profile packet must be exactly:

```text
36-byte payload
+ report ID 0x4B
= 37-byte native output report
```

An extra `0x00` in the middle of the slot-1 payload made native output 38 bytes. The device accepted the write but the resulting readback was malformed and audio became a hiss.

**Rule:** validate every PEQ write packet at runtime and reject anything other than 36 payload bytes.

## 2. Do not pad WalkPlay PEQ writes to 64 bytes

The HID descriptor advertised a 64-byte maximum output size. That is not the same as the logical WalkPlay frame size.

A debug build tried 64-byte zero-padding to approximate WebHID behavior. The working solution ultimately required exact 37-byte native reports for the PEQ filter writes.

**Rule:** follow the captured application frame size, not merely the HID descriptor maximum.

## 3. Report ID is a byte in the native IOKit buffer

WebHID captures showed the logical payload. Native IOKit `IOHIDDeviceSetReport` receives a buffer beginning with report ID `0x4B` and an explicit length.

Confusing payload length with total report length caused repeated diagnostics to appear inconsistent.

**Rule:** when documenting a packet, always state both logical payload length and native report length.

## 4. Do not search for an `0A 02` trailer

A tempting implementation looked for a literal `0A 02` sequence as the end of a PEQ record. This is unsafe because `0x0A` can be part of legitimate gain/coefficient bytes.

**Rule:** use fixed offsets and fixed lengths after normalization.

## 5. The firmware can insert an `FF 00` pair

The tested device exposed responses where the record contained an extra firmware/status pattern around byte 6:

```text
... FF 00 <coefficient data> ...
```

The current working normalization removes the inserted `00` while preserving the `FF`, restoring the canonical 36-byte record.

An earlier attempt removed the `FF` itself and shifted fields incorrectly.

**Rule:** preserve the debug23-style `FF 00` handling until new device captures prove otherwise.

## 6. Do not interpret slot bytes in isolation

The device can report different metadata/slot bytes after applying the built-in flat profile. On the tested Hi-MAX, complete flat filter data + `0 dB` can coexist with a readback slot byte of `0x00`.

The code therefore recognizes the full known flat profile rather than trusting a single slot byte.

**Rule:** slot `0x00` is not automatically equivalent to OFF and not automatically safe to restore. Resolve the complete profile state first.

## 7. Custom slot IDs are not universally 101

The tested Hi-MAX custom slot was `101` (`0x65`). Another WalkPlay-compatible device was observed using `255` (`0xFF`).

**Rule:** store the real slot ID and never hardcode `101` into restore logic.

## 8. `0x0F` exists but did not work on the tested firmware

Public protocol descriptions identify `0x0F` as an active-slot command, but the tested device did not provide a useful response to the speculative query.

**Rule:** a documented command is not proof that every firmware supports a useful transaction. Prefer successful captured behavior.

## 9. Never send `0x17` as part of PEQ switching

An early development attempt added extra commands to the flat-profile path. The authoritative WalkPlay capture did not contain them, and `0x17` is associated with factory reset.

**Rule:** omit speculative/destructive commands from a normal toggle path.

## 10. Flash timing matters

The official WalkPlay implementation schedules the Flash commit one second after the register/DSP write stage. Committing too early correlated with corrupted audio even when immediate readback seemed plausible.

**Rule:** retain the one-second delay unless a new authoritative capture demonstrates a changed timing requirement.

## 11. Raw HID data and text cache are different truth layers

The binary HID coefficients are the device's authoritative DSP representation. The DevicePEQ text cache is a human-editable representation.

Repeatedly reconstructing coefficients from the text cache can introduce quantization differences. Therefore, when a custom profile is read directly from the device, the app preserves the raw filter bytes in RAM for normal re-application.

The text file is primarily for persistence and advanced editing.

## 12. Frequency conversion initially used the wrong representation

A previous formula applied a compensation factor to the raw frequency field and produced values like `73 Hz` from a device field that represented `75 Hz`.

The tested DevicePEQ export showed that the expected cache representation is the raw metadata frequency.

**Rule:** for this tested CB1200AU profile, frequency is the raw unsigned 16-bit Hz field.

## 13. Q conversion needs deliberate fixed-point handling

The raw Q field is unsigned 8.8, not a floating-point number.

The tested DevicePEQ export uses a canonical two-decimal representation, printed to three places. The app therefore canonicalizes Q before rebuilding the raw 8.8 value.

**Rule:** distinguish display rounding from binary quantization.

## 14. Unplug must not quit the app

An initial disconnect path could interact badly with main-run-loop unscheduling. The dangerous pattern was synchronously dispatching back to the main queue when removal already occurred on the main thread.

**Rule:** test close paths from both main-thread and worker-thread callers.

## 15. A new HID interface can appear after a physical reconnect

The app must remain resident after removal and allow `IOHIDManager`'s matching callback to discover the newly created HID interface.

**Rule:** do not implement unplug recovery as “quit and restart.”

## 16. `Rescan now` must invalidate old asynchronous work

A simple rescan can leave old probe/read results arriving later and overwriting the fresh state.

**Rule:** increment a generation and discard stale work before beginning a fresh scan.

## 17. Atomic editors replace files, not only modify them

Editors may write a temporary file and rename it over the original. Watching only the original inode is insufficient.

**Rule:** watch both the directory and active file and recreate the file watcher after rename/delete events.

## 18. Exact CFType bridging matters in Swift 6

Swift 6 diagnoses a conditional cast to some CoreFoundation types such as `IOHIDDevice` as always succeeding.

The current enumeration uses an explicit bridge:

```swift
(set as NSSet).map { $0 as! IOHIDDevice }
```

because `IOHIDManagerCopyDevices` is already documented to return a set of `IOHIDDevice` objects.

**Rule:** do not blindly use `as? IOHIDDevice` in this context.

## 19. App Sandbox storage paths are not ordinary home-directory paths

A sandboxed process may use `FileManager`'s Application Support URL without receiving arbitrary home-directory access. Hardcoding the pre-sandbox path into documentation or code is both confusing and dangerous.

**Rule:** resolve app-owned data through Foundation directory APIs from inside the sandbox.

## 20. The USB entitlement is broader than the device filter

`com.apple.security.device.usb` is required for sandboxed USB access but is not a per-VID/PID entitlement.

**Rule:** treat the historical vendor-ID + USB-transport filter and successful WalkPlay probe as an additional security boundary, not as a replacement for the entitlement.

## 21. Readback alone is not proof of correctness

During development, some sequences produced plausible readback yet unusable audio. Always include an actual audio sanity test when changing report framing, timing, or write order.

## 22. Preserve captured built-in profiles literally

The flat profile is a vendor/application-defined built-in state. It is safer to ship the exact captured packets than to regenerate them from a mathematically equivalent but potentially coefficient-different design.


## 12. Multiple HID devices require an explicit startup selection policy

Selecting the first matching HID interface is unsafe when more than one supported CB1200AU is attached. The release implementation therefore confirms all startup candidates through the protocol probe, automatically selects exactly one, and prompts the user only when more than one confirmed device exists. Later switching happens through the Device submenu.

## 13. A USB entitlement is not a VID allowlist

`com.apple.security.device.usb` enables sandboxed USB access but does not express a narrow per-device policy. The application must still enforce its own runtime vendor/transport filter before probing devices.

## 14. Debug logging must be opt-in

Diagnostic HID traces contain device identity and raw report data. Keeping the logger silent by default reduces accidental data collection and filesystem writes. Do not bypass the `DebugLog` gate with ad-hoc `NSLog` or `print` statements.

## 15. The menu toggle and left-click toggle must share one implementation

Duplicating the PEQ transaction logic for a new menu command creates an easy path for the two user interfaces to diverge. The release implementation routes both actions into the same `togglePEQ()` method.
