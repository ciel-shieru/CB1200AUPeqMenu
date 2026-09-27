import Cocoa
import IOKit
import IOKit.hid
import Darwin

// MARK: - WalkPlay / CB1200AU protocol

private let APP_VERSION = "0.0.1"
private let BUILD_FINGERPRINT = "v0.0.1"

private enum WalkPlayProtocol {
    static let reportID: UInt8 = 0x4B
    static let read: UInt8 = 0x80
    static let write: UInt8 = 0x01
    static let end: UInt8 = 0x00

    static let flashEQ: UInt8 = 0x01
    static let globalGain: UInt8 = 0x03
    static let peqValues: UInt8 = 0x09
    static let tempWrite: UInt8 = 0x0A
    static let version: UInt8 = 0x0C
    static let getSlot: UInt8 = 0x0F
    static let filterCount = 8

    // Slot 1 is the built-in flat/default profile and is treated as PEQ OFF.
    // The custom/ON slot is intentionally device-derived and may be 101, 255,
    // or another value depending on the WalkPlay device.
    static let disabledSlotID: UInt8 = 1

    // Official WalkPlay web-app capture of the built-in flat profile on the
    // CB1200AU Hi-MAX. This is the built-in profile, not a user EQ, so it is safe
    // for the app to carry as a static fallback. User/custom EQ data is never
    // hardcoded here.
    static let slot1Profile: [[UInt8]] = [
        [0x01, 0x09, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x0D, 0x82, 0x47, 0x80, 0xC5, 0xAA, 0xB8, 0x3F, 0xF3, 0x7D, 0xB8, 0x7F, 0x3B, 0x55, 0x47, 0xC0, 0x32, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01],
        [0x01, 0x09, 0x18, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x83, 0x41, 0x1E, 0x81, 0xF1, 0x86, 0xE4, 0x3E, 0x7D, 0xBE, 0xE1, 0x7E, 0x0F, 0x79, 0x1B, 0xC1, 0xC8, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01],
        [0x01, 0x09, 0x18, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0xCF, 0xAB, 0xCC, 0x82, 0xAE, 0x7F, 0x44, 0x3D, 0x31, 0x54, 0x33, 0x7D, 0x52, 0x80, 0xBB, 0xC2, 0xF4, 0x01, 0xC0, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01],
        [0x01, 0x09, 0x18, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x70, 0x49, 0x9C, 0x85, 0xD1, 0xF0, 0xA6, 0x3A, 0x90, 0xB6, 0x63, 0x7A, 0x2F, 0x0F, 0x59, 0xC5, 0xE8, 0x03, 0xC0, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01],
        [0x01, 0x09, 0x18, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x48, 0xB7, 0x14, 0x8E, 0xE0, 0x14, 0x76, 0x33, 0xB8, 0x48, 0xEB, 0x71, 0x20, 0xEB, 0x89, 0xCC, 0xC4, 0x09, 0xC0, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01],
        [0x01, 0x09, 0x18, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x77, 0xDA, 0x2E, 0x9C, 0x18, 0x40, 0x69, 0x29, 0x89, 0x25, 0xD1, 0x63, 0xE8, 0xBF, 0x96, 0xD6, 0x88, 0x13, 0xC0, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01],
        [0x01, 0x09, 0x18, 0x00, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0xFE, 0x25, 0xC4, 0xB7, 0x04, 0x78, 0x0C, 0x1B, 0x02, 0xDA, 0x3B, 0x48, 0xFC, 0x87, 0xF3, 0xE4, 0x10, 0x27, 0xC0, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01],
        [0x01, 0x09, 0x18, 0x00, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x7B, 0x7A, 0x3F, 0xD2, 0x59, 0xFB, 0x59, 0x12, 0x85, 0x85, 0xC0, 0x2D, 0xA7, 0x04, 0xA6, 0xED, 0x98, 0x3A, 0xC0, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01],
    ]

    // The App Sandbox USB entitlement is class-wide. Narrow discovery in code
    // to the USB vendor IDs historically accepted by this application, then
    // require a successful WalkPlay protocol probe before presenting a device
    // as a CB1200AU candidate.
    static let vendorIDs: Set<Int> = [
        0x0104, 0x011B, 0x011D, 0x0661, 0x0663, 0x0666, 0x0762,
        0x0909, 0x0D8C, 0x2FC6, 0x3302, 0x34BE, 0x35D8, 0x36A7,
        0x373B, 0x60C1, 0x60E1, 0xB445, 0xB44D
    ]
}

private struct DevicePEQFilter {
    let enabled: Bool
    let type: String
    let frequencyHz: Double
    let gainDB: Double
    let q: Double
}

private struct DevicePEQTextProfile {
    let preampDB: Double
    let filters: [DevicePEQFilter]
    let slotID: UInt8
}

private struct CachedPEQProfile {
    let slotID: UInt8
    let devicePEQ: DevicePEQTextProfile
    let filterWritePackets: [[UInt8]]
    let globalGainByte: UInt8
    let globalGainDB: Double
    let filterReadResponses: [[UInt8]]
    let getSlotResponse: [UInt8]?
}

private struct PEQReadResult {
    let slotID: UInt8
    let enabled: Bool
    let filterResponses: [[UInt8]]
    let globalGainResponse: [UInt8]
    let globalGainByte: UInt8
    let globalGainDB: Double
    let getSlotResponse: [UInt8]?
    let customProfile: CachedPEQProfile?
}

// MARK: - Debug logging

private enum SandboxPaths {
    // In a sandboxed process, this Application Support URL resolves within the
    // app container. There is deliberately no fallback to the real home dir,
    // Downloads, user-selected locations, or a global temp directory.
    static let appSupportRoot: URL = {
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            preconditionFailure("App Sandbox Application Support directory is unavailable")
        }
        return applicationSupport.appendingPathComponent("CB1200AUPeqMenu", isDirectory: true)
    }()

    static let profilesDirectory = appSupportRoot.appendingPathComponent("DevicePEQ Profiles", isDirectory: true)
    static let logsDirectory = appSupportRoot.appendingPathComponent("Logs", isDirectory: true)

    static func ensureDirectories() {
        do {
            try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: appSupportRoot.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: profilesDirectory.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: logsDirectory.path)
        } catch {
            DebugLog.info("failed to create sandbox app-data directories: \(error.localizedDescription)")
        }
    }
}

private enum DebugLog {
    static let enabled: Bool = {
        if CommandLine.arguments.contains("--debug") { return true }
        let environment = ProcessInfo.processInfo.environment["CB1200AU_DEBUG"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return environment == "true"
    }()

    private static let lock = NSLock()
    private static let logURL: URL = {
        SandboxPaths.ensureDirectories()
        return SandboxPaths.logsDirectory.appendingPathComponent("CB1200AUPeqMenu.log", isDirectory: false)
    }()

    static func info(_ message: String) {
        guard enabled else { return }
        let formatter = ISO8601DateFormatter()
        let line = "[\(formatter.string(from: Date()))] CB1200AU PEQ: \(message)\n"

        lock.lock()
        defer { lock.unlock() }

        if let data = line.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            return
        }

        try? line.data(using: .utf8)?.write(to: logURL, options: [.atomic])
    }

    static func printLogLocation() {
        guard enabled else { return }
        let message = "debug log file: \(logURL.path)"
        Swift.print(message)
        info(message)
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func property(_ device: IOHIDDevice, _ key: CFString) -> String {
        guard let value = IOHIDDeviceGetProperty(device, key) else { return "<nil>" }
        return String(describing: value)
    }

    static func intProperty(_ device: IOHIDDevice, _ key: CFString) -> Int? {
        (IOHIDDeviceGetProperty(device, key) as? NSNumber)?.intValue
    }

    static func describe(_ device: IOHIDDevice) -> String {
        let vid = intProperty(device, kIOHIDVendorIDKey as CFString)
        let pid = intProperty(device, kIOHIDProductIDKey as CFString)
        let usagePage = intProperty(device, kIOHIDPrimaryUsagePageKey as CFString)
        let usage = intProperty(device, kIOHIDPrimaryUsageKey as CFString)
        let input = intProperty(device, kIOHIDMaxInputReportSizeKey as CFString)
        let output = intProperty(device, kIOHIDMaxOutputReportSizeKey as CFString)
        let feature = intProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString)
        let location = intProperty(device, kIOHIDLocationIDKey as CFString)

        return "VID=0x\(String(format: "%04X", vid ?? -1)) PID=0x\(String(format: "%04X", pid ?? -1)) " +
            "manufacturer=\(property(device, kIOHIDManufacturerKey as CFString)) " +
            "product=\(property(device, kIOHIDProductKey as CFString)) " +
            "serial=\(property(device, kIOHIDSerialNumberKey as CFString)) " +
            "transport=\(property(device, kIOHIDTransportKey as CFString)) " +
            "usagePage=0x\(String(format: "%04X", usagePage ?? 0)) " +
            "usage=0x\(String(format: "%04X", usage ?? 0)) " +
            "location=0x\(String(format: "%08X", location ?? 0)) " +
            "maxInput=\(input ?? -1) maxOutput=\(output ?? -1) maxFeature=\(feature ?? -1)"
    }
}

// MARK: - DevicePEQ text profile codec / persistence

private enum DevicePEQProfileCodec {
    private static let minFrequency = 20.0
    private static let maxFrequency = 20000.0
    private static let minQ = 0.1
    private static let maxQ = 10.0

    private static let preampRegex = try! NSRegularExpression(
        pattern: #"^\s*Preamp\s*:\s*([+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))\s*dB\s*$"#,
        options: [.caseInsensitive]
    )
    private static let filterRegex = try! NSRegularExpression(
        pattern: #"^\s*Filter\s+(\d+)\s*:\s*(ON|OFF)(?:\s+([A-Za-z]+)\s+Fc\s+([0-9]+(?:\.[0-9]*)?|\.[0-9]+)\s+Hz\s+Gain\s+([+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))\s+dB\s+Q\s+([0-9]+(?:\.[0-9]*)?|\.[0-9]+))?\s*$"#,
        options: [.caseInsensitive]
    )
    private static let slotRegex = try! NSRegularExpression(
        pattern: #"^\s*Slot\s*:\s*(\d+)\s*$"#,
        options: [.caseInsensitive]
    )

