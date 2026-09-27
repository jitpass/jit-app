// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Wrapping a tool from the Tools and AI Agents windows. Each of these
/// runs a step before the wrap that changes something on its own (a key
/// stored, an rc file migrated); when that step worked and the wrap did
/// not, the result says both (`WrapSteps`), never "Nothing was changed".
extension StatusItemController {
    /// `jit wrap <tool>`, after the sheet said what it does. With a value,
    /// `jit vault set <path> --stdin` runs first: the CLI cannot take the
    /// key in the same step, and that one field is the reason wrapping is
    /// in-app at all. Two Touch IDs then, and the sheet said so.
    func wrapTool(_ tool: String, value: String?) {
        let record = model.toolListing?.tool(named: tool)
        if value == nil, let key = record?.shellConfigKey(scan: model.macScan) {
            wrapFromShellConfig(tool, key: key)
            return
        }
        let path = record?.injects.first?.vaultPath
        let stores = value.map { !$0.isEmpty } == true && path != nil
        let work: @Sendable () -> Result<WrapSteps, Error> = {
            guard stores, let value, let path else {
                return JitCLI.execute(["wrap", tool]).map { WrapSteps(text: [$0]) }
            }
            return Self.wrapSteps(first: ["vault", "set", path, "--stdin", "--yes"], stdin: value, wrap: ["wrap", tool])
        }
        runTools(tool, work: work, then: { [weak self] steps in
            guard let self else {
                return
            }
            model.scanStale = true
            model.toolsSheet = nil
            model.agentsSheet = nil
            let title = steps.title(success: "Wrapped \(tool)", done: Format.keyStored(path ?? tool), tool: tool)
            showResult(title: title, text: steps.report, failed: steps.failed)
            if stores {
                vaultChanged()
            }
        })
    }

    /// A tool outside the catalog: `jit vault set wrap-<tool>/VAR --stdin`
    /// with the key from the sheet, then `jit wrap add <tool> --env
    /// VAR=wrap-<tool>/VAR`, the same shape `jit wrap` gives a catalog
    /// tool, so Unwrap and the listing treat it like one.
    func handWrap(_ tool: String, name: String, value: String) {
        let path = "wrap-\(tool)/\(name)"
        let work: @Sendable () -> Result<WrapSteps, Error> = {
            Self.wrapSteps(
                first: ["vault", "set", path, "--stdin", "--yes"], stdin: value, wrap: ["wrap", "add", tool, "--env", name + "=" + path]
            )
        }
        runTools(tool, work: work, then: { [weak self] steps in
            guard let self else {
                return
            }
            model.toolsSheet = nil
            model.toolsSelected = tool
            let title = steps.title(success: "Wrapped \(tool)", done: Format.keyStored(path), tool: tool)
            showResult(title: title, text: steps.report, failed: steps.failed)
            vaultChanged()
        })
    }

    /// The key is an `export` in a shell config, which `jit wrap` does not
    /// read: `jit migrate <rc> --yes` moves it (the export line becomes a
    /// `jit export` of the same profile, so every shell keeps the var),
    /// then `jit wrap add <tool> --env VAR=<rc name>/VAR` points the shim
    /// at that copy. One Touch ID: the wrap only checks the path exists.
    private func wrapFromShellConfig(_ tool: String, key: ShellConfigKey) {
        let work: @Sendable () -> Result<WrapSteps, Error> = {
            Self.wrapSteps(first: ["migrate", key.file, "--yes"], wrap: ["wrap", "add", tool, "--env", key.name + "=" + key.vaultPath])
        }
        runTools(tool, work: work, then: { [weak self] steps in
            guard let self else {
                return
            }
            model.scanStale = true
            model.toolsSheet = nil
            model.agentsSheet = nil
            let protected = "Protected \(Format.home(key.file))"
            showResult(
                title: steps.title(success: protected + ", wrapped \(tool)", done: protected, tool: tool),
                text: steps.report,
                failed: steps.failed
            )
            vaultChanged()
            runScan(wholeMac: true, kind: .afterProtect)
        })
    }

    /// The first step, then the wrap. A first step that failed changed
    /// nothing and is the run's failure; a wrap that failed after it is
    /// recorded in the result, since the first step's change stands.
    nonisolated static func wrapSteps(first: [String], stdin: String? = nil, wrap: [String]) -> Result<WrapSteps, Error> {
        let done: String
        switch JitCLI.execute(first, stdin: stdin) {
        case let .success(text): done = text
        case let .failure(error): return .failure(error)
        }
        switch JitCLI.execute(wrap) {
        case let .success(text): return .success(WrapSteps(text: [done, text]))
        case let .failure(error): return .success(WrapSteps(text: [done], wrapFailed: describeTools(error)))
        }
    }
}
