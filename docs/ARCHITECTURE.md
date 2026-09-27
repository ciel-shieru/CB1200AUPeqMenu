# Architecture and Runtime Design

## Overview

The application is a single native AppKit process with four main subsystems:

1. **Menu-bar UI / state machine** — owns the status item, context menu, user actions, and human-readable PEQ state.
2. **HID manager / device wrapper** — discovers, opens, schedules, talks to, and closes supported WalkPlay HID interfaces.
3. **DevicePEQ codec/store** — converts between raw HID PEQ records, in-memory cached profiles, and human-readable DevicePEQ text.
4. **Sandbox-contained profile watcher** — watches the profile directory and active profile file for live edits.

There is deliberately no helper process, XPC service, daemon, network service, login item, or external database.

## Main-thread model

`IOHIDManager` is scheduled on the main CFRunLoop so connect/remove callbacks remain event-driven and integrated with AppKit.

Device I/O is performed through dedicated dispatch queues in the current implementation. UI state is only committed on the main thread.

A simplified flow is:

```text
macOS HID subsystem
        |
        v
IOHIDManager vendor-allowlist + USB transport matching
        |
        +---- matching callback ----> probe queue ----> WalkPlayHIDDevice
        |
        +---- removal callback -----> clear current device; stay alive

WalkPlayHIDDevice
        |
        +---- send/receive HID reports
        +---- readPEQProfile()
        +---- setPEQ()
        |
        v
DevicePEQProfileCodec / ProfileStore
        |
        +---- RAM cache
        +---- sandbox profile file
        +---- live watcher

AppDelegate
        |
        v
status item / toggle / Rescan now / alerts
```

## Discovery lifecycle

At startup:

1. Create `IOHIDManager`.
2. Apply the historical vendor allowlist through `IOHIDManagerSetDeviceMatchingMultiple`, constrained to USB transport.
3. Register matching/removal callbacks.
4. Schedule the manager on the main run loop.
5. Open the manager.
6. Perform one initial enumeration of the manager's already-known matching interfaces.
7. Deduplicate physical identities and probe each candidate with the WalkPlay version request.
8. Automatically select one confirmed device, or show the one-time startup picker when multiple confirmed devices exist.

The matching callback is the authoritative path for devices that appear later.

### Why there is still an initial enumeration

A HID interface may already exist before the application launches. The initial `IOHIDManagerCopyDevices` pass handles that case without resorting to broad IORegistry enumeration.

### Candidate selection

The manager first filters by the complete historical vendor allowlist and USB transport. It then probes candidates rather than trusting USB identity alone. A candidate is selectable only after the WalkPlay version exchange succeeds.

The current tested Hi-MAX remains `0x3302:0x12CA`, but the discovery architecture intentionally accommodates the wider historical vendor set. Among duplicate HID interfaces, a vendor-specific usage page (`>= 0xFF00`) is preferred when choosing which interface to probe first.

## Device selection UI

`WalkPlayDeviceManager` maintains a list of confirmed candidates. `AppDelegate` renders that list as the **Device** submenu and marks the current device with an NSMenu checkmark. The same manager exposes `selectCandidate(key:)` for user-driven switching. Switching closes the current HID wrapper, resets UI state through the existing callback path, and opens/probes the newly selected candidate.

The one-time startup picker uses an `NSAlert` with an `NSPopUpButton`. It is shown only when the initial confirmed-candidate count is greater than one.

## Device open / close

Opening a HID candidate:

1. `IOHIDDeviceOpen`.
2. Allocate a stable input-report buffer based on the HID input-report size.
3. Register the input-report callback.
4. Schedule the device on the main CFRunLoop.

Closing:

1. Clear any pending response callback.
2. Unregister the input callback and release the input buffer.
3. Unschedule the device from the main run loop.
4. Close the HID device.

The unschedule path explicitly avoids `DispatchQueue.main.sync` when already on the main thread. This is important during removal callbacks because a synchronous dispatch to the same queue can deadlock.

## Report request/response matching

The device wrapper keeps one pending response continuation/closure. A request installs a matcher for the expected read command, sends the request, and waits on a semaphore until an input report arrives or a timeout occurs.

Input reports are accepted only when:

- report type is input,
- report ID is `0x4B`, and
- the first byte of the copied report equals `0x4B`.

The report ID is stripped before protocol parsing.

Unexpected responses are logged and ignored by the request matcher rather than being treated as a successful response.

## Operation generations

Two lifecycle generations exist:

- HID probe generation in `WalkPlayDeviceManager`.
- application operation generation in `AppDelegate`.

A disconnect or **Rescan now** increments the relevant generation. Async HID work captures the generation at start and discards its result if the generation has changed before completion.

This prevents a stale device response from a previous connection from overwriting state for a newly connected device.

## Rescan now

`Rescan now` is designed as a complete logical reset:

1. Increment application operation generation.
2. Clear read/toggle-in-progress flags.
3. Set PEQ state to unknown.
4. Clear the in-memory custom profile, URL, and profile error.
5. Stop watching the current profile.
6. Ask the device manager to invalidate its probe generation.
7. Close/release the selected device.
8. Re-run the existing-device enumeration.
9. Ignore any stale probe or read result generated before the reset.

This is intentionally stronger than simply calling `scanExistingDevices()`.

## Disconnect/reconnect behavior

When the selected HID interface disappears:

- the wrapper is closed,
- the selected device is cleared,
- UI state changes to unknown/no-device,
- no periodic rescan is started,
- the `IOHIDManager` remains open and scheduled.

When macOS announces the next matching CB1200AU interface, the normal matching callback starts a fresh probe.

## PEQ state machine

The menu-bar state is one of:

- `unknown`
- `reading`
- `enabled`
- `disabled`
- `error(message)`

The application never toggles blindly. A click is accepted only from `enabled` or `disabled`.

After a write, the app performs a full PEQ read and derives the final state from verified device contents.

## Profile persistence lifecycle

### Custom slot active at connect

1. Read eight filters.
2. Read global/DAC gain.
3. Resolve the slot from the filter records.
4. Build an in-memory `CachedPEQProfile` containing:
   - slot ID,
   - DevicePEQ text representation,
   - exact filter write packets derived from readback,
   - global gain byte/value,
   - raw read responses.
5. Save DevicePEQ text to the sandbox-contained profile file.
6. Begin watching the profile file.

### Slot 1 active at connect

1. Read and verify the built-in flat state.
2. Look for the device-specific cached text profile.
3. Parse it and reconstruct exact write packets in RAM.
4. Watch the file for live edits.

If no custom profile exists, enable is blocked until one is supplied.

## Live file watching

The watcher monitors both:

- the profile directory, for atomic-save rename/replacement and newly created files;
- the currently selected device's profile file, for direct writes and metadata changes.

It uses `open(..., O_EVTONLY)` plus GCD `DispatchSourceFileSystemObject` sources. Events are debounced for a short period before the main thread is asked to reload the profile.

For rename/delete events, the file watcher is recreated when the expected file reappears. This handles editors that save by replacing the original inode rather than modifying it in place.

A valid edited profile is parsed and replaces the in-memory cache. A malformed profile does not destroy the last valid cached profile; instead, the error is stored and displayed.

## File permissions

The profile directory is set to `0700`, and profile files are set to `0600` where the platform/filesystem permits these POSIX attributes.

## Logging

The application writes its explicit diagnostic log to the sandbox-contained `Logs/CB1200AUPeqMenu.log`. It may also use Apple's unified logging through `NSLog`. It does not intentionally write application data to external filesystem paths.
