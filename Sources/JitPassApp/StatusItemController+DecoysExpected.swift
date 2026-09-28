// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Expected readers (mockup: Decoy Bursts, section 3): the list, the mark
/// and its Undo. A mark changes what JitPass says, never what jit serves.
extension StatusItemController {
    func loadDecoyExpected() {
        Task.detached {
            let expected = JitCLI.decoysExpected()
            await MainActor.run { [weak self] in
                self?.model.decoyExpected = expected
            }
        }
    }

    /// Mark Expected, from the sheet, or Not Expected (`remove`).
    func setDecoyExpected(_ reader: ExpectedReader, remove: Bool) {
        model.decoyExpectAsk = nil
        model.decoysOutcome = nil
        Task.detached {
            let result = JitCLI.decoysExpect(reader, remove: remove)
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                switch result {
                case let .success(list):
                    model.decoyExpected = list
                    model.decoysOutcome = WindowOutcome(
                        title: Format.decoyExpectedBanner(reader, remove: remove), text: "", unexpect: remove ? nil : reader
                    )
                case let .failure(error):
                    model.decoysOutcome = WindowOutcome(
                        title: Format.decoyExpectFailed(remove: remove, Self.describeTools(error)),
                        text: "",
                        failed: true
                    )
                }
            }
        }
    }
}