    static func serialize(_ profile: DevicePEQTextProfile) -> String {
        var lines: [String] = []
        lines.append(String(format: "Preamp: %.1f dB", locale: Locale(identifier: "en_US_POSIX"), profile.preampDB))
        for (index, filter) in profile.filters.enumerated() {
            let number = index + 1
            if !filter.enabled {
                lines.append("Filter \(number): OFF")
            } else {
                let displayQ = Self.roundToHundredth(filter.q)
                lines.append(String(format: "Filter %d: ON %@ Fc %.0f Hz Gain %.1f dB Q %.3f", locale: Locale(identifier: "en_US_POSIX"), number, filter.type, filter.frequencyHz, filter.gainDB, displayQ))
            }
        }
        lines.append("Slot: \(profile.slotID)")
        return lines.joined(separator: "\n") + "\n"
    }

    static func parse(_ text: String) throws -> DevicePEQTextProfile {
        var preamp: Double?
        var slot: UInt8?
        var parsedFilters: [Int: DevicePEQFilter] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if let m = firstMatch(preampRegex, line), let value = Double(m[1]) {
                preamp = value
                continue
            }
            if let m = firstMatch(slotRegex, line), let value = Int(m[1]), (0...255).contains(value) {
                slot = UInt8(value)
                continue
            }
            if let m = firstMatch(filterRegex, line), let index = Int(m[1]), (1...WalkPlayProtocol.filterCount).contains(index) {
                let enabled = m[2].uppercased() == "ON"
                if !enabled {
                    parsedFilters[index - 1] = DevicePEQFilter(enabled: false, type: "PK", frequencyHz: 0, gainDB: 0, q: 0)
                    continue
                }
                guard let frequency = Double(m[4]), let gain = Double(m[5]), let q = Double(m[6]) else {
                    throw HIDError.protocolError("Invalid DevicePEQ filter \(index) numeric values")
                }
                let type = m[3].uppercased()
                guard Self.supportedFilterTypes.contains(type) else {
                    throw HIDError.protocolError("Unsupported DevicePEQ filter type \(type) in filter \(index)")
                }
                parsedFilters[index - 1] = DevicePEQFilter(enabled: true, type: type, frequencyHz: frequency, gainDB: gain, q: q)
                continue
            }
            throw HIDError.protocolError("Unrecognized DevicePEQ profile line: \(line)")
        }

        guard let preamp else { throw HIDError.protocolError("DevicePEQ profile is missing a Preamp line") }
        guard let slot, slot != 0, slot != WalkPlayProtocol.disabledSlotID else {
            throw HIDError.protocolError("DevicePEQ custom profile must contain a custom Slot: <2-255>, not Slot: 0 or Slot: 1")
        }

        var filters = Array(repeating: DevicePEQFilter(enabled: false, type: "PK", frequencyHz: 0, gainDB: 0, q: 0), count: WalkPlayProtocol.filterCount)
        for i in 0..<WalkPlayProtocol.filterCount {
            if let filter = parsedFilters[i] { filters[i] = filter }
        }
        return DevicePEQTextProfile(preampDB: preamp, filters: filters, slotID: slot)
    }

    static func profile(fromReadResponses responses: [[UInt8]], globalGainDB: Double, slotID: UInt8) throws -> CachedPEQProfile {
        guard responses.count == WalkPlayProtocol.filterCount else {
            throw HIDError.protocolError("Expected \(WalkPlayProtocol.filterCount) PEQ filter responses, got \(responses.count)")
        }
        var filters: [DevicePEQFilter] = []
        filters.reserveCapacity(responses.count)
        for response in responses {
            filters.append(try parseFilterResponse(response))
        }
        let textProfile = DevicePEQTextProfile(preampDB: globalGainDB, filters: filters, slotID: slotID)
        let packets = try writePacketsPreservingReadback(responses, slotID: slotID)
        return CachedPEQProfile(
            slotID: slotID,
            devicePEQ: textProfile,
            filterWritePackets: packets,
            globalGainByte: UInt8(bitPattern: Int8(clamping: Int(globalGainDB.rounded()))),
            globalGainDB: globalGainDB,
            filterReadResponses: responses,
            getSlotResponse: nil
        )
    }

    static func cachedProfile(from textProfile: DevicePEQTextProfile) throws -> CachedPEQProfile {
        let packets = try writePackets(from: textProfile)
        let gain = max(-128, min(127, Int(textProfile.preampDB.rounded())))
        let gainByte = UInt8(bitPattern: Int8(gain))
        return CachedPEQProfile(
            slotID: textProfile.slotID,
            devicePEQ: textProfile,
            filterWritePackets: packets,
            globalGainByte: gainByte,
            globalGainDB: textProfile.preampDB,
            filterReadResponses: [],
            getSlotResponse: nil
        )
    }

    private static func writePacketsPreservingReadback(_ responses: [[UInt8]], slotID: UInt8) throws -> [[UInt8]] {
        guard responses.count == WalkPlayProtocol.filterCount else {
            throw HIDError.protocolError("Expected 8 PEQ readback records, got \(responses.count)")
        }
        guard slotID != 0, slotID != WalkPlayProtocol.disabledSlotID else {
            throw HIDError.protocolError("Cannot cache slot 0 or built-in flat slot 1 as a custom profile")
        }

        return try responses.enumerated().map { index, response in
            guard response.count == 36 else {
                throw HIDError.protocolError("PEQ filter-\(index + 1) readback length=\(response.count), expected 36")
            }
            guard response[1] == WalkPlayProtocol.peqValues else {
                throw HIDError.protocolError("PEQ filter-\(index + 1) readback has unexpected command 0x\(String(response[1], radix: 16))")
            }

            var packet = response
            packet[0] = WalkPlayProtocol.write
            packet[2] = 0x18
            packet[4] = UInt8(index)
            packet[35] = slotID
            guard packet.count == 36 else {
                throw HIDError.protocolError("PEQ filter-\(index + 1) converted write length=\(packet.count), expected 36")
            }
            return packet
        }
    }

    static func writePackets(from profile: DevicePEQTextProfile) throws -> [[UInt8]] {
        guard profile.filters.count == WalkPlayProtocol.filterCount else {
            throw HIDError.protocolError("DevicePEQ profile must contain exactly 8 filters")
        }
        guard profile.slotID != 0, profile.slotID != WalkPlayProtocol.disabledSlotID else {
            throw HIDError.protocolError("Refusing to write custom profile with Slot: 0 or Slot: 1")
        }
        guard profile.preampDB >= -128 && profile.preampDB <= 127 else {
            throw HIDError.protocolError("DevicePEQ preamp/global gain is outside the signed 8-bit WalkPlay range")
        }

        return try profile.filters.enumerated().map { index, filter in
            var packet: [UInt8] = [WalkPlayProtocol.write, WalkPlayProtocol.peqValues, 0x18, 0x00, UInt8(index), 0x00, 0x00]
            let typeByte = filterTypeByte(filter.type)

            if !filter.enabled {
                packet.append(contentsOf: Array(repeating: 0, count: 20))
                packet.append(contentsOf: littleEndian(UInt16(0)))
                packet.append(contentsOf: littleEndian(UInt16(0)))
                packet.append(contentsOf: littleEndian(UInt16(bitPattern: 0)))
                packet.append(typeByte)
                packet.append(0x00)
                packet.append(profile.slotID)
                guard packet.count == 36 else {
                    throw HIDError.protocolError("DevicePEQ disabled filter-\(index + 1) generated write length=\(packet.count), expected 36")
                }
                return packet
            }

            try validate(filter, index: index)
            let storedFrequency = min(max(Int(filter.frequencyHz.rounded()), Int(minFrequency)), Int(maxFrequency))
            // Reconstruct the exact 8.8 Q value from the textual value before
            // generating coefficients. For example, DevicePEQ's Q=0.920 maps
            // back to raw 0x00EC (236/256), preserving the original HID data.
            let canonicalQ = Self.roundToHundredth(filter.q)
            let qRaw = UInt16(clamping: Int((canonicalQ * 256.0).rounded()))
            let storedQ = Double(qRaw) / 256.0
            let gainRaw = Int16(clamping: Int((filter.gainDB * 256.0).rounded()))

            let bArr = computeIIRFilter(frequencyHz: Double(storedFrequency), gainDB: filter.gainDB, q: storedQ, type: filter.type)
            packet.append(contentsOf: bArr)
            packet.append(contentsOf: littleEndian(UInt16(storedFrequency)))
            packet.append(contentsOf: littleEndian(qRaw))
            packet.append(contentsOf: littleEndian(UInt16(bitPattern: gainRaw)))
            packet.append(typeByte)
            packet.append(0x00)
            packet.append(profile.slotID)
            guard packet.count == 36 else {
                throw HIDError.protocolError("DevicePEQ filter-\(index + 1) generated write length=\(packet.count), expected 36")
            }
            return packet
        }
    }

    private static let supportedFilterTypes: Set<String> = ["PK", "LSQ", "HSQ", "LP", "HP"]

    private static func parseFilterResponse(_ response: [UInt8]) throws -> DevicePEQFilter {
        guard response.count >= 36 else { throw HIDError.protocolError("PEQ filter response too short: \(response.count) bytes") }
        let freqRaw = UInt16(response[27]) | (UInt16(response[28]) << 8)
        let qRaw = UInt16(response[29]) | (UInt16(response[30]) << 8)
        let gainSigned = Int16(bitPattern: UInt16(response[31]) | (UInt16(response[32]) << 8))
        let type = filterTypeString(response[33])

        let metadataCorrupted = freqRaw == 0xFFFF && qRaw == 0xFFFF && gainSigned == -1
        if metadataCorrupted || freqRaw == 0 || qRaw == 0 {
            return DevicePEQFilter(enabled: false, type: type, frequencyHz: 0, gainDB: 0, q: 0)
        }

        // DevicePEQ's textual representation for this CB1200AU profile is the
        // raw WalkPlay metadata value: frequency is the little-endian integer,
        // while Q is the unsigned 8.8 value rounded to two decimal places for
        // display. Do not apply the old 0.9775/cos-Nyquist compensation here;
        // that produced a cache file which differed from DevicePEQ even though
        // the underlying HID bytes were correct.
        let frequency = Double(freqRaw)
        let gain = Double(gainSigned) / 256.0
        let q = Self.roundToHundredth(Double(qRaw) / 256.0)
        return DevicePEQFilter(enabled: true, type: type, frequencyHz: frequency, gainDB: gain, q: q)
    }

    private static func roundToHundredth(_ value: Double) -> Double {
        (value * 100.0).rounded() / 100.0
    }

    private static func validate(_ filter: DevicePEQFilter, index: Int) throws {
        guard supportedFilterTypes.contains(filter.type) else { throw HIDError.protocolError("Filter \(index + 1) type \(filter.type) is not supported by WalkPlay DevicePEQ") }
        guard filter.frequencyHz >= minFrequency && filter.frequencyHz <= maxFrequency else { throw HIDError.protocolError("Filter \(index + 1) frequency must be 20-20000 Hz") }
        guard filter.gainDB >= -10 && filter.gainDB <= 10 else { throw HIDError.protocolError("Filter \(index + 1) gain must be -10 to +10 dB for SchemeNo11") }
        guard filter.q >= minQ && filter.q <= maxQ else { throw HIDError.protocolError("Filter \(index + 1) Q must be 0.1-10") }
    }

    private static func filterTypeByte(_ type: String) -> UInt8 {
        switch type {
        case "LSQ": return 1
        case "PK": return 2
        case "HSQ": return 3
        case "LP": return 4
        case "HP": return 5
        default: return 2
        }
    }

    private static func filterTypeString(_ byte: UInt8) -> String {
        switch byte {
        case 1: return "LSQ"
        case 2: return "PK"
        case 3: return "HSQ"
        case 4: return "LP"
        case 5: return "HP"
        default: return "PK"
        }
    }

    private static func computeIIRFilter(frequencyHz: Double, gainDB: Double, q: Double, type: String) -> [UInt8] {
        let A = pow(10.0, gainDB / 40.0)
        let w0 = frequencyHz * 2.0 * Double.pi / 96000.0
        let sinw0 = sin(w0)
        let cosw0 = cos(w0)
        let alpha = sinw0 / (2.0 * q)
        var a0: Double
        var a1: Double
        var a2: Double
        var b0: Double
        var b1: Double
        var b2: Double

        if type == "LSQ" || type == "HSQ" {
            let shelfAlpha = (sinw0 / 2.0) * sqrt((A + 1.0 / A) * (1.0 / q - 1.0) + 2.0)
            let sqrtA2Alpha = 2.0 * sqrt(A) * shelfAlpha
            if type == "LSQ" {
                b0 = A * ((A + 1) - (A - 1) * cosw0 + sqrtA2Alpha)
                b1 = 2 * A * ((A - 1) - (A + 1) * cosw0)
                b2 = A * ((A + 1) - (A - 1) * cosw0 - sqrtA2Alpha)
                a0 = (A + 1) + (A - 1) * cosw0 + sqrtA2Alpha
                a1 = -2 * ((A - 1) + (A + 1) * cosw0)
                a2 = (A + 1) + (A - 1) * cosw0 - sqrtA2Alpha
            } else {
                b0 = A * ((A + 1) + (A - 1) * cosw0 + sqrtA2Alpha)
                b1 = -2 * A * ((A - 1) + (A + 1) * cosw0)
                b2 = A * ((A + 1) + (A - 1) * cosw0 - sqrtA2Alpha)
                a0 = (A + 1) - (A - 1) * cosw0 + sqrtA2Alpha
                a1 = 2 * ((A - 1) - (A + 1) * cosw0)
                a2 = (A + 1) - (A - 1) * cosw0 - sqrtA2Alpha
            }
        } else {
            b0 = 1 + alpha * A
            b1 = -2 * cosw0
            b2 = 1 - alpha * A
            a0 = 1 + alpha / A
            a1 = -2 * cosw0
            a2 = 1 - alpha / A
        }

        let values = [1.0, a1 / a0, a2 / a0]
        let values2 = [b0 / a0, b1 / a0, b2 / a0]
        let quantized: [Int32] = values2.map { Int32(clamping: Int64(($0 * 1073741824.0).rounded())) } + [Int32(clamping: Int64((-values[1] * 1073741824.0).rounded())), Int32(clamping: Int64((-values[2] * 1073741824.0).rounded()))]
        var bytes: [UInt8] = []
        bytes.reserveCapacity(20)
        for value in quantized {
            let raw = UInt32(bitPattern: value)
            bytes.append(UInt8(truncatingIfNeeded: raw))
            bytes.append(UInt8(truncatingIfNeeded: raw >> 8))
            bytes.append(UInt8(truncatingIfNeeded: raw >> 16))
            bytes.append(UInt8(truncatingIfNeeded: raw >> 24))
        }
        return bytes
    }

    private static func littleEndian(_ value: UInt16) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
    }

    private static func firstMatch(_ regex: NSRegularExpression, _ line: String) -> [String]? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { i in
            let r = match.range(at: i)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: line) else { return "" }
            return String(line[swiftRange])
        }
    }
}

