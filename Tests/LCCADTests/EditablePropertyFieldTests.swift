import XCTest
@testable import LCCAD

/// `EditablePropertyField.valueToCommit` の確定判定ロジックのテスト (#55)。
/// 無編集フォーカスアウトで丸め表示値が書き戻されないことを保証する。
final class EditablePropertyFieldTests: XCTestCase {

    // MARK: - 無編集ガード (#55)

    func testUnchangedTextDoesNotCommit() {
        // アスペクトロック付きスケール後の H=66.6667mm は「66.7」と表示される。
        // 無編集のままフォーカスアウトしても丸め値をコミットしてはならない。
        XCTAssertNil(EditablePropertyField.valueToCommit(
            editText: "66.7", textAtEditStart: "66.7", range: nil))
    }

    func testRetypingSameStringDoesNotCommit() {
        // 一度消して同じ文字列を打ち直した場合も表示文字列は不変なので確定しない
        XCTAssertNil(EditablePropertyField.valueToCommit(
            editText: "137.3", textAtEditStart: "137.3", range: 0.1...10000))
    }

    // MARK: - 通常の確定

    func testChangedTextCommitsParsedValue() {
        XCTAssertEqual(EditablePropertyField.valueToCommit(
            editText: "50", textAtEditStart: "30.0", range: nil), 50)
    }

    func testChangedTextClampsToRange() {
        XCTAssertEqual(EditablePropertyField.valueToCommit(
            editText: "500", textAtEditStart: "30.0", range: 0.1...200), 200)
        XCTAssertEqual(EditablePropertyField.valueToCommit(
            editText: "0", textAtEditStart: "30.0", range: 0.1...200), 0.1)
    }

    func testNumericallyEqualButDifferentStringCommits() {
        // "30" と "30.0" は文字列としては別 → 明示的な打ち直しとして確定する。
        // 実質同値のコミットは ViewModel 側の no-op ガードが吸収する
        XCTAssertEqual(EditablePropertyField.valueToCommit(
            editText: "30", textAtEditStart: "30.0", range: nil), 30)
    }

    // MARK: - 無効値

    func testInvalidTextDoesNotCommit() {
        XCTAssertNil(EditablePropertyField.valueToCommit(
            editText: "abc", textAtEditStart: "30.0", range: nil))
        XCTAssertNil(EditablePropertyField.valueToCommit(
            editText: "", textAtEditStart: "30.0", range: nil))
    }
}
