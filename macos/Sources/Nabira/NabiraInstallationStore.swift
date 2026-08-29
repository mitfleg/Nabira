import CryptoKit
import Foundation
import IOKit

enum NabiraDeviceIdentityError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        NabiraCopy.text(
            "Не удалось определить это устройство.",
            "Could not identify this device."
        )
    }
}

enum NabiraDeviceIdentity {
    // В API уходит только необратимый SHA-256, а не IOPlatformUUID устройства.
    static func identifier() throws -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != IO_OBJECT_NULL else { throw NabiraDeviceIdentityError.unavailable }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            throw NabiraDeviceIdentityError.unavailable
        }

        let normalized = property.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { throw NabiraDeviceIdentityError.unavailable }
        let digest = SHA256.hash(data: Data("nabira-device-v1:\(normalized)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