private enum DevicePEQProfileStore {
    static let profilesDirectoryName = "DevicePEQ Profiles"

    static func expectedDirectoryURL() -> URL {
        SandboxPaths.profilesDirectory
    }

    static func expectedProfileURL(for device: WalkPlayHIDDevice) -> URL {
        let name = sanitize(device.productName)
        let serial = sanitize(device.serialNumber.isEmpty ? "NOSERIAL" : device.serialNumber)
        let filename = "\(name)_VID-\(String(format: "%04X", device.vendorID))_PID-\(String(format: "%04X", device.productID))_SERIAL-\(serial).txt"
        return expectedDirectoryURL().appendingPathComponent(filename, isDirectory: false)
    }

    static func load(for device: WalkPlayHIDDevice) throws -> (DevicePEQTextProfile, URL)? {
        let url = expectedProfileURL(for: device)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let text = try String(contentsOf: url, encoding: .utf8)
        return (try DevicePEQProfileCodec.parse(text), url)
    }

    static func save(_ profile: DevicePEQTextProfile, for device: WalkPlayHIDDevice) throws -> URL {
        let directory = expectedDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let url = expectedProfileURL(for: device)
        let text = DevicePEQProfileCodec.serialize(profile)
        let data = Data(text.utf8)
        let temporary = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return result.isEmpty ? "UNKNOWN" : String(result.prefix(120))
    }
}

// MARK: - Cached DevicePEQ profile file watcher

private final class DevicePEQProfileWatcher {
    private let queue = DispatchQueue(label: "local.cb1200au.peqmenu.profile-watch", qos: .utility)
    private var directoryFD: Int32 = -1
    private var directorySource: DispatchSourceFileSystemObject?
    private var profileFD: Int32 = -1
    private var profileSource: DispatchSourceFileSystemObject?
    private var watchedURL: URL?
    private var pendingNotification: DispatchWorkItem?

    var onChange: ((URL) -> Void)?

    func start(directory: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.openDirectoryWatcher(directory: directory)
        }
    }

    func watchProfile(_ url: URL?) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.watchedURL != url else {
                if let url, FileManager.default.fileExists(atPath: url.path), self.profileSource == nil {
                    self.openProfileWatcher(url: url)
                }
                return
            }
            self.closeProfileWatcher()
            self.watchedURL = url
            if let url {
                self.openProfileWatcher(url: url)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingNotification?.cancel()
            self.pendingNotification = nil
            self.closeProfileWatcher()
            self.closeDirectoryWatcher()
            self.watchedURL = nil
        }
    }

    private func openDirectoryWatcher(directory: URL) {
        closeDirectoryWatcher()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            DebugLog.info("profile directory watcher could not open: \(directory.path), errno=\(errno)")
            return
        }
        directoryFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .link],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self, let url = self.watchedURL else { return }
            DebugLog.info("cached-profile directory changed; scheduling reload check for \(url.path)")
            self.scheduleNotification(for: url)
            if self.profileSource == nil, FileManager.default.fileExists(atPath: url.path) {
                self.openProfileWatcher(url: url)
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        directorySource = source
        source.resume()
        DebugLog.info("watching cached DevicePEQ profile directory: \(directory.path)")
    }

    private func openProfileWatcher(url: URL) {
        closeProfileWatcher()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            DebugLog.info("cached DevicePEQ profile watcher could not open: \(url.path); file may not exist yet")
            return
        }
        profileFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self, let url = self.watchedURL else { return }
            let flags = self.profileSource?.data ?? []
            DebugLog.info("cached DevicePEQ profile changed: \(url.path) events=\(flags)")
            self.scheduleNotification(for: url)
            if flags.contains(.rename) || flags.contains(.delete) {
                self.closeProfileWatcher()
                self.queue.asyncAfter(deadline: .now() + 0.20) { [weak self] in
                    guard let self, let url = self.watchedURL else { return }
                    if FileManager.default.fileExists(atPath: url.path) {
                        self.openProfileWatcher(url: url)
                    }
                }
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        profileSource = source
        source.resume()
        DebugLog.info("watching cached DevicePEQ profile file: \(url.path)")
    }

    private func scheduleNotification(for url: URL) {
        pendingNotification?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(url)
            }
        }
        pendingNotification = work
        queue.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func closeDirectoryWatcher() {
        directorySource?.cancel()
        directorySource = nil
        directoryFD = -1
    }

    private func closeProfileWatcher() {
        profileSource?.cancel()
        profileSource = nil
        profileFD = -1
    }
}

