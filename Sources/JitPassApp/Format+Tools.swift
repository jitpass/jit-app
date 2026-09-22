// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Every sentence the Tools window says.
extension Format {
    static func toolsHeadline(_ board: ToolsBoard) -> String {
        guard board.hasWraps else {
            return "Nothing runs through jit yet"
        }
        var text = count(board.rows.count, "tool") + (board.rows.count == 1 ? " runs" : " run") + " through jit"
        if board.needingYou > 0 {
            text += " · \(board.needingYou) need" + (board.needingYou == 1 ? "s" : "") + " you"
        }
        return text
    }

    static func toolsSubline(_ board: ToolsBoard) -> String {
        var text = "Each tool reads its key from the vault, for its own process only."
        if board.hasWraps {
            text += board.activity.isEmpty
                ? " Last use and other readers come from the audit."
                : " Last use and other readers are the audit's, this week."
        }
        return text
    }

    static func toolsFooter(_ board: ToolsBoard) -> String {
        var parts = [count(board.installed, "tool") + " installed", "\(board.rows.count) through jit"]
        if board.hasWraps, !board.activity.isEmpty {
            let reads = board.activity.values.reduce(0) { $0 + $1.reads }
            parts.append(count(reads, "read") + " this week")
            let others = board.rows.filter { !(board.activity[$0.id]?.others(than: $0.id).isEmpty ?? true) }.count
            parts.append(others == 0 ? "0 by another program" : count(others, "key") + " read by another program")
        }
        return parts.joined(separator: " · ")
    }

    /// The empty state's sentence: what Findings offers, and that a tool
    /// appears here once it runs through jit.
    static func toolsEmptyMessage(_ board: ToolsBoard, scan: ScanReport?) -> String {
        var parts: [String] = []
        for tool in board.toWrap {
            let line = toolKeyLine(tool, scan: scan)
            parts.append(line.wrapsHere
                ? line.text + "; Wrap hands it to " + tool.tool + " only, after your Touch ID"
                : line.text + "; Findings offers to protect it")
        }
        let quiet = (board.listing?.others ?? []).filter { !$0.wrapped && !$0.isProtected && !board.toWrap.contains($0) }.map(\.tool)
        if !quiet.isEmpty {
            parts.append(names(quiet) + (quiet.count == 1 ? " has" : " have") + " nothing to protect")
        }
        parts.append("A tool appears here once it reads its key through jit")
        return parts.joined(separator: ". ") + "."
    }

    /// The header's line for a tool whose key is still in the open: where
    /// it is, and the verb — Findings' Protect, or, for a token in the
    /// tool's own keychain (which the scan cannot see), Wrap from here.
    struct ToolKeyLine {
        var text: String
        var verb: String
        var wrapsHere: Bool
    }

    static func toolKeyLine(_ tool: ToolRecord, scan: ScanReport?) -> ToolKeyLine {
        switch tool.keyState(scan: scan) {
        case let .found(source) where source.hasPrefix("~") || source.hasPrefix("/"):
            ToolKeyLine(text: tool.tool + " keeps a key in " + home(source), verb: "protect it in Findings", wrapsHere: false)
        // The keychain keeps the token from other users, not from other
        // programs: anything running as you can print it with the tool's
        // own command. That command is the reason, so the line names it
        // (windows.md: "when the flag is the decision").
        case let .found(command):
            ToolKeyLine(
                text: tool.tool + " keeps its token in its keychain, but any program can read it with " + command,
                verb: "wrap it", wrapsHere: true
            )
        default:
            ToolKeyLine(text: tool.tool + " has a key jit could take", verb: "protect it in Findings", wrapsHere: false)
        }
    }

    static func toolTierWord(_ tier: ToolCard.Tier) -> String {
        switch tier {
        case .fixNow: "Fix now"
        case .silent: "Silent"
        case .working: "Working"
        }
    }

    static func toolTierTitle(_ tier: ToolCard.Tier, count n: Int) -> String {
        switch tier {
        case .fixNow: count(n, "tool") + (n == 1 ? " needs" : " need") + " you"
        case .silent: count(n, "tool") + " wrapped, never used"
        case .working: count(n, "tool") + ", healthy"
        }
    }

    static func toolTierNote(_ tier: ToolCard.Tier) -> String {
        switch tier {
        case .fixNow: "A broken shim, or a captured login whose session has run out: the next call fails until it is fixed. "
            + "Log In… opens your terminal."
        case .silent: "Wrapped, and the key has never been read through jit: another copy on PATH may be answering first."
        case .working: "The shim is on PATH, the key resolves, and only the tool itself has read it."
        }
    }

    /// The row for a tool jit recognises on this Mac but does not run
    /// yet: what its credential is, and where its key sits.
    static func knownToolFact(_ tool: ToolRecord, scan: ScanReport?) -> String {
        var parts = [tool.shortDoc.isEmpty ? tool.kind : tool.shortDoc]
        switch tool.keyState(scan: scan) {
        case let .found(source) where source.hasPrefix("~") || source.hasPrefix("/"):
            parts.append("key in " + home(source))
        case let .found(command):
            parts.append("in its keychain, readable by any program with " + command)
            parts.append("Wrap hands it to " + tool.tool + " only, after your Touch ID, and logs each read")
        case .none:
            parts.append(tool.isNative ? "nothing found" : "no key found")
        case .unknown:
            // A native tool's key is a file only a scan finds; the report
            // is not kept across a relaunch, so until one runs the row
            // says what would answer it.
            parts.append(tool.isNative ? "not scanned yet · a scan looks for its credentials file" : "not checked yet")
        case .protected:
            parts.append("protected")
        }
        return parts.joined(separator: " · ")
    }

    static let knownToolsNote = "Installed here and in jit's catalogue. "
        + "A tool with a key jit can take shows the verb; one with nothing found has nothing to do."
}
