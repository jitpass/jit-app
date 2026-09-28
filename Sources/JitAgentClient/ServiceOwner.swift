// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Whose jit the background service runs. A restart from this app runs
/// the app's own jit: when the service runs another copy (a dev build
/// beside the installed app), that restart is refused (only the jit inside
/// the installed JitPass can reach a Secure Enclave key) or would re-point
/// the service at the wrong copy. So the app offers it only when the two
/// are the same file, or when it cannot tell (an older service).
public enum ServiceOwner {
    /// The service's executable when it is a different file from `own`;
    /// nil when they are the same, or either is unknown.
    public static func elsewhere(service: String?, own: String?) -> String? {
        guard let service, !service.isEmpty, let own, !own.isEmpty else {
            return nil
        }
        return resolved(service) == resolved(own) ? nil : service
    }

    /// Where to restart it from, in the reader's terms: the app bundle
    /// that holds that jit ("/Applications/JitPass.app"), else the binary.
    public static func place(_ executable: String, home: String = NSHomeDirectory()) -> String {
        let parts = executable.split(separator: "/", omittingEmptySubsequences: false)
        var place = executable
        if let app = parts.firstIndex(where: { $0.hasSuffix(".app") }) {
            place = parts[...app].joined(separator: "/")
        }
        return place.hasPrefix(home + "/") ? "~" + place.dropFirst(home.count) : place
    }

    static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

public extension DoctorBoard {
    /// The board with no Restart Service anywhere on a service card when the
    /// service runs another copy of jit (its button, its ⋯ menu, its rows'
    /// buttons and menus), and a line saying where to restart it.
    func restartingElsewhere(_ executable: String?, home: String = NSHomeDirectory()) -> DoctorBoard {
        guard let executable else {
            return self
        }
        var board = self
        board.cards = cards.map { card in
            guard card.items.contains(where: { $0.kind == "service" }) else {
                return card
            }
            var card = card
            var removed = false
            if let primary = card.primary, primary.restartsService {
                card.primary = nil
                removed = true
            }
            card.menu = card.menu.withoutRestart(&removed)
            card.rows = card.rows.map { row in
                var row = row
                let before = row.buttons.count
                row.buttons.removeAll(where: \.restartsService)
                removed = removed || row.buttons.count != before
                row.menu = row.menu.withoutRestart(&removed)
                return row
            }
            guard removed else {
                return card
            }
            let line = "The service runs the jit in \(ServiceOwner.place(executable, home: home)); restart it from there."
            card.reason = [card.reason, line].compactMap { $0 }.joined(separator: " ")
            return card
        }
        return board
    }
}

extension DoctorButton {
    /// Runs `jit service restart`, whatever it is titled.
    var restartsService: Bool {
        title == "Restart Service" || steps.contains { ($0.argv ?? []).contains(["service", "restart"]) }
    }
}

extension [DoctorMenuEntry] {
    /// The menu without its restart entries, and no separator left leading,
    /// trailing or doubled by one.
    func withoutRestart(_ removed: inout Bool) -> [DoctorMenuEntry] {
        var out: [DoctorMenuEntry] = []
        for entry in self {
            if case let .button(button) = entry, button.restartsService {
                removed = true
                continue
            }
            if case .separator = entry, out.isEmpty || out.last == .separator {
                continue
            }
            out.append(entry)
        }
        if out.last == .separator {
            out.removeLast()
        }
        return out
    }
}
