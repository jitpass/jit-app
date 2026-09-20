// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// The dialogs a doctor action needs before the app can run its command:
/// a hidden value, a passphrase typed twice, and the plan behind a
/// confirmation. All modal, all AppKit, so a secret typed here goes
/// straight to the CLI's stdin and never through a SwiftUI binding.
///
/// Output has no dialog any more. A command's own words land in the row
/// that asked for them, or in a sheet on the Doctor window when the
/// output was the whole request; the monospaced pane in a window of its
/// own is gone.
enum DoctorDialogs {
    /// One hidden field. Nil when cancelled or left empty.
    @MainActor
    static func askSecret(_ prompt: String, title: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = prompt
        alert.addButton(withTitle: title)
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runFrontmost() == .alertFirstButtonReturn, !field.stringValue.isEmpty else {
            return nil
        }
        return field.stringValue
    }

    /// A passphrase and its confirmation; asks again until they match. The
    /// fields are labelled and the text says to fill both: with a bare
    /// placeholder under the first field, users typed it once and met an
    /// "entries differ" they had no way to expect. A second field left
    /// empty keeps the first entry; two that differ clear both, because
    /// either could hold the typo. A "Show passphrase" box reveals both,
    /// because a passphrase that has to be remembered is one the user
    /// wants to read back before committing to it.
    @MainActor
    static func askPassphrase(_ prompt: String, title: String) -> String? {
        var note = prompt + " Type it in both fields."
        var kept = ""
        while true {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = note + " jit never stores it; losing it makes the file unreadable."
            alert.addButton(withTitle: title)
            alert.addButton(withTitle: "Cancel")
            let fields = PassphraseFields(passphrase: kept)
            alert.accessoryView = fields
            alert.window.initialFirstResponder = kept.isEmpty ? fields.passphraseField : fields.confirmField
            guard alert.runFrontmost() == .alertFirstButtonReturn else {
                return nil
            }
            let (first, second) = fields.values
            if first.isEmpty {
                note = "The passphrase can't be empty."
                kept = ""
            } else if second.isEmpty {
                note = "Type the same passphrase again in Confirm."
                kept = first
            } else if first != second {
                note = "The two entries differ. Type the passphrase in both fields again."
                kept = ""
            } else {
                return first
            }
        }
    }

    /// A confirmation worded from a dry run, with jit's plan under the
    /// text, monospaced and scrolling when it is long, and a link to the
    /// file it is about. The buttons follow `confirmDeletion`: a `breaks`
    /// one (an undo that writes plaintext back) is red and not the default,
    /// so Return never presses it and Escape cancels.
    @MainActor
    static func confirmPlan(_ confirmation: DeleteConfirmation, plan: String?, reveal: RevealLink?) -> Bool {
        let alert = NSAlert()
        alert.messageText = confirmation.title
        alert.informativeText = confirmation.message
        alert.alertStyle = confirmation.button == nil || !confirmation.destructive ? .informational : .warning
        alert.accessoryView = planAccessory(plan, reveal: reveal)
        guard let button = confirmation.button else {
            alert.addButton(withTitle: "OK")
            alert.runFrontmost()
            return false
        }
        let run = alert.addButton(withTitle: button)
        let cancel = alert.addButton(withTitle: "Cancel")
        if confirmation.breaks {
            run.hasDestructiveAction = true
            run.keyEquivalent = ""
            cancel.keyEquivalent = "\u{1b}"
        }
        return alert.runFrontmost() == .alertFirstButtonReturn
    }

    /// The plan in a scroll view, the reveal link under it.
    @MainActor
    private static func planAccessory(_ plan: String?, reveal: RevealLink?) -> NSView? {
        let link = reveal.map(RevealButton.init)
        guard let plan, !plan.isEmpty else {
            return link
        }
        let width: CGFloat = 480
        let lines = CGFloat(plan.components(separatedBy: "\n").count)
        let height = min(240, lines * 15 + 12)
        let below = link.map { $0.frame.height + 6 } ?? 0
        let box = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height + below))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: below, width: width, height: height))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let view = NSTextView(frame: scroll.bounds)
        view.isEditable = false
        view.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        view.string = plan
        view.autoresizingMask = [.width]
        scroll.documentView = view
        box.addSubview(scroll)
        if let link {
            link.setFrameOrigin(NSPoint(x: 0, y: 0))
            box.addSubview(link)
        }
        return box
    }
}

