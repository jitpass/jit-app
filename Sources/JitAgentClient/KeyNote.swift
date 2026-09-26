// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// jit's `key_note` after a revoke or a remove (internal/agent's
/// keyNoteOf), read as one of its two meanings. The grant or job is gone
/// either way; what differs is the key.
public enum KeyNote: Equatable, Sendable {
    /// The key sits in a Secure Enclave this copy of jit can't reach, and
    /// the service deletes it the next time it starts: expected, neutral.
    /// jit's sentence, shown as it is.
    case kept(String)
    /// The delete failed. jit's sentence carries the raw error, so it is
    /// not shown: the banner says so in plain words, and the error is in
    /// jit's own trail (the grant_end or job event's cause).
    case deleteFailed

    /// jit sends a sentence and no structured field, so the failure is
    /// told by the start keyNoteOf gives it: "Its key couldn't be deleted
    /// (<error>); …". Anything else is the neutral note. nil for none.
    public init?(_ text: String?) {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else {
            return nil
        }
        self = text.hasPrefix(Self.failedStart) ? .deleteFailed : .kept(text)
    }

    static let failedStart = "Its key couldn't be deleted"

    /// The failure is a failure banner (red), per "colour carries state".
    public var failed: Bool {
        self == .deleteFailed
    }

    /// The banner's sentence about the key.
    public var sentence: String {
        switch self {
        case let .kept(text): text
        case .deleteFailed: "Its key couldn't be deleted; JitPass's service tries again the next time it starts."
        }
    }
}