// MARK: - HID device wrapper

private final class WalkPlayHIDDevice {
    let device: IOHIDDevice
    let vendorID: Int
    let productID: Int
    let productName: String
    let serialNumber: String
    let locationID: Int
    let usagePage: Int

    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var inputBufferLength = 0
    private var callbackInstalled = false
    private var deviceScheduledOnMainRunLoop = false

    private let lock = NSLock()
    private var pendingResponse: (([UInt8]) -> Void)?

    init(device: IOHIDDevice) {
        self.device = device
        vendorID = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0
        productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
        productName = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "WalkPlay HID"
        serialNumber = (IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String) ?? ""
        locationID = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber)?.intValue ?? 0
        usagePage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
        DebugLog.info("created HID wrapper: " + DebugLog.describe(device))
    }

    func open() throws {
        DebugLog.info("opening HID candidate: " + DebugLog.describe(device))
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            DebugLog.info(String(format: "IOHIDDeviceOpen failed for VID=0x%04X PID=0x%04X: 0x%08X", vendorID, productID, openResult))
            throw HIDError.ioKit(openResult, "IOHIDDeviceOpen failed")
        }
        DebugLog.info(String(format: "opened HID candidate VID=0x%04X PID=0x%04X", vendorID, productID))

        let maxInput = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 64
        let inputSize = max(1, min(maxInput, 4097))
        let allocatedInputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: inputSize)
        allocatedInputBuffer.initialize(repeating: 0, count: inputSize)
        inputBuffer = allocatedInputBuffer
        inputBufferLength = inputSize

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            allocatedInputBuffer,
            inputSize,
            { context, _, _, reportType, reportID, report, reportLength in
                guard reportType == kIOHIDReportTypeInput, let context, reportLength > 0 else { return }
                let owner = Unmanaged<WalkPlayHIDDevice>.fromOpaque(context).takeUnretainedValue()
                owner.handleInputReport(reportID: reportID, report: report, reportLength: reportLength)
            },
            context
        )
        callbackInstalled = true
        DebugLog.info(String(format: "input callback installed for VID=0x%04X PID=0x%04X inputBuffer=%d stableAllocatedBuffer=true", vendorID, productID, inputBufferLength))

        DispatchQueue.main.sync {
            let mode = CFRunLoopMode.defaultMode!.rawValue
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), mode)
            deviceScheduledOnMainRunLoop = true
            DebugLog.info(String(format: "scheduled HID device on main run loop VID=0x%04X PID=0x%04X", vendorID, productID))
        }
    }

    func close() {
        DebugLog.info(String(format: "closing HID device VID=0x%04X PID=0x%04X", vendorID, productID))
        lock.lock()
        pendingResponse = nil
        lock.unlock()

        if callbackInstalled {
            if let inputBuffer {
                IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, inputBufferLength, nil, nil)
                inputBuffer.deinitialize(count: inputBufferLength)
                inputBuffer.deallocate()
            }
            inputBuffer = nil
            inputBufferLength = 0
            callbackInstalled = false
        }
        if deviceScheduledOnMainRunLoop {
            let unschedule = { [weak self] in
                guard let self else { return }
                let mode = CFRunLoopMode.defaultMode!.rawValue
                IOHIDDeviceUnscheduleFromRunLoop(self.device, CFRunLoopGetMain(), mode)
                self.deviceScheduledOnMainRunLoop = false
            }
            if Thread.isMainThread {
                unschedule()
            } else {
                DispatchQueue.main.sync(execute: unschedule)
            }
        }
        _ = IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func send(_ payload: [UInt8]) throws {
        // The authoritative WalkPlay WebHID capture uses the logical report size,
        // not the HID descriptor's 64-byte maximum. For example, the flat-profile
        // PEQ write is 37 bytes total: report ID 0x4B + a 36-byte WalkPlay payload.
        // Preserve that exact framing for native IOKit HID as well.
        let logicalLength = payload.count + 1
        let advertisedOutputSize = (IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? NSNumber)?.intValue ?? logicalLength

        var report = [UInt8](repeating: 0, count: logicalLength)
        report[0] = WalkPlayProtocol.reportID
        report.replaceSubrange(1..<logicalLength, with: payload)

        DebugLog.info(String(format: "TX reportID=0x%02X VID=0x%04X PID=0x%04X payload=[%@] logicalLength=%d iokitBuffer=[%@] bufferLength=%d maxOutput=%d padded=no", WalkPlayProtocol.reportID, vendorID, productID, DebugLog.hex(payload), logicalLength, DebugLog.hex(report), report.count, advertisedOutputSize))
        let result = report.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(WalkPlayProtocol.reportID), buffer.baseAddress!, report.count)
        }
        guard result == kIOReturnSuccess else {
            DebugLog.info(String(format: "IOHIDDeviceSetReport failed VID=0x%04X PID=0x%04X: 0x%08X", vendorID, productID, result))
            throw HIDError.ioKit(result, "IOHIDDeviceSetReport failed")
        }
    }

    func probeProtocol(timeout: TimeInterval = 1.0) throws {
        let versionResponse = try waitForResponse(expectedCommand: WalkPlayProtocol.version, timeout: timeout) {
            try self.send([WalkPlayProtocol.read, WalkPlayProtocol.version])
        }
        DebugLog.info(String(format: "RX WalkPlay version VID=0x%04X PID=0x%04X payload=[%@]", vendorID, productID, DebugLog.hex(versionResponse)))
        if versionResponse.count >= 6 {
            let versionBytes = Array(versionResponse[3..<6])
            let printable = String(bytes: versionBytes, encoding: .ascii) ?? "<non-ASCII>"
            DebugLog.info("decoded WalkPlay firmware version=\(printable)")
        }
    }

    func readPEQProfile(timeout: TimeInterval = 1.5) throws -> PEQReadResult {
        var filterResponses = Array(repeating: [UInt8](), count: WalkPlayProtocol.filterCount)
        var derivedSlotIDs: [UInt8] = []

        DebugLog.info("pulling all 8 PEQ filters to populate current profile and cache custom data")
        for filterIndex in 0..<WalkPlayProtocol.filterCount {
            DebugLog.info(String(format: "pulling PEQ filter %d/8", filterIndex + 1))
            let response = try waitForResponse(expectedCommand: WalkPlayProtocol.peqValues, timeout: timeout) {
                try self.send([WalkPlayProtocol.read, WalkPlayProtocol.peqValues, WalkPlayProtocol.end, 0x00, UInt8(filterIndex), 0x00])
            }
            let normalized = try Self.normalizePEQFilterResponse(response, filterIndex: filterIndex)
            filterResponses[filterIndex] = normalized.bytes
            derivedSlotIDs.append(normalized.slotID)
            DebugLog.info(String(format: "RX PEQ_VALUES/filter-%d metadata=0x%02X slot-byte=0x%02X", filterIndex, normalized.metadata, normalized.slotID))
            Thread.sleep(forTimeInterval: 0.025)
        }

        let derivedSlot = Self.consistentSlotID(from: derivedSlotIDs)
        DebugLog.info(String(format: "current EQ slot from filter records=%@", derivedSlot.map { String(format: "0x%02X", $0) } ?? "inconsistent"))

        // The official WalkPlay/DevicePEQ protocol exposes 0x0F as an active-slot
        // command, but this firmware does not provide a usable response to the
        // speculative 80 0F 00 query. Do not block startup/verification waiting
        // for a response that the device does not emit. The complete PEQ data and
        // global gain are sufficient to recognize the built-in flat profile.
        let getSlotResponse: [UInt8]? = nil

        let globalGainResponse = try readGlobalGain(timeout: timeout)
        guard globalGainResponse.count > 4 else { throw HIDError.protocolError("Global-gain response too short: \(globalGainResponse.count) bytes") }
        let globalGainByte = globalGainResponse[4]
        let globalGainDB = Double(Int8(bitPattern: globalGainByte))
        DebugLog.info(String(format: "decoded global/DAC gain=%.1f dB (byte=0x%02X)", globalGainDB, globalGainByte))

        var slot: UInt8? = derivedSlot

        // After writing the official built-in flat profile, this firmware can keep
        // returning metadata/slot = 0x00 even though the complete eight-band data
        // and global gain are now exactly the slot-1 profile. Recognize the profile
        // contents first, so post-write verification does not confuse stale slot
        // metadata with an uninitialized device. A bare slot 0 with any other
        // profile remains an error, preserving the fresh-insertion safety rule.
        if let derivedSlot, derivedSlot == 0, Self.matchesBuiltInFlatProfile(filterResponses: filterResponses, globalGainByte: globalGainByte) {
            slot = WalkPlayProtocol.disabledSlotID
            DebugLog.info("filter data + 0 dB gain exactly match built-in flat slot 1 despite stale slot metadata 0x00; treating current profile as slot 1")
        }

        guard let resolvedSlot = slot else {
            throw HIDError.protocolError("Unable to determine a consistent current EQ slot from the 8 PEQ filter records")
        }
        if resolvedSlot == 0 {
            throw HIDError.protocolError("Current EQ slot is 0x00 and the active filter data does not match the known built-in flat profile; device PEQ metadata has not been populated yet")
        }

        let enabled = resolvedSlot != WalkPlayProtocol.disabledSlotID
        var customProfile: CachedPEQProfile?
        if enabled {
            customProfile = try DevicePEQProfileCodec.profile(fromReadResponses: filterResponses, globalGainDB: globalGainDB, slotID: resolvedSlot)
            customProfile = CachedPEQProfile(
                slotID: customProfile!.slotID,
                devicePEQ: customProfile!.devicePEQ,
                filterWritePackets: customProfile!.filterWritePackets,
                globalGainByte: customProfile!.globalGainByte,
                globalGainDB: customProfile!.globalGainDB,
                filterReadResponses: customProfile!.filterReadResponses,
                getSlotResponse: getSlotResponse
            )
            DebugLog.info(String(format: "cached complete custom PEQ profile in RAM: slot=%d (0x%02X), filters=%d, globalGain=%.1f dB", resolvedSlot, resolvedSlot, customProfile!.filterWritePackets.count, globalGainDB))
        } else {
            DebugLog.info("current profile is built-in flat slot 1; custom DevicePEQ profile will be loaded from disk by AppDelegate")
        }

        return PEQReadResult(
            slotID: resolvedSlot,
            enabled: enabled,
            filterResponses: filterResponses,
            globalGainResponse: globalGainResponse,
            globalGainByte: globalGainByte,
            globalGainDB: globalGainDB,
            getSlotResponse: getSlotResponse,
            customProfile: customProfile
        )
    }

    func setPEQ(enabled: Bool, customProfile: CachedPEQProfile?) throws {
        let filterPackets: [[UInt8]]
        let dacGain: UInt8
        let targetSlot: UInt8

        if enabled {
            guard let customProfile else {
                throw HIDError.protocolError("No cached custom DevicePEQ profile is available for enabling PEQ")
            }
            targetSlot = customProfile.slotID
            filterPackets = customProfile.filterWritePackets
            dacGain = customProfile.globalGainByte
            DebugLog.info(String(format: "applying cached DevicePEQ custom profile: slot=%d (0x%02X), filters=%d, DAC/global gain=%.1f dB (0x%02X)", targetSlot, targetSlot, filterPackets.count, customProfile.globalGainDB, dacGain))
        } else {
            targetSlot = WalkPlayProtocol.disabledSlotID
            filterPackets = WalkPlayProtocol.slot1Profile
            dacGain = 0x00
            DebugLog.info("applying built-in flat slot-1 profile: filters=8, DAC/global gain=0 dB")
        }

        guard filterPackets.count == WalkPlayProtocol.filterCount else {
            throw HIDError.protocolError("PEQ profile must contain exactly 8 filter writes; got \(filterPackets.count)")
        }
        for (index, packet) in filterPackets.enumerated() {
            guard packet.count == 36 else { throw HIDError.protocolError("PEQ filter-\(index + 1) write record has unexpected length \(packet.count)") }
            DebugLog.info(String(format: "writing PEQ filter %d/8 for slot %d", index + 1, targetSlot))
            try send(packet)
            Thread.sleep(forTimeInterval: 0.025)
        }
        Thread.sleep(forTimeInterval: 0.100)

        if !enabled {
            // IMPORTANT: do not send speculative control commands here. The
            // authoritative user-provided WalkPlay WebHID capture for the
            // built-in flat profile contains only the eight 0x09 writes, the
            // 0x0A register-cache flush, the 0x03 DAC/gain write, and the
            // 0x01 Flash commit. In particular, 0x17 is documented by the
            // independent WalkPlay protocol documentation as factory reset,
            // so it must never be sent as part of a PEQ toggle.
            DebugLog.info("using exact captured built-in flat-profile commit sequence; no extra profile-control commands")
        }

        DebugLog.info("flushing PEQ data to DSP/register cache")
        try send([WalkPlayProtocol.write, WalkPlayProtocol.tempWrite, 0x04, 0x00, 0x00, 0xFF, 0xFF])
        Thread.sleep(forTimeInterval: 0.050)

        DebugLog.info(String(format: "setting profile DAC/global gain byte=0x%02X", dacGain))
        try send([WalkPlayProtocol.write, WalkPlayProtocol.globalGain, 0x02, 0x00, dacGain])
        Thread.sleep(forTimeInterval: 0.050)

        // The official WalkPlay implementation schedules the Flash commit
        // 1 second after the register/DSP write sequence. Committing earlier
        // can leave a newly-written profile in a corrupted DSP state even when
        // the immediate PEQ readback appears correct.
        DebugLog.info("waiting 1.0s after profile register/gain writes before Flash commit (matches official WalkPlay timing)")
        Thread.sleep(forTimeInterval: 1.000)

        DebugLog.info("committing PEQ profile to Flash")
        try send([WalkPlayProtocol.write, WalkPlayProtocol.flashEQ, WalkPlayProtocol.end])
        // Give the device time to finish the Flash commit before readback.
        Thread.sleep(forTimeInterval: 0.200)
    }

    private struct PEQFilterRecord {
        let bytes: [UInt8]
        let metadata: UInt8
        let slotID: UInt8
    }

    private static func matchesBuiltInFlatProfile(filterResponses: [[UInt8]], globalGainByte: UInt8) -> Bool {
        guard filterResponses.count == WalkPlayProtocol.filterCount, globalGainByte == 0x00 else { return false }
        for index in 0..<WalkPlayProtocol.filterCount {
            let response = filterResponses[index]
            let expected = WalkPlayProtocol.slot1Profile[index]
            guard response.count >= 34, expected.count >= 34 else { return false }
            // The read response differs from the write packet in command byte,
            // and byte 6 may be firmware/status data. The actual PEQ coefficients
            // and filter descriptor occupy bytes 7...33 and must match exactly.
            if Array(response[7...33]) != Array(expected[7...33]) {
                return false
            }
        }
        return true
    }

    private static func normalizePEQFilterResponse(_ response: [UInt8], filterIndex: Int) throws -> PEQFilterRecord {
        // The per-filter PEQ response is a fixed 36-byte payload; the corresponding
        // WalkPlay PEQ write record is also 36 bytes, followed by no explicit END byte. The field
        // layout matches DevicePEQ's parser:
        //   [27..28] frequency, [29..30] Q, [31..32] gain, [33] type,
        //   [34] profile metadata/namespace byte, [35] slot ID.
        // There is NO literal 0A 02 trailer. For filter 0, 0x0A happens to
        // be the high byte of the gain field, while filter 1/2/etc. can contain
        // other values there. Searching for 0A 02 therefore breaks valid EQs.
        guard response.count >= 36 else {
            throw HIDError.protocolError(
                "PEQ filter-\(filterIndex + 1) response too short: \(response.count) bytes; expected at least 36"
            )
        }

        var normalized = Array(response.prefix(36))

        // Some firmware/report paths can expose an extra FF 00 pair before the
        // coefficient data. Preserve the canonical 36-byte DevicePEQ record if
        // that exact extra pair is present. This is the debug23 normalization
        // behavior from the earlier working normalization path; an unconditional
        // FF-at-index-6 removal would break the normal response shape on this device.
        if response.count >= 38, response[6] == 0xFF, response[7] == 0x00, response[8] != 0x00 {
            normalized = Array(response[0..<7]) + Array(response[8..<37])
            DebugLog.info(String(format: "normalized PEQ filter-%d response by removing firmware FF 00 pair at payload index 6", filterIndex + 1))
        }

        guard normalized.count == 36 else {
            throw HIDError.protocolError(
                "PEQ filter-\(filterIndex + 1) normalized response length=\(normalized.count), expected 36"
            )
        }
        guard normalized[1] == WalkPlayProtocol.peqValues, normalized[4] == UInt8(filterIndex) else {
            throw HIDError.protocolError(
                String(format: "PEQ filter-%d response header/index mismatch: command=0x%02X index=%d",
                       filterIndex + 1, normalized[1], normalized[4])
            )
        }

        let metadata = normalized[34]
        let slotID = normalized[35]
        return PEQFilterRecord(bytes: normalized, metadata: metadata, slotID: slotID)
    }

    private static func consistentSlotID(from values: [UInt8]) -> UInt8? {
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private func readGlobalGain(timeout: TimeInterval) throws -> [UInt8] {
        let response = try waitForResponse(expectedCommand: WalkPlayProtocol.globalGain, timeout: min(timeout, 1.0)) {
            try self.send([WalkPlayProtocol.read, WalkPlayProtocol.globalGain, WalkPlayProtocol.end])
        }
        DebugLog.info(String(format: "RX GLOBAL_GAIN (0x03) payload=[%@]", DebugLog.hex(response)))
        return response
    }

    private func waitForResponse(expectedCommand: UInt8, timeout: TimeInterval, sendRequest: () throws -> Void) throws -> [UInt8] {
        let semaphore = DispatchSemaphore(value: 0)
        var response: [UInt8]?
        var sendError: Error?

        lock.lock()
        pendingResponse = { [weak self] data in
            guard let self else { return }
            guard data.count >= 2 else { return }
            guard data[0] == WalkPlayProtocol.read, data[1] == expectedCommand else {
                DebugLog.info(String(format: "RX response candidate did not match command 0x%02X: payload=[%@]", expectedCommand, DebugLog.hex(data)))
                return
            }
            DebugLog.info(String(format: "RX response MATCHED command 0x%02X: payload=[%@]", expectedCommand, DebugLog.hex(data)))
            self.lock.lock()
            response = data
            self.pendingResponse = nil
            self.lock.unlock()
            semaphore.signal()
        }
        lock.unlock()

        do {
            try sendRequest()
        } catch {
            lock.lock(); pendingResponse = nil; lock.unlock()
            sendError = error
        }
        if let sendError { throw sendError }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            lock.lock(); pendingResponse = nil; lock.unlock()
            throw HIDError.timeout("Timed out waiting for WalkPlay response to command 0x\(String(expectedCommand, radix: 16))")
        }
        guard let response else { throw HIDError.protocolError("WalkPlay returned no usable response") }
        return response
    }

    private func handleInputReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, reportLength: CFIndex) {
        guard reportID == UInt32(WalkPlayProtocol.reportID), reportLength > 0 else { return }
        let raw = Array(UnsafeBufferPointer(start: report, count: reportLength))
        guard raw.first == WalkPlayProtocol.reportID else { return }
        let payload = Array(raw.dropFirst())
        DebugLog.info(String(format: "RX reportID=0x%02X VID=0x%04X PID=0x%04X rawLength=%d raw=[%@] payloadLength=%d payload=[%@]", reportID, vendorID, productID, raw.count, DebugLog.hex(raw), payload.count, DebugLog.hex(payload)))
        lock.lock()
        let callback = pendingResponse
        lock.unlock()
        callback?(payload)
    }
}

