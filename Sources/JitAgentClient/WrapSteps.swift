// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A wrap that needs a step before it: `jit vault set` then `jit wrap`,
/// or `jit migrate <rc>` then `jit wrap add`. When the first step worked
/// and the wrap did not, the first step's change is real — the key is in
/// the vault, the rc file is rewritten — and the Tools window used to say
/// "Nothing was changed" over it (2026-09-27). This is that run: jit's
/// text for each step that worked, and the wrap's line when it failed.
public struct WrapSteps: Sendable, Equatable {
    public var text: [String]
    public var wrapFailed: String?

    public init(text: [String], wrapFailed: String? = nil) {
        self.text = text
        self.wrapFailed = wrapFailed
    }

    public var failed: Bool {
        wrapFailed != nil
    }

    /// The result's line: `success` when the wrap worked; otherwise what
    /// the first step did (`done`) and then the wrap's failure in jit's
    /// words, "Protected ~/acme.rc · wrap globex failed: <jit's line>".
    public func title(success: String, done: String, tool: String) -> String {
        guard let wrapFailed else {
            return success
        }
        return done + " · " + ScanWording.wrapFailed(tool, line: wrapFailed)
    }

    /// jit's words, every step's, the failure last.
    public var report: String {
        (text + [wrapFailed ?? ""]).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}
