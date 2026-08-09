import XCTest
@testable import Browser

final class URLParserTests: XCTestCase {

    func testHTTPSPassthrough() {
        let url = URLParser.parse("https://example.com/path")
        XCTAssertEqual(url?.absoluteString, "https://example.com/path")
    }

    func testHTTPPassthrough() {
        let url = URLParser.parse("http://example.com")
        XCTAssertEqual(url?.scheme, "http")
        XCTAssertEqual(url?.host, "example.com")
    }

    func testBareDomainDefaultsToHTTPS() {
        let url = URLParser.parse("example.com")
        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    func testSearchQueryUsesTemplate() {
        let url = URLParser.parse("hello world")
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertTrue(url?.absoluteString.contains("hello") == true)
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(URLParser.parse("   "))
    }
}
