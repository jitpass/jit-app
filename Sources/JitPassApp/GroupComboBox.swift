// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import SwiftUI

/// An editable field with a dropdown of existing choices: type a new
/// profile name or pick one. SwiftUI has no combo box on macOS, so this is
/// AppKit's `NSComboBox`, which is exactly that control.
struct GroupComboBox: NSViewRepresentable {
    @Binding var text: String
    var choices: [String]
    var placeholder = ""

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.completes = true
        box.isEditable = true
        box.placeholderString = placeholder
        box.delegate = context.coordinator
        box.target = context.coordinator
        box.action = #selector(Coordinator.changed(_:))
        box.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return box
    }

    func updateNSView(_ box: NSComboBox, context _: Context) {
        if box.objectValues as? [String] != choices {
            box.removeAllItems()
            box.addItems(withObjectValues: choices)
        }
        if box.stringValue != text {
            box.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            if let box = notification.object as? NSComboBox {
                text.wrappedValue = box.stringValue
            }
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox, box.indexOfSelectedItem >= 0,
                  let value = box.itemObjectValue(at: box.indexOfSelectedItem) as? String
            else {
                return
            }
            text.wrappedValue = value
        }

        @objc func changed(_ box: NSComboBox) {
            text.wrappedValue = box.stringValue
        }
    }
}
