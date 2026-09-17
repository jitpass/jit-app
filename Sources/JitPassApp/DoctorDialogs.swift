// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit

/// The dialogs a doctor action needs before the app can run its command:
/// a hidden value, a passphrase typed twice, and a window for output the
/// user asked to see. All modal, all AppKit, so a secret typed here goes
/// straight to the CLI's stdin and never through a SwiftUI binding.
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
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else {
            return nil
        }
        return field.stringValue
    }

    /// A passphrase and its confirmation; asks again until they match. A
    /// "Show passphrase" box reveals both, because a passphrase that has
    /// to be remembered is one the user wants to read back before
    /// committing to it.
    @MainActor
    static func askPassphrase(_ prompt: String, title: String) -> String? {
        var note = prompt
        while true {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = note + " jit never stores it; losing it makes the file unreadable."
            alert.addButton(withTitle: title)
            alert.addButton(withTitle: "Cancel")
            let fields = PassphraseFields()
            alert.accessoryView = fields
            alert.window.initialFirstResponder = fields.firstField
            guard alert.runModal() == .alertFirstButtonReturn else {
                return nil
            }
            let (first, second) = fields.values
            if first.isEmpty {
                note = "The passphrase can't be empty."
            } else if first != second {
                note = "The two entries differ. Type the passphrase twice."
            } else {
                return first
            }
        }
    }

    /// The command's output, monospaced, in a sheet the user closes.
    @MainActor
    static func showOutput(_ text: String, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "Close")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let view = NSTextView(frame: scroll.bounds)
        view.isEditable = false
        view.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        view.string = text.isEmpty ? "(no output)" : text
        view.autoresizingMask = [.width]
        scroll.documentView = view
        alert.accessoryView = scroll
        alert.runModal()
    }
}

/// Two passphrase fields and a checkbox that reveals them. NSSecureTextField
/// cannot switch to plain text in place, so the box swaps each secure
/// field for a plain one carrying the same value, and back.
private final class PassphraseFields: NSView {
    private let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
    private var entries: [NSTextField] = []
    private let reveal = NSButton(checkboxWithTitle: "Show passphrase", target: nil, action: nil)

    var firstField: NSTextField {
        entries[0]
    }

    var values: (String, String) {
        (entries[0].stringValue, entries[1].stringValue)
    }

    init() {
        super.init(frame: stack.frame)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        addSubview(stack)
        entries = ["Passphrase", "Again"].map { Self.field(placeholder: $0, secure: true) }
        entries.forEach(stack.addArrangedSubview)
        reveal.target = self
        reveal.action = #selector(toggle)
        stack.addArrangedSubview(reveal)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    @objc private func toggle() {
        let secure = reveal.state != .on
        let swapped = entries.map { old -> NSTextField in
            let new = Self.field(placeholder: old.placeholderString ?? "", secure: secure)
            new.stringValue = old.stringValue
            return new
        }
        for (old, new) in zip(entries, swapped) {
            let index = stack.arrangedSubviews.firstIndex(of: old) ?? 0
            stack.removeArrangedSubview(old)
            old.removeFromSuperview()
            stack.insertArrangedSubview(new, at: index)
        }
        entries = swapped
        window?.makeFirstResponder(entries[0])
    }

    private static func field(placeholder: String, secure: Bool) -> NSTextField {
        let frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        let field = secure ? NSSecureTextField(frame: frame) : NSTextField(frame: frame)
        field.placeholderString = placeholder
        field.widthAnchor.constraint(equalToConstant: 320).isActive = true
        return field
    }
}
