import Testing
@testable import Nabira

@Suite("Device-bound trial identity")
struct NabiraDeviceIdentityTests {
    @Test("The identifier is stable and contains no raw platform UUID")
    func stableHashedIdentifier() throws {
        let first = try NabiraDeviceIdentity.identifier()
        let second = try NabiraDeviceIdentity.identifier()

        #expect(first == second)
        #expect(first.count == 64)
        #expect(first.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(!first.contains("-"))
    }
}