private enum HIDError: LocalizedError {
    case ioKit(kern_return_t, String)
    case timeout(String)
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case let .ioKit(code, message):
            return "\(message) (0x\(String(code, radix: 16)))"
        case let .timeout(message), let .protocolError(message):
            return message
        }
    }
}

// MARK: - Device manager

private final class WalkPlayDeviceManager {
    struct CandidateInfo: Hashable {
        let vendorID: Int
        let productID: Int
        let productName: String
        let serialNumber: String
        let locationID: Int
        let usagePage: Int

        var key: String {
            "\(vendorID)-\(productID)-\(serialNumber)-\(locationID)"
        }

        var displayName: String {
            var parts = [productName.isEmpty ? "CB1200AU" : productName]
            if !serialNumber.isEmpty { parts.append("SN \(serialNumber)") }
            parts.append(String(format: "VID-%04X PID-%04X", vendorID, productID))
            if locationID != 0 { parts.append(String(format: "USB 0x%08X", locationID)) }
            return parts.joined(separator: " — ")
        }
    }

    private let manager: IOHIDManager
    private(set) var current: WalkPlayHIDDevice?
    private(set) var availableCandidates: [CandidateInfo] = []

    var onDeviceStateChanged: ((WalkPlayHIDDevice?) -> Void)?
    var onCandidatesChanged: (([CandidateInfo]) -> Void)?