/// A file a dialog is about, offered under its text as a link ("Show
/// Profile File", "Show Config"): it selects the file in Finder and leaves
/// the dialog up, since an accessory button never ends an alert's modal
/// run. Disabled when the file is gone. Never opens the file: a click must
/// not launch an editor on one that may hold plaintext.
struct RevealLink {
    var title: String
    var path: String
}

@MainActor
final class RevealButton: NSButton {
    private let url: URL

    init(_ link: RevealLink) {
        url = URL(fileURLWithPath: link.path)
        super.init(frame: .zero)
        let exists = FileManager.default.fileExists(atPath: link.path)
        isBordered = false
        attributedTitle = NSAttributedString(string: link.title, attributes: [
            .foregroundColor: exists ? NSColor.linkColor : NSColor.disabledControlTextColor,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        ])
        isEnabled = exists
        toolTip = exists ? Format.home(link.path) : "Not there any more: \(Format.home(link.path))"
        target = self
        action = #selector(reveal)
        sizeToFit()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    @objc private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Two labelled passphrase fields and a checkbox that reveals them.
/// NSSecureTextField cannot switch to plain text in place, so the box swaps
/// each secure field for a plain one carrying the same value, and back.
private final class PassphraseFields: NSView {
    private static let labels = ["Passphrase", "Confirm"]
    private static let placeholders = ["", "The same passphrase again"]
    private static let labelWidth: CGFloat = 76
    private static let fieldWidth: CGFloat = 236

    private let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
    private var rows: [NSStackView] = []
    private var entries: [NSTextField] = []
    private let reveal = NSButton(checkboxWithTitle: "Show passphrase", target: nil, action: nil)

    var passphraseField: NSTextField {
        entries[0]
    }

    var confirmField: NSTextField {
        entries[1]
    }

    var values: (String, String) {
        (entries[0].stringValue, entries[1].stringValue)
    }

    init(passphrase: String) {
        super.init(frame: stack.frame)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        addSubview(stack)
        entries = Self.placeholders.map { Self.field(placeholder: $0, secure: true) }
        entries[0].stringValue = passphrase
        for (label, entry) in zip(Self.labels, entries) {
            let name = NSTextField(labelWithString: label)
            name.alignment = .right
            name.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true
            let row = NSStackView(views: [name, entry])
            row.orientation = .horizontal
            row.spacing = 8
            rows.append(row)
            stack.addArrangedSubview(row)
        }
        reveal.target = self
        reveal.action = #selector(toggle)
        // Under the fields, not under the labels.
        let revealRow = NSStackView(views: [reveal])
        revealRow.edgeInsets = NSEdgeInsets(top: 0, left: Self.labelWidth + 8, bottom: 0, right: 0)
        stack.addArrangedSubview(revealRow)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    @objc private func toggle() {
        let secure = reveal.state != .on
        let focused = entries.firstIndex { $0.currentEditor() != nil } ?? 0
        let swapped = entries.map { old -> NSTextField in
            let new = Self.field(placeholder: old.placeholderString ?? "", secure: secure)
            new.stringValue = old.stringValue
            return new
        }
        for (row, (old, new)) in zip(rows, zip(entries, swapped)) {
            row.removeArrangedSubview(old)
            old.removeFromSuperview()
            row.addArrangedSubview(new)
        }
        entries = swapped
        window?.makeFirstResponder(entries[focused])
    }

    private static func field(placeholder: String, secure: Bool) -> NSTextField {
        let frame = NSRect(x: 0, y: 0, width: fieldWidth, height: 24)
        let field = secure ? NSSecureTextField(frame: frame) : NSTextField(frame: frame)
        field.placeholderString = placeholder
        field.widthAnchor.constraint(equalToConstant: fieldWidth).isActive = true
        return field
    }
}
