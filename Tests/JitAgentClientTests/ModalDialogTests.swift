// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import XCTest

/// The app target has no tests of its own, so this reads its sources: every
/// alert and file panel must open through `runFrontmost`, which brings the
/// accessory app forward first. A bare `runModal()` opened the passphrase
/// dialog inactive, with a grey default button and no keyboard.
final class ModalDialogTests: XCTestCase {
    func testEveryModalDialogBringsTheAppForward() throws {
        let app = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JitPassApp")
        let files = try FileManager.default.contentsOfDirectory(atPath: app.path)
            .filter { $0.hasSuffix(".swift") && $0 != "Frontmost.swift" }
        XCTAssertFalse(files.isEmpty, "no sources found under \(app.path)")
        for file in files {
            let source = try String(contentsOf: app.appendingPathComponent(file), encoding: .utf8)
            for (number, line) in source.components(separatedBy: "\n").enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.contains(".runModal("), !code.hasPrefix("//") {
                    XCTFail("\(file):\(number + 1) calls runModal(); use runFrontmost()")
                }
            }
        }
    }

    /// A SwiftUI question asked as a modal from inside a SwiftUI button's
    /// action never answers: its buttons and Return are dead, and the app
    /// had to be killed (Protect in 2.3.1). `ModalHost.ask` starts its modal
    /// loop on the run loop's next turn, and nothing else starts one.
    func testTheSwiftUIModalStartsAfterTheClick() throws {
        let app = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JitPassApp")
        let host = try String(contentsOf: app.appendingPathComponent("Frontmost.swift"), encoding: .utf8)
        guard let ask = host.range(of: "static func ask"), let run = host.range(of: "runModal(for:") else {
            return XCTFail("ModalHost.ask or its runModal(for:) is gone from Frontmost.swift")
        }
        let body = host[ask.upperBound ..< run.lowerBound]
        XCTAssertTrue(body.contains("RunLoop.main.perform"), "ModalHost.ask must defer its modal loop past the caller")
        let others = try FileManager.default.contentsOfDirectory(atPath: app.path)
            .filter { $0.hasSuffix(".swift") && $0 != "Frontmost.swift" }
        for file in others {
            let source = try String(contentsOf: app.appendingPathComponent(file), encoding: .utf8)
            XCTAssertFalse(source.contains("runModal(for:"), "\(file) starts a modal loop; ask through ModalHost")
        }
    }
}
