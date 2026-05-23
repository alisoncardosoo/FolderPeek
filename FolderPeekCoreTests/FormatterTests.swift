import XCTest
@testable import FolderPeekCore

final class FormatterTests: XCTestCase {
    func testNilSizeUsesPlaceholder() {
        XCTAssertEqual(FolderPeekFormatters.sizeString(nil), "--")
    }

    func testItemCountMarksLimit() {
        XCTAssertEqual(FolderPeekFormatters.itemCountString(10, reachedLimit: false), "10 itens")
        XCTAssertEqual(FolderPeekFormatters.itemCountString(10, reachedLimit: true), "10+ itens")
    }
}
