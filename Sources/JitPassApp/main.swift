// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit

/// A menu bar only app: no Dock icon, no main window. LSUIElement in the
/// bundle's Info.plist does the same when packaged; the activation policy
/// covers `swift run` during development.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
