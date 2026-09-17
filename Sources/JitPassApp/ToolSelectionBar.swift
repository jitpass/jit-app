// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The bar under the Tools list: the selected tool's facts, one line each
/// in the words of docs/design/tools-window.md §3 and §5, with the command
/// that changes each fact next to it.
struct ToolSelectionBar: View {
    @ObservedObject var model: MenuModel
    let actions: ToolsActions
    let tool: ToolRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let tool {
                HStack(spacing: 8) {
                    Text(tool.tool).fontWeight(.semibold)
                    Spacer()
                    if model.toolsBusy == tool.tool {
                        Text("Touch ID…").foregroundStyle(.secondary)
                    }
                    if tool.wrapped, tool.kind != "native" {
                        Button("Unwrap…") { actions.unwrap(tool.tool) }
                    }
                    if let hint = tool.verifyHint, tool.isProtected {
                        Button(hint.contains("<") ? "Verify in Terminal" : "Verify") { actions.verify(tool.tool) }
                    }
                }
                .disabled(model.toolsBusy != nil)
                if let message = model.toolsMessage {
                    factLine(message, tint: Color(StatusMark.red))
                }
                facts(tool)
            } else {
                Text("Select a tool.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One line per fact, in the words of docs/design/tools-window.md §3,
    /// each with the command that changes it.
    @ViewBuilder private func facts(_ tool: ToolRecord) -> some View {
        if let label = tool.agentLabel {
            agentFacts(tool, label: label)
        } else {
            switch tool.kind {
            case "capture": captureFacts(tool)
            case "native": nativeFacts(tool)
            case "grant": grantFacts(tool)
            default: shimFacts(tool)
            }
        }
        if let detail = tool.shimDetail {
            factLine(detail, tint: Color(StatusMark.red))
        }
    }

    @ViewBuilder private func agentFacts(_ tool: ToolRecord, label: String) -> some View {
        shimFacts(tool)
        HStack(spacing: 8) {
            factLine(cacheLine(label), tint: nil)
            Spacer()
            if model.macScan == nil {
                Button("Scan Now", action: actions.scanNow).controlSize(.small).disabled(model.scanning)
            } else if model.macScan?.agentCopies(in: label) ?? 0 > 0 {
                Button("Clean Caches…", action: actions.cleanCaches).controlSize(.small).disabled(model.toolsBusy != nil)
            }
        }
        HStack(spacing: 8) {
            factLine(consentLine, tint: nil)
            Spacer()
            if model.consentEnabled == false {
                Button("Settings…", action: actions.openSettings).controlSize(.small)
            }
        }
    }

    private func cacheLine(_ label: String) -> String {
        guard let scan = model.macScan else {
            return "Caches: no whole-Mac scan yet, so jit has not looked for copies of your secrets in \(label)'s cache."
        }
        let copies = scan.agentCopies(in: label)
        if copies == 0 {
            return "Caches: the last scan found no copy of your secrets in \(label)'s cache."
        }
        return "Caches: the last scan found \(copies) cop\(copies == 1 ? "y" : "ies") of your secrets in \(label)'s cache."
    }

    private var consentLine: String {
        switch model.consentEnabled {
        case true: "Reach: when this agent runs a tool that needs a machine credential, JitPass asks you first."
        case false: "Reach: consent is off, so a tool this agent runs gets machine credentials without asking you."
        default: "Reach: the service is not running, so nothing is being asked."
        }
    }

    @ViewBuilder private func shimFacts(_ tool: ToolRecord) -> some View {
        if tool.wrapped {
            let vars = tool.injects.map { $0.name + ($0.stored ? "" : " (nothing stored)") }.joined(separator: ", ")
            HStack(spacing: 8) {
                factLine("injects " + (vars.isEmpty ? "nothing" : vars) + " into \(tool.tool) only", tint: nil)
                Spacer()
                if !tool.injects.isEmpty {
                    Button("Open Vault", action: actions.openVault).controlSize(.small)
                }
            }
        } else {
            factLine(notWrappedLine(tool), tint: nil)
        }
    }

    /// Whether there is a key to move, and what Wrap does with it.
    private func notWrappedLine(_ tool: ToolRecord) -> String {
        let target = tool.injects.first?.vaultPath ?? "the vault"
        if let key = tool.shellConfigKey(scan: model.macScan) {
            return "key exported in \(Format.home(key.file)) · Wrap moves it to \(key.vaultPath) and hooks the file"
        }
        switch tool.keyState(scan: model.macScan) {
        case let .found(source) where source.hasPrefix("~") || source.hasPrefix("/"):
            return "key in \(Format.home(source)) · Wrap moves it to \(target) and blanks the file (backed up)"
        case .found:
            return "token in \(tool.tool)'s keychain, encrypted · Wrap copies it to \(target) for \(tool.tool)'s process only"
        case .none:
            return "no key found · Wrap installs the shim if you paste one"
        case .unknown:
            return "not checked · scan the Mac, or open Wrap to see where jit looks"
        case .protected:
            return "protected"
        }
    }

    @ViewBuilder private func captureFacts(_ tool: ToolRecord) -> some View {
        if tool.wrapped {
            ForEach(model.cli?.sessions(mintedBy: tool.tool) ?? []) { session in
                HStack(spacing: 8) {
                    Text(session.profile).font(.system(size: 12, design: .monospaced))
                        .help("Every `\(tool.tool) get` logs in with your MFA; the temporary AWS credentials go into the vault "
                            + "and aws reads them through credential_process. Nothing lands in ~/.aws/credentials.")
                    Text(sessionText(session)).font(.system(size: 12))
                        .foregroundStyle(session.live ? Color.secondary : Color(StatusMark.amber))
                    Spacer()
                    if let mint = session.mint, !session.live {
                        Button("Renew in Terminal") { actions.mintInTerminal(mint) }.controlSize(.small)
                            .help("Runs `\(mint)`: a fresh login with your MFA, caught into the vault")
                    }
                }
            }
        } else {
            factLine("not wrapped · Wrap routes each `\(tool.tool) get` login into the vault instead of ~/.aws/credentials", tint: nil)
        }
    }

    /// A session with no stamp was captured before jit recorded expiry;
    /// jit reports it live because it cannot say otherwise, and the row
    /// should not dress that up.
    private func sessionText(_ session: CLISession) -> String {
        guard let expires = session.expires else {
            return session.live ? "no expiry recorded · the next login stores one" : "expired"
        }
        let text = Format.expiry(expires)
        if let mint = session.mint, !session.live {
            return text + " · `\(mint)` renews it"
        }
        return text
    }

    @ViewBuilder private func grantFacts(_ tool: ToolRecord) -> some View {
        let mount = tool.with ?? "its"
        if tool.wrapped {
            factLine("every run is granted the \(mount) mount under its own Touch ID; the file serves decoys to everything else", tint: nil)
        } else if tool.mountMigrated {
            factLine("the \(mount) file is in the vault · Wrap makes `\(tool.tool)` take the grant by itself", tint: nil)
        } else {
            switch tool.keyState(scan: model.macScan) {
            case let .found(path):
                factLine("credential file at \(Format.home(path)) · Protect moves it to the vault, then Wrap takes the grant", tint: nil)
            default:
                factLine("nothing found · no \(mount) credential file on this Mac", tint: nil)
            }
        }
    }

    @ViewBuilder private func nativeFacts(_ tool: ToolRecord) -> some View {
        if tool.isProtected {
            let count = tool.vaultSecrets
            factLine(
                "\(count) secret\(count == 1 ? "" : "s") in the vault, served through \(tool.tool)'s own credential mechanism",
                tint: nil
            )
        } else {
            factLine("nothing found · Protect runs the migration that hooks \(tool.tool)'s own credential mechanism", tint: nil)
        }
    }

    private func factLine(_ text: String, tint: Color?) -> some View {
        Text(text).font(.subheadline).foregroundStyle(tint ?? Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
