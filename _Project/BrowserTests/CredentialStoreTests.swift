import XCTest
@testable import Browser

final class CredentialStoreTests: XCTestCase {

    func testNormalizedHostStripsWWWAndLowercases() {
        XCTAssertEqual(
            CredentialStore.normalizedHost(from: "https://WWW.Example.COM/path"),
            "example.com"
        )
    }

    func testNormalizedHostNilForInvalid() {
        XCTAssertNil(CredentialStore.normalizedHost(from: nil))
        XCTAssertNil(CredentialStore.normalizedHost(from: "not a url"))
    }

    func testSaveUpdateDeleteRoundTrip() {
        let store = CredentialStore.shared
        let host = "cred-store-test-\(UUID().uuidString.prefix(8)).example"
        let username = "user-\(UUID().uuidString.prefix(6))"

        XCTAssertNotNil(store.save(host: host, username: username, password: "first-pass"))
        XCTAssertTrue(store.hasCredential(host: host, username: username))

        let updated = store.save(host: host, username: username, password: "second-pass")
        XCTAssertEqual(updated?.password, "second-pass")

        let listed = store.credentials(forHost: host)
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.username, username)

        if let id = listed.first?.id {
            XCTAssertTrue(store.delete(id: id))
        }
        XCTAssertTrue(store.credentials(forHost: host).isEmpty)
    }

    func testDebugDescriptionRedactsPassword() {
        let cred = SavedCredential(host: "example.com", username: "a", password: "secret-value")
        let desc = String(reflecting: cred)
        XCTAssertFalse(desc.contains("secret-value"))
        XCTAssertTrue(desc.contains("<redacted>"))
    }
}