    private let probeQueue = DispatchQueue(label: "local.cb1200au.peqmenu.hid-probe", qos: .userInitiated)
    private var probeInProgress = false
    private var probeGeneration: UInt = 0
    private var initialStartupScanComplete = false
    private var candidateDevices: [String: IOHIDDevice] = [:]

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = WalkPlayProtocol.vendorIDs.sorted().map { vendorID in
            [
                kIOHIDVendorIDKey as String: NSNumber(value: vendorID),
                kIOHIDTransportKey as String: "USB"
            ]
        }
        DebugLog.info("initializing IOHIDManager with supported USB VID allowlist count=\(WalkPlayProtocol.vendorIDs.count)")
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let owner = Unmanaged<WalkPlayDeviceManager>.fromOpaque(context).takeUnretainedValue()
            owner.deviceMatched(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let owner = Unmanaged<WalkPlayDeviceManager>.fromOpaque(context).takeUnretainedValue()
            owner.deviceRemoved(device)
        }, context)

        let runLoopMode = CFRunLoopMode.defaultMode!.rawValue
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), runLoopMode)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            DebugLog.info(String(format: "IOHIDManagerOpen failed: 0x%08X", result))
        } else {
            DebugLog.info("IOHIDManager opened successfully")
        }
    }

    deinit {
        current?.close()
        let runLoopMode = CFRunLoopMode.defaultMode!.rawValue
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), runLoopMode)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func resetAndRescan(reason: String = "manual rescan") {
        precondition(Thread.isMainThread, "WalkPlayDeviceManager.resetAndRescan must run on the main thread")
        probeGeneration &+= 1
        probeInProgress = false
        DebugLog.info("resetAndRescan: invalidating current device/candidate state (reason=\(reason))")

        current?.close()
        current = nil
        availableCandidates.removeAll()
        candidateDevices.removeAll()
        onCandidatesChanged?(availableCandidates)
        onDeviceStateChanged?(nil)
        scanExistingDevices(reason: reason, startupScan: false)
    }

    func scanExistingDevices(reason: String = "manual scan", startupScan: Bool = false) {
        precondition(Thread.isMainThread, "WalkPlayDeviceManager.scanExistingDevices must run on the main thread")
        guard !probeInProgress else {
            DebugLog.info("scanExistingDevices skipped: probe already in progress (reason=\(reason))")
            return
        }

        guard let set = IOHIDManagerCopyDevices(manager) else {
            DebugLog.info("IOHIDManagerCopyDevices returned nil (reason=\(reason))")
            if startupScan { initialStartupScanComplete = true }
            return
        }

        let allDevices = (set as NSSet).map { $0 as! IOHIDDevice }
        let devices = deduplicatePhysicalInterfaces(allDevices.filter(isWalkPlayCandidate))
        DebugLog.info("enumeration: \(allDevices.count) HID interfaces matched the vendor/USB filter; \(devices.count) protocol candidates will be probed (reason=\(reason))")

        if devices.isEmpty {
            availableCandidates.removeAll()
            candidateDevices.removeAll()
            onCandidatesChanged?(availableCandidates)
            if startupScan { initialStartupScanComplete = true }
            DebugLog.info("no candidate HID interfaces currently connected; waiting for event-driven HID connection callbacks")
            return
        }

        if startupScan {
            initialStartupScanComplete = false
        }
        probeInProgress = true
        let generation = probeGeneration

        probeQueue.async { [weak self] in
            guard let self else { return }
            var discovered: [(CandidateInfo, IOHIDDevice)] = []
            for device in devices {
                if generation != self.probeGeneration { break }
                let candidate = WalkPlayHIDDevice(device: device)
                var opened = false
                do {
                    try candidate.open()
                    opened = true
                    try candidate.probeProtocol(timeout: 0.8)
                    let info = self.candidateInfo(for: candidate)
                    discovered.append((info, device))
                    candidate.close()
                } catch {
                    if opened { candidate.close() }
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.probeInProgress = false
                guard generation == self.probeGeneration else {
                    self.scanExistingDevices(reason: "post-reset fresh scan", startupScan: false)
                    return
                }

                self.availableCandidates.removeAll()
                self.candidateDevices.removeAll()
                for (info, device) in discovered {
                    if self.availableCandidates.contains(where: { $0.key == info.key }) { continue }
                    self.availableCandidates.append(info)
                    self.candidateDevices[info.key] = device
                }
                self.availableCandidates.sort {
                    ($0.productName, $0.serialNumber, $0.locationID) < ($1.productName, $1.serialNumber, $1.locationID)
                }
                DebugLog.info("confirmed WalkPlay candidate count=\(self.availableCandidates.count)")
                self.onCandidatesChanged?(self.availableCandidates)

                if startupScan {
                    self.initialStartupScanComplete = true
                }

                if self.current == nil, self.availableCandidates.count == 1 {
                    self.selectCandidate(at: 0)
                }
            }
        }
    }

    var currentCandidateKey: String? {
        guard let current else { return nil }
        return candidateInfo(for: current).key
    }

    func selectCandidate(key: String) {
        precondition(Thread.isMainThread, "WalkPlayDeviceManager.selectCandidate(key:) must run on the main thread")
        guard let index = availableCandidates.firstIndex(where: { $0.key == key }) else { return }
        selectCandidate(at: index)
    }

    func selectCandidate(at index: Int) {
        precondition(Thread.isMainThread, "WalkPlayDeviceManager.selectCandidate must run on the main thread")
        guard !probeInProgress, availableCandidates.indices.contains(index) else { return }
        let info = availableCandidates[index]
        if info.key == currentCandidateKey { return }
        if let current {
            current.close()
            self.current = nil
            onDeviceStateChanged?(nil)
        }
        guard let rawDevice = candidateDevices[info.key] else { return }
        probeAndSelect(rawDevice, expectedKey: info.key)
    }

    private func probeAndSelect(_ rawDevice: IOHIDDevice, expectedKey: String) {
        precondition(Thread.isMainThread, "WalkPlayDeviceManager.probeAndSelect must run on the main thread")
        guard current == nil, !probeInProgress else { return }
        let candidate = WalkPlayHIDDevice(device: rawDevice)
        let generation = probeGeneration
        probeInProgress = true

        probeQueue.async { [weak self] in
            guard let self else { return }
            var opened = false
            var probeError: Error?
            do {
                try candidate.open()
                opened = true
                try candidate.probeProtocol(timeout: 0.8)
            } catch {
                probeError = error
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    if opened { candidate.close() }
                    return
                }
                self.probeInProgress = false
                guard generation == self.probeGeneration else {
                    if opened { candidate.close() }
                    return
                }
                guard opened, probeError == nil else {
                    if opened { candidate.close() }
                    DebugLog.info("selection probe failed for candidate \(expectedKey): \(probeError?.localizedDescription ?? "unknown error")")
                    self.availableCandidates.removeAll { $0.key == expectedKey }
                    self.candidateDevices.removeValue(forKey: expectedKey)
                    self.onCandidatesChanged?(self.availableCandidates)
                    return
                }
                self.current = candidate
                DebugLog.info(String(format: "SELECTED WalkPlay device VID=0x%04X PID=0x%04X product=%@", candidate.vendorID, candidate.productID, candidate.productName))
                self.onDeviceStateChanged?(candidate)
                self.onCandidatesChanged?(self.availableCandidates)
            }
        }
    }

    private func deviceMatched(_ device: IOHIDDevice) {
        guard isWalkPlayCandidate(device) else { return }
        let info = deviceInfo(for: device)
        DebugLog.info("HID matching callback for supported vendor candidate: \(info.displayName)")
        guard !probeInProgress, !availableCandidates.contains(where: { $0.key == info.key }) else { return }
        probeAndAddCandidate(device, info: info)
    }

    private func probeAndAddCandidate(_ device: IOHIDDevice, info: CandidateInfo) {
        let generation = probeGeneration
        probeInProgress = true
        let candidate = WalkPlayHIDDevice(device: device)

        probeQueue.async { [weak self] in
            guard let self else { return }
            var opened = false
            var success = false
            do {
                try candidate.open()
                opened = true
                try candidate.probeProtocol(timeout: 0.8)
                success = true
            } catch {
                DebugLog.info("event-driven candidate probe failed for \(info.displayName): \(error.localizedDescription)")
            }
            if opened { candidate.close() }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.probeInProgress = false
                guard generation == self.probeGeneration else { return }
                if success {
                    self.candidateDevices[info.key] = device
                    if !self.availableCandidates.contains(where: { $0.key == info.key }) {
                        self.availableCandidates.append(info)
                        self.availableCandidates.sort {
                            ($0.productName, $0.serialNumber, $0.locationID) < ($1.productName, $1.serialNumber, $1.locationID)
                        }
                    }
                    self.onCandidatesChanged?(self.availableCandidates)
                    if self.current == nil, self.availableCandidates.count == 1 {
                        if let index = self.availableCandidates.firstIndex(where: { $0.key == info.key }) {
                            self.selectCandidate(at: index)
                        }
                    }
                }
            }
        }
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let info = deviceInfo(for: device)
        availableCandidates.removeAll { $0.key == info.key }
        candidateDevices.removeValue(forKey: info.key)
        onCandidatesChanged?(availableCandidates)

        guard let current, current.device == device else { return }
        DebugLog.info(String(format: "SELECTED WalkPlay device removed VID=0x%04X PID=0x%04X; waiting for HID connection event", current.vendorID, current.productID))
        current.close()
        self.current = nil
        onDeviceStateChanged?(nil)

        if availableCandidates.count == 1 {
            selectCandidate(at: 0)
        }
    }

    private func deduplicatePhysicalInterfaces(_ devices: [IOHIDDevice]) -> [IOHIDDevice] {
        var seen = Set<String>()
        return devices.sorted { candidateScore($0) < candidateScore($1) }.filter { device in
            let info = deviceInfo(for: device)
            if seen.contains(info.key) { return false }
            seen.insert(info.key)
            return true
        }
    }

    private func candidateScore(_ device: IOHIDDevice) -> Int {
        let usagePage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
        if usagePage >= 0xFF00 { return 0 }
        if usagePage == 0 { return 1 }
        return 2
    }

    private func candidateInfo(for candidate: WalkPlayHIDDevice) -> CandidateInfo {
        CandidateInfo(vendorID: candidate.vendorID, productID: candidate.productID, productName: candidate.productName, serialNumber: candidate.serialNumber, locationID: candidate.locationID, usagePage: candidate.usagePage)
    }

    private func deviceInfo(for device: IOHIDDevice) -> CandidateInfo {
        let vid = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? -1
        let pid = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? -1
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "CB1200AU"
        let serial = (IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String) ?? ""
        let location = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber)?.intValue ?? 0
        let usagePage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
        return CandidateInfo(vendorID: vid, productID: pid, productName: product, serialNumber: serial, locationID: location, usagePage: usagePage)
    }

    private func isWalkPlayCandidate(_ device: IOHIDDevice) -> Bool {
        let vid = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? -1
        let transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String)?.uppercased()
        guard WalkPlayProtocol.vendorIDs.contains(vid) else { return false }
        guard transport == "USB" || transport == "USB DEVICE" else { return false }
        return true
    }
}

