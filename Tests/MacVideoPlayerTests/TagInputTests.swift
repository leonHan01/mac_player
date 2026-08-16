import AppKit
import XCTest
@testable import MacVideoPlayer

@MainActor
final class TagInputTests: XCTestCase {
    func testTagInputFieldIsEditable() {
        let field = NSTextField()
        field.isEditable = false

        PlayerView.configureTagInputField(field)

        XCTAssertTrue(field.isEditable)
        XCTAssertTrue(field.isSelectable)
        XCTAssertTrue(field.usesSingleLineMode)
    }
}
