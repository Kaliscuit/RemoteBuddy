import XCTest
@testable import RemoteBuddy

final class RemoteIdentityTests: XCTestCase {
    func testAcceptsAnyConfiguredRemoteAndRejectsMalformedIdentities() {
        XCTAssertEqual(RemoteIdentity.canonicalAddress("aa:bb:cc:dd:ee:ff"), "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(RemoteIdentity.canonicalAddress("11:22:33:44:55:66"), "11:22:33:44:55:66")
        for value in ["", "AA:BB:CC:DD:EE", "GG:BB:CC:DD:EE:FF", " AA:BB:CC:DD:EE:FF", "arbitrary"] {
            XCTAssertNil(RemoteIdentity.canonicalAddress(value))
        }
    }
}
