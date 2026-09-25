// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// jit's `key_note` after a revoke or a remove: a key kept in an enclave
/// this jit can't reach is a neutral note, a failed delete is a failure,
/// said without jit's raw error (internal/agent's keyNoteOf).
final class KeyNoteTests: XCTestCase {
    static let kept = "Its Secure Enclave key couldn't be reached from this copy of jit; "
        + "JitPass's service deletes it the next time it starts."
    static let failed = "Its key couldn't be deleted (OSStatus -25293: The user name or passphrase you entered is not correct.); "
        + "JitPass's service tries again the next time it starts."

    func testAFailedDeleteIsAFailureInPlainWords() throws {
        let note = try XCTUnwrap(KeyNote(Self.failed))
        XCTAssertEqual(note, .deleteFailed)
        XCTAssertTrue(note.failed)
        XCTAssertEqual(note.sentence, "Its key couldn't be deleted; JitPass's service tries again the next time it starts.")
        XCTAssertFalse(note.sentence.contains("OSStatus"))
        XCTAssertFalse(note.sentence.contains("("))
    }

    /// Control: the neutral note stays neutral, and is shown as jit said it.
    func testAKeptKeyIsNeutral() throws {
        let note = try XCTUnwrap(KeyNote(Self.kept))
        XCTAssertEqual(note, .kept(Self.kept))
        XCTAssertFalse(note.failed)
        XCTAssertEqual(note.sentence, Self.kept)
    }

    func testNoNoteIsNil() {
        XCTAssertNil(KeyNote(nil))
        XCTAssertNil(KeyNote(""))
        XCTAssertNil(KeyNote("  "))
    }
}
