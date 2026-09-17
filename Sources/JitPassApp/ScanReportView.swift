// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The scan report, compact: the score, then "jit will protect these" (one
/// finding per line, each with a Protect button and one for the lot) and
/// "Needs you" (one row per file, the flagged lines under it, with Open
/// and Reveal). The terminal keeps the full evidence, and every protect
/// stays a terminal command, because `jit migrate` is the guided write
/// path with its own confirmations.
struct ScanReportView: View {
    @ObservedObject var model: MenuModel
    let actions: ScanActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)
            if let error = model.scanError {
                Text(error).foregroundStyle(.secondary).padding(.vertical, 20)
            } else if let report = model.scan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        protectSection(report)
                        manualSection(report.manualByFile)
                        if !report.scaffolding.isEmpty {
                            fileSection("Test fixtures and examples", ScanFileGroup.group(report.scaffolding))
                            Text(Self.scaffoldingNote).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 12)
                    .padding(.trailing, 14)
                }
            } else if !model.scanning {
                chooser
            } else {
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
    }

    /// The first thing the window shows: nothing is scanned until the user
    /// says where. A whole-home scan takes seconds and reads everything, so
    /// it is a choice, not a default.
    private var chooser: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("What should jit scan?").font(.headline)
            Text(
                "A folder scan looks only there. The whole Mac covers your home folder,\nshell configs, credential files and agent caches."
            )
            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Choose Folder…", action: actions.chooseFolder).keyboardShortcut(.defaultAction)
                Button("Scan Whole Mac", action: actions.scanWholeMac)
            }
            accessNote
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Whether a whole-Mac scan will run quietly or trigger a prompt per
    /// protected folder, and the one place that changes it.
    private var accessNote: some View {
        HStack(spacing: 6) {
            if model.fullDiskAccess {
                Text("Full Disk Access granted: a whole-Mac scan runs without prompts.")
            } else {
                Text("Without Full Disk Access, macOS asks once per protected folder.")
                Button("Grant in System Settings", action: actions.grantFullDiskAccess).buttonStyle(.link)
            }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 6)
    }

    private static let scaffoldingNote = "Real-looking values in test files or documentation. "
        + "The scanner counts them in the score; check they are not live."

    /// The CLI's headline, not a score: secrets protected over secrets
    /// known, the bar, and what closes the gap. A folder scan has no
    /// ledger of its own, so it leads with its findings instead.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if model.scanning {
                    ProgressView().controlSize(.small)
                    Text(model.scanScope == nil ? "Scanning your Mac…" : "Scanning…").font(.headline)
                } else if let s = model.scan?.summary, model.scanScope == nil {
                    Text("\(s.secretsProtected) of \(s.secretsTotal) secrets protected · \(s.percent)%").font(.headline)
                } else if let s = model.scan?.summary {
                    Text("\(s.totalFindings) finding\(s.totalFindings == 1 ? "" : "s")").font(.headline)
                } else {
                    Text("Protected").font(.headline)
                }
                Spacer(minLength: 16)
                if !model.fullDiskAccess {
                    Button("Grant Full Disk Access", action: actions.grantFullDiskAccess)
                        .help("Opens System Settings › Privacy & Security › Full Disk Access. Add JitPass there.")
                }
                Button("Scan Folder…", action: actions.chooseFolder).disabled(model.scanning)
                Button("Rescan", action: actions.rescan).disabled(model.scanning || model.scan == nil)
                Button("Open in Terminal", action: actions.openInTerminal)
            }
            if !model.scanning, let s = model.scan?.summary, model.scanScope == nil {
                coverageBar(s)
            }
            HStack(spacing: 6) {
                if let line = summaryLine {
                    Text(line)
                    Text("·")
                }
                if !model.scanExcludes.isEmpty {
                    Text("excluding \(model.scanExcludes.count) folder" + (model.scanExcludes.count == 1 ? "" : "s"))
                    Button("edit", action: actions.openSettings).buttonStyle(.link)
                    Text("·")
                }
                if let scope = model.scanScope {
                    Text("in " + Format.home(scope)).lineLimit(1).truncationMode(.middle)
                    Button("whole Mac", action: actions.scanWholeMac).buttonStyle(.link).disabled(model.scanning)
                } else {
                    Text("whole Mac")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var summaryLine: String? {
        guard !model.scanning, let s = model.scan?.summary else {
            return nil
        }
        let line = Format.scanSummary(s, wholeMac: model.scanScope == nil)
        return line.isEmpty ? nil : line
    }

    /// The CLI's ten-cell bar and its "to 100%" line.
    private func coverageBar(_ s: ScanSummary) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(0 ..< 10, id: \.self) { cell in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(cell < s.percent / 10 ? Color(StatusMark.green) : Color(nsColor: .separatorColor))
                        .frame(width: 14, height: 6)
                }
            }
            if let line = s.toFullLine {
                Text(line).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private static let manualNote = "jit can't rewrite these safely. Rotate or move each value yourself."

    private func heading(_ title: String, _ count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text("\(count)").foregroundStyle(.secondary)
        }
    }

    private func protectSection(_ report: ScanReport) -> some View {
        let findings = report.migratable
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                heading("jit will protect these", findings.count)
                Spacer()
                if findings.count > 1 {
                    Button("Protect All") { actions.protectAll(report.protectAllCommands) }.controlSize(.small)
                }
            }
            if findings.isEmpty {
                Text("nothing").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(findings) { f in
                HStack(alignment: .top, spacing: 8) {
                    dot(f.severity)
                    VStack(alignment: .leading, spacing: 1) {
                        path(f.filePath)
                        detail(f)
                    }
                    Spacer()
                    fileButtons(f.filePath, line: f.line)
                    if let fix = f.fixCommand {
                        Button("Protect") { actions.protect(fix) }.buttonStyle(.link).font(.system(size: 12))
                    }
                }
            }
        }
    }

    private func manualSection(_ groups: [ScanFileGroup]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fileSection("Needs you", groups)
            if !groups.isEmpty {
                Text(Self.manualNote).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    /// One row per file: the path, then each flagged line under it.
    private func fileSection(_ title: String, _ groups: [ScanFileGroup]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(title, groups.reduce(0) { $0 + $1.findings.count })
            if groups.isEmpty {
                Text("nothing").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(groups) { g in
                HStack(alignment: .top, spacing: 8) {
                    dot(g.severity)
                    VStack(alignment: .leading, spacing: 1) {
                        path(g.filePath)
                        ForEach(g.findings) { detail($0, numbered: true) }
                    }
                    Spacer()
                    fileButtons(g.filePath, line: g.findings.compactMap(\.line).first)
                }
            }
        }
    }

    /// Open in the editor (at `line` when there is one) and Reveal in
    /// Finder, on every row: a reader wants to see the file whether jit
    /// can rewrite it or not.
    private func fileButtons(_ filePath: String, line: Int?) -> some View {
        HStack(spacing: 8) {
            Button("Open") { actions.open(filePath, line) }
            Button("Reveal") { actions.reveal(filePath) }
        }
        .buttonStyle(.link).font(.system(size: 12))
    }

    private func dot(_ severity: String) -> some View {
        Circle().fill(Severity.color(severity)).frame(width: 7, height: 7).padding(.top, 5)
    }

    /// Truncated at the start: the filename and its parent are what tell
    /// two paths apart, and the home prefix is the part a reader can guess.
    private func path(_ filePath: String) -> some View {
        Text(Format.home(filePath)).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.head)
    }

    private func detail(_ f: ScanFinding, numbered: Bool = false) -> some View {
        var parts = [Format.findingType(f.findingType), f.evidence]
        if numbered, let line = f.line {
            parts.insert("line \(line)", at: 0)
        }
        return Text(parts.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
    }
}

struct ScanActions {
    var rescan: () -> Void = {}
    var openSettings: () -> Void = {}
    var chooseFolder: () -> Void = {}
    var scanWholeMac: () -> Void = {}
    var openInTerminal: () -> Void = {}
    var protect: (String) -> Void = { _ in }
    var protectAll: ([String]) -> Void = { _ in }
    var open: (String, Int?) -> Void = { _, _ in }
    var reveal: (String) -> Void = { _ in }
    var grantFullDiskAccess: () -> Void = {}
}
