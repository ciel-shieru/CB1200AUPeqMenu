# Security Summary

CB1200AU PEQ v0.0.1 uses native macOS App Sandbox + Hardened Runtime. Its only functional sandbox entitlement beyond App Sandbox is USB access for the HID controller:

```xml
com.apple.security.app-sandbox = true
com.apple.security.device.usb = true
```

Runtime HID discovery is narrowed further to the historical vendor allowlist, USB transport, and successful WalkPlay protocol probing.

All runtime application data is stored inside the App Sandbox container. Cached DevicePEQ files and the optional debug log are never intentionally placed in the real user home directory or another external path.

Debug logging is opt-in only via `--debug` or `CB1200AU_DEBUG=true`; otherwise the application's logger emits no diagnostics.

See [`docs/SECURITY.md`](docs/SECURITY.md) for the detailed threat model and verification checklist.
