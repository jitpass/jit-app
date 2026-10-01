// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Wrapping a tool from the Tools and AI Agents windows. Each of these
/// can run a step before the wrap that changes something on its own (a key
/// stored, an rc file migrated); when that step worked and the wrap did
/// not, the sheet says both (`ChangeSheet.wrapped`), never "Nothing was
/// changed". The wrap itself is `--format json`: its rows are jit's
/// report, not its text.
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
        let verify = record?.verifyHint != nil
        let work: @Sendable () -> Result<WrapReport, Error> = {
            guard stores, let value, let path else {
                return Self.wrapRun(tool: tool) { JitCLI.wrap(tool) }
            }
            return Self.wrapRun(tool: tool, first: ["vault", "set", path, "--stdin", "--yes"], stdin: value) { JitCLI.wrap(tool) }
        }
        runTools(tool, work: work, then: { [weak self] report in
            guard let self else {
                return
            }
            model.scanStale = true
            model.toolsSheet = nil
            model.agentsSheet = nil
            showChanges(.wrapped(report, stored: stores ? path : nil, verify: verify))
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
        let work: @Sendable () -> Result<WrapReport, Error> = {
            Self.wrapRun(tool: tool, first: ["vault", "set", path, "--stdin", "--yes"], stdin: value) {
                JitCLI.wrapAdd(tool, env: name + "=" + path)
            }
        }
        runTools(tool, work: work, then: { [weak self] report in
            guard let self else {
                return
            }
            model.toolsSheet = nil
            model.toolsSelected = tool
            showChanges(.wrapped(report, stored: path))
            vaultChanged()
        })
    }

    /// The key is an `export` in a shell config, which `jit wrap` does not
    /// read: `jit migrate <rc> --yes` moves it (the export line becomes a
    /// `jit export` of the same profile, so every shell keeps the var),
    /// then `jit wrap add <tool> --env VAR=<rc name>/VAR` points the shim
    /// at that copy. One Touch ID: the wrap only checks the path exists.
    private func wrapFromShellConfig(_ tool: String, key: ShellConfigKey) {
        let verify = model.toolListing?.tool(named: tool)?.verifyHint != nil
        let work: @Sendable () -> Result<WrapReport, Error> = {
            Self.wrapRun(tool: tool, first: ["migrate", key.file, "--yes"]) {
                JitCLI.wrapAdd(tool, env: key.name + "=" + key.vaultPath)
            }
        }
        runTools(tool, work: work, then: { [weak self] report in
            guard let self else {
                return
            }
            model.scanStale = true
            model.toolsSheet = nil
            model.agentsSheet = nil
            showChanges(.wrapped(report, protected: Format.home(key.file), verify: verify))
            vaultChanged()
            runScan(wholeMac: true, kind: .afterProtect)
        })
    }

    /// The first step, then the wrap. A first step that failed changed
    /// nothing and is the run's failure; a wrap that wrote no report after
    /// it is recorded as the report's error, since the first step's change
    /// stands.
    nonisolated static func wrapRun(
        tool: String, first: [String]? = nil, stdin: String? = nil, wrap: @Sendable () -> Result<WrapReport, Error>
    ) -> Result<WrapReport, Error> {
        if let first, case let .failure(error) = JitCLI.execute(first, stdin: stdin) {
            return .failure(error)
        }
        switch wrap() {
        case let .success(report):
            return .success(report)
        case let .failure(error):
            return .success(WrapReport(tool: tool, kind: "", wrapped: false, errors: [describeTools(error)]))
        }
    }
}