// MARK: - Menu bar app

private enum PEQState {
    case unknown
    case enabled
    case disabled
    case reading
    case error(String)
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var menuStatusItem: NSMenuItem!
    private var deviceMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var deviceManager: WalkPlayDeviceManager!
    private var startupDevicePickerShown = false
    private var peqState: PEQState = .unknown
    private var stateReadInProgress = false
    private var toggleInProgress = false
    private var customProfile: CachedPEQProfile?
    private var customProfileURL: URL?
    private var customProfileLoadError: String?
    private var operationGeneration: UInt = 0
    private let profileWatcher = DevicePEQProfileWatcher()

    private let hidQueue = DispatchQueue(label: "local.cb1200au.peqmenu.hid", qos: .userInitiated)

    func applicationDidFinishLaunching(_ notification: Notification) {
        SandboxPaths.ensureDirectories()
        DebugLog.printLogLocation()
        DebugLog.info("BUILD_FINGERPRINT=\(BUILD_FINGERPRINT)")
        DebugLog.info("applicationDidFinishLaunching: App Sandbox container-only storage; exact CB1200AU VID/PID HID matching; no network entitlements requested")
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = nil
        button.title = "EQ ?"
        button.toolTip = "CB1200AU WalkPlay PEQ"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        menu = NSMenu()
        menu.autoenablesItems = false
        menuStatusItem = NSMenuItem(title: "PEQ: Unknown", action: nil, keyEquivalent: "")
        menuStatusItem.isEnabled = false
        menu.addItem(menuStatusItem)
        let toggleSeparator = NSMenuItem.separator()
        menu.addItem(toggleSeparator)
        toggleMenuItem = NSMenuItem(title: "Toggle PEQ", action: #selector(togglePEQFromMenu(_:)), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)
        menu.addItem(.separator())
        deviceMenuItem = NSMenuItem(title: "Device: None", action: nil, keyEquivalent: "")
        deviceMenuItem.submenu = NSMenu()
        deviceMenuItem.submenu?.autoenablesItems = false
        menu.addItem(deviceMenuItem)
        let refresh = NSMenuItem(title: "Rescan now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        updateStatusItem()

        profileWatcher.onChange = { [weak self] url in
            self?.reloadCachedProfileFromDiskIfRelevant(url: url)
        }
        profileWatcher.start(directory: DevicePEQProfileStore.expectedDirectoryURL())

        deviceManager = WalkPlayDeviceManager()
        deviceManager.onCandidatesChanged = { [weak self] candidates in
            guard let self else { return }
            self.updateDeviceMenu(candidates: candidates)
            if !self.startupDevicePickerShown, candidates.count > 1 {
                self.startupDevicePickerShown = true
                self.presentStartupDevicePicker(candidates: candidates)
            }
        }
        deviceManager.onDeviceStateChanged = { [weak self] device in
            DispatchQueue.main.async {
                guard let self else { return }
                self.operationGeneration &+= 1
                self.stateReadInProgress = device != nil
                self.toggleInProgress = false
                self.peqState = device == nil ? .unknown : .reading
                self.customProfile = nil
                self.customProfileURL = nil
                self.customProfileLoadError = nil
                self.profileWatcher.watchProfile(device.map { DevicePEQProfileStore.expectedProfileURL(for: $0) })
                self.updateStatusItem()
                guard let device else {
                    DebugLog.info("no WalkPlay device selected; waiting for HID connection event; application remains running")
                    return
                }
                self.readPEQStateOnce(for: device)
            }
        }
        deviceManager.scanExistingDevices(reason: "AppDelegate startup", startupScan: true)
    }

    private func updateDeviceMenu(candidates: [WalkPlayDeviceManager.CandidateInfo]) {
        guard let submenu = deviceMenuItem?.submenu else { return }
        submenu.removeAllItems()

        if candidates.isEmpty {
            let item = NSMenuItem(title: "No supported CB1200AU devices connected", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        } else {
            for candidate in candidates {
                let item = NSMenuItem(title: candidate.displayName, action: #selector(selectDeviceFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = candidate.key
                item.state = (candidate.key == deviceManager.currentCandidateKey) ? .on : .off
                submenu.addItem(item)
            }
        }

        let currentName = deviceManager?.current.map { WalkPlayDeviceManager.CandidateInfo(vendorID: $0.vendorID, productID: $0.productID, productName: $0.productName, serialNumber: $0.serialNumber, locationID: $0.locationID, usagePage: $0.usagePage).displayName }
        deviceMenuItem.title = currentName.map { "Device: \($0)" } ?? (candidates.count > 1 ? "Device: Select…" : "Device: None")
    }

    private func presentStartupDevicePicker(candidates: [WalkPlayDeviceManager.CandidateInfo]) {
        guard deviceManager.current == nil, candidates.count > 1 else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Select a CB1200AU device"
        alert.informativeText = "More than one supported CB1200AU device was discovered. Choose which device this menu-bar app should control. You can change the selection later from the Device menu."

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 430, height: 26), pullsDown: false)
        for candidate in candidates {
            popup.addItem(withTitle: candidate.displayName)
            popup.lastItem?.representedObject = candidate.key
        }
        alert.accessoryView = popup
        alert.addButton(withTitle: "Select")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn,
           let key = popup.selectedItem?.representedObject as? String {
            deviceManager.selectCandidate(key: key)
        }
        updateDeviceMenu(candidates: deviceManager.availableCandidates)
    }

    @objc private func selectDeviceFromMenu(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        guard !stateReadInProgress, !toggleInProgress else { return }
        deviceManager.selectCandidate(key: key)
        updateDeviceMenu(candidates: deviceManager.availableCandidates)
    }

    @objc private func togglePEQFromMenu(_ sender: NSMenuItem) {
        togglePEQ()
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        switch event.type {
        case .leftMouseUp:
            DebugLog.info("status item left-click: toggle PEQ")
            togglePEQ()
        case .rightMouseUp:
            DebugLog.info("status item right-click: show menu")
            menu.popUp(positioning: nil, at: NSPoint(x: statusItem.button?.bounds.midX ?? 0, y: 0), in: statusItem.button)
        default: break
        }
    }

    private func readPEQStateOnce(for device: WalkPlayHIDDevice) {
        let generation = operationGeneration
        hidQueue.async { [weak self, weak device] in
            guard let self, let device else { return }
            do {
                let result = try device.readPEQProfile()
                guard self.isOperationCurrent(generation) else {
                    DebugLog.info("discarding stale PEQ state read result after disconnect/rescan")
                    return
                }

                var loadedProfile: CachedPEQProfile?
                var loadedURL: URL?
                var loadError: String?

                if result.enabled {
                    guard let profile = result.customProfile else {
                        throw HIDError.protocolError("Current custom PEQ slot 0x\(String(result.slotID, radix: 16)) could not be cached")
                    }
                    loadedProfile = profile
                    do {
                        let url = try DevicePEQProfileStore.save(profile.devicePEQ, for: device)
                        loadedURL = url
                        DebugLog.info("saved live custom DevicePEQ profile to disk: \(url.path)")
                    } catch {
                        loadError = "The live custom PEQ profile is cached in RAM, but could not be saved to disk: \(error.localizedDescription)"
                        DebugLog.info("failed to save live custom DevicePEQ profile: \(error.localizedDescription)")
                    }
                } else {
                    do {
                        if let (textProfile, url) = try DevicePEQProfileStore.load(for: device) {
                            let loaded = try DevicePEQProfileCodec.cachedProfile(from: textProfile)
                            loadedProfile = loaded
                            loadedURL = url
                            loadError = nil
                            DebugLog.info(String(format: "loaded custom DevicePEQ profile from disk into RAM: slot=%d (0x%02X) path=%@", loaded.slotID, loaded.slotID, url.path))
                        } else {
                            loadError = missingCustomProfileMessage(for: device)
                            DebugLog.info("no custom DevicePEQ profile found on disk; expected path=\(DevicePEQProfileStore.expectedProfileURL(for: device).path)")
                        }
                    } catch {
                        loadError = "The saved DevicePEQ profile could not be loaded: \(error.localizedDescription)\n\nExpected path:\n\(DevicePEQProfileStore.expectedProfileURL(for: device).path)"
                        DebugLog.info("failed to load DevicePEQ profile: \(error.localizedDescription)")
                    }
                }

                guard self.isOperationCurrent(generation) else {
                    DebugLog.info("discarding stale PEQ state/profile result after disconnect/rescan")
                    return
                }

                DispatchQueue.main.async {
                    guard self.operationGeneration == generation, self.deviceManager.current === device else { return }
                    self.customProfile = loadedProfile
                    self.customProfileURL = loadedURL
                    self.customProfileLoadError = loadError
                    self.stateReadInProgress = false
                    self.peqState = result.enabled ? .enabled : .disabled
                    self.profileWatcher.watchProfile(loadedURL ?? DevicePEQProfileStore.expectedProfileURL(for: device))
                    self.updateStatusItem()
                    DebugLog.info(String(format: "launch/connect PEQ state read completed: slot=%d (0x%02X), enabled=%@", result.slotID, result.slotID, result.enabled ? "true" : "false"))
                    if !result.enabled, let message = self.customProfileLoadError {
                        self.showCustomProfileRequiredAlert(for: device, details: message)
                    } else if result.enabled, let message = self.customProfileLoadError {
                        self.showNonFatalProfileAlert(message)
                    }
                }
            } catch {
                DebugLog.info("launch/connect PEQ state read failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    guard self.operationGeneration == generation, self.deviceManager.current === device else { return }
                    self.stateReadInProgress = false
                    self.peqState = .error(error.localizedDescription)
                    self.updateStatusItem()
                }
            }
        }
    }

    private func togglePEQ() {
        guard let device = deviceManager.current else { return }
        guard !stateReadInProgress, !toggleInProgress else { return }

        let currentlyEnabled: Bool
        switch peqState {
        case .enabled: currentlyEnabled = true
        case .disabled: currentlyEnabled = false
        case .unknown, .reading, .error:
            DebugLog.info("toggle ignored because cached PEQ state is not usable: \(String(describing: peqState))")
            return
        }

        let newState = !currentlyEnabled
        let profileForToggle = customProfile
        if newState && profileForToggle == nil {
            showCustomProfileRequiredAlert(for: device, details: customProfileLoadError ?? missingCustomProfileMessage(for: device))
            return
        }

        toggleInProgress = true
        peqState = .reading
        updateStatusItem()
        let generation = operationGeneration

        hidQueue.async { [weak self, weak device] in
            guard let self, let device else { return }
            do {
                DebugLog.info("toggle requested: current=\(currentlyEnabled ? "enabled" : "disabled"), sending=\(newState ? "enable" : "disable"), targetSlot=\(newState ? String(profileForToggle?.slotID ?? 0) : "1")")
                try device.setPEQ(enabled: newState, customProfile: profileForToggle)
                DebugLog.info("PEQ write succeeded; verifying current PEQ state with full profile read")
                let result = try device.readPEQProfile()
                guard self.isOperationCurrent(generation) else {
                    DebugLog.info("discarding stale PEQ toggle result after disconnect/rescan")
                    return
                }

                let refreshedProfile = result.enabled ? result.customProfile : nil
                DispatchQueue.main.async {
                    guard self.operationGeneration == generation, self.deviceManager.current === device else { return }
                    if let refreshedProfile {
                        self.customProfile = refreshedProfile
                    }
                    self.toggleInProgress = false
                    self.peqState = result.enabled ? .enabled : .disabled
                    self.updateStatusItem()
                    DebugLog.info(String(format: "post-toggle verification: slot=%d (0x%02X), enabled=%@", result.slotID, result.slotID, result.enabled ? "true" : "false"))
                }
            } catch {
                DebugLog.info("PEQ toggle or post-toggle verification failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    guard self.operationGeneration == generation, self.deviceManager.current === device else { return }
                    self.toggleInProgress = false
                    self.peqState = .error(error.localizedDescription)
                    self.updateStatusItem()
                }
            }
        }
    }

    @objc private func refreshNow() {
        DebugLog.info("manual Rescan now requested: resetting application/device state and restarting discovery from scratch")
        operationGeneration &+= 1
        stateReadInProgress = false
        toggleInProgress = false
        peqState = .unknown
        customProfile = nil
        customProfileURL = nil
        customProfileLoadError = nil
        profileWatcher.watchProfile(nil)
        updateStatusItem()
        deviceManager.resetAndRescan(reason: "manual Rescan now")
    }

    private func isOperationCurrent(_ generation: UInt) -> Bool {
        if Thread.isMainThread {
            return operationGeneration == generation
        }
        return DispatchQueue.main.sync { operationGeneration == generation }
    }

    private func reloadCachedProfileFromDiskIfRelevant(url: URL) {
        guard let device = deviceManager.current else {
            DebugLog.info("cached DevicePEQ profile changed while no WalkPlay device is connected: \(url.path)")
            return
        }
        let expectedURL = DevicePEQProfileStore.expectedProfileURL(for: device)
        guard url.standardizedFileURL == expectedURL.standardizedFileURL else {
            DebugLog.info("cached DevicePEQ profile changed for another HID device; ignoring for current device: \(url.path)")
            return
        }

        let generation = operationGeneration
        hidQueue.async { [weak self, weak device] in
            guard let self, let device else { return }
            do {
                guard let (textProfile, loadedURL) = try DevicePEQProfileStore.load(for: device) else {
                    DebugLog.info("cached DevicePEQ profile file disappeared: \(url.path)")
                    DispatchQueue.main.async {
                        guard self.operationGeneration == generation, self.deviceManager.current === device else { return }
                        self.customProfile = nil
                        self.customProfileURL = nil
                        self.customProfileLoadError = self.missingCustomProfileMessage(for: device)
                        self.updateStatusItem()
                    }
                    return
                }
                let loaded = try DevicePEQProfileCodec.cachedProfile(from: textProfile)
                guard self.isOperationCurrent(generation) else { return }
                DispatchQueue.main.async {
                    guard self.operationGeneration == generation, self.deviceManager.current === device else { return }
                    self.customProfile = loaded
                    self.customProfileURL = loadedURL
                    self.customProfileLoadError = nil
                    DebugLog.info(String(format: "automatically reloaded edited DevicePEQ profile into RAM: slot=%d (0x%02X) path=%@", loaded.slotID, loaded.slotID, loadedURL.path))
                    self.updateStatusItem()
                }
            } catch {
                DebugLog.info("edited DevicePEQ profile could not be loaded into RAM: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    guard self.operationGeneration == generation, self.deviceManager.current === device else { return }
                    self.customProfileLoadError = "The edited DevicePEQ profile could not be loaded: \(error.localizedDescription)\n\nPath:\n\(url.path)"
                    self.updateStatusItem()
                }
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        button.image = nil
        switch peqState {
        case .unknown:
            button.title = "EQ ?"
            menuStatusItem?.title = deviceManager?.current == nil ? "PEQ: Unknown — no CB1200AU connected" : "PEQ: Unknown"
        case .reading:
            button.title = "EQ …"
            menuStatusItem?.title = "PEQ: Reading status…"
        case .enabled:
            button.title = "EQ ✓"
            menuStatusItem?.title = customProfile.map { "PEQ: ON — slot \($0.slotID)" } ?? "PEQ: ON"
        case .disabled:
            button.title = "EQ —"
            menuStatusItem?.title = customProfile == nil ? "PEQ: OFF — custom profile unavailable" : "PEQ: OFF"
        case let .error(message):
            button.title = "EQ !"
            menuStatusItem?.title = "PEQ: Error — \(message)"
        }
        if let toggleMenuItem {
            switch peqState {
            case .enabled, .disabled:
                toggleMenuItem.isEnabled = !stateReadInProgress && !toggleInProgress && deviceManager?.current != nil
                toggleMenuItem.title = "Toggle PEQ"
            default:
                toggleMenuItem.isEnabled = false
                toggleMenuItem.title = "Toggle PEQ"
            }
        }
        updateDeviceMenu(candidates: deviceManager?.availableCandidates ?? [])
    }

    private func showCustomProfileRequiredAlert(for device: WalkPlayHIDDevice, details: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Custom PEQ profile required"
        alert.informativeText = "The device is currently on built-in flat slot 1, but this app does not have a saved custom DevicePEQ profile for this HID device.\n\nLoad the custom PEQ profile to the device with DevicePEQ or the official WalkPlay app, then choose Rescan now. You can also populate this file manually using the DevicePEQ export format plus a final Slot: <0-255> line:\n\n\(DevicePEQProfileStore.expectedProfileURL(for: device).path)\n\n\(details)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showNonFatalProfileAlert(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Custom PEQ profile was not saved"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func missingCustomProfileMessage(for device: WalkPlayHIDDevice) -> String {
        "No custom DevicePEQ profile was found. Expected path:\n\(DevicePEQProfileStore.expectedProfileURL(for: device).path)"
    }

    @objc private func quit() {
        profileWatcher.stop()
        deviceManager.current?.close()
        NSApp.terminate(nil)
    }
}

@main
private enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
