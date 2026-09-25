// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Everything the panel shows, as plain values the controller writes and the
/// view reads. No socket, no process, no AppKit: the view stays a pure
/// rendering of this, and the controller stays the only place that talks to
/// jit.
@MainActor
final class MenuModel: ObservableObject {
    @Published var state: SessionState = .notRunning
    @Published var grants: [GrantStatus] = []
    @Published var lastEvent: SessionEvent?
    /// Disclosed challenges the agent has parked with this app, oldest
    /// first; the consent sheet shows the first.
    @Published var consentRequests: [ConsentRequest] = []
    @Published var consentEnabled: Bool?
    @Published var ttlSeconds: Int64?
    @Published var cli: CLIStatus?
    @Published var scan: ScanReport?
    @Published var scanning = false
    @Published var scanError: String?
    /// The folder the last scan was limited to; nil means the whole Mac.
    @Published var scanScope: String?
    /// The scan now running is deep: the window shows the unlock state.
    @Published var scanDeep = false
    /// The last whole-Mac scan, whoever started it: what the Findings row shows. A folder scan never replaces it.
    @Published var macScan: ScanReport?
    @Published var macScanAt: Date?
    /// Who started the last whole-Mac scan; when the last deep one finished (its vault copies carry: landWholeMac);
    /// the ids this run has that the one before did not (nil: no run to compare with); when that run was.
    @Published var macScanKind: ScanRunKind?
    @Published var macDeepScanAt: Date?
    @Published var macScanNew: Set<String>?
    @Published var previousMacScanAt: Date?
    /// Set when jit changed something (a Protect ran) so the next chance rescans even before the schedule says so.
    @Published var scanStale = false
    @Published var scanChoosing = false // New Scan…: the window shows the chooser over its report, which stays
    @Published var scanSchedule: ScanSchedule = .init(
        rawValue: UserDefaults.standard.string(forKey: ScanSchedule.preferenceKey) ?? ""
    ) ?? .default
    @Published var scanExcludes: [String] = ScanExcludes.load()
    @Published var redactAfterScan = UserDefaults.standard.bool(forKey: Notifier.redactAfterScanKey)
    /// Agents whose caches are redacted after every scheduled scan, by tool; the global switch covers them all.
    @Published var redactAgents = Set(UserDefaults.standard.stringArray(forKey: Notifier.redactAgentsKey) ?? [])
    /// What each agent did through jit in the last week, by tool, from the audit; empty until read (AI Agents).
    @Published var agentActivity: [String: AgentActivity] = [:]
    /// Each wrapped tool's reads this week, by tool, from the audit; empty until read (Tools).
    @Published var toolActivity: [String: ToolActivity] = [:]
    @Published var audit: AuditReport?
    /// Decoy serves in the last 24 hours (nil until read), and the same by
    /// reading program, for the AI Agents digest's per-agent row.
    @Published var decoyReads24h: Int?
    /// The week's serve events, for the Decoys window; empty until read there.
    @Published var decoyEvents: [SessionEvent] = []
    @Published var decoysSheet: ToolsSheet?
    @Published var decoysOutcome: WindowOutcome?
    @Published var decoyReadsByProgram: [String: Int] = [:]
    @Published var notifyDecoys = Notifier.decoysEnabled
    @Published var notifyChanges = Notifier.changesEnabled
    /// What macOS allows, re-read when Settings opens and whenever the app
    /// comes forward (the answer changes in System Settings).
    @Published var notificationPermission: NotificationPermission = .unknown
    @Published var auditFilter = AuditFilter(since: "24h")
    @Published var auditLoading = false
    /// The New Grant sheet's inputs: the usual programs and every process,
    /// the terminal and editor apps to anchor under, and every profile jit
    /// can find on this Mac (ProfileDiscovery), plus folders the user added.
    @Published var grantProcesses: [RunningProcess] = []
    @Published var grantAllProcesses: [RunningProcess] = []
    @Published var grantSessionRoots: [RunningProcess] = []
    @Published var grantProfiles: [DiscoveredProfile] = []
    @Published var grantExtraRoots: [String] = []
    /// Profiles doctor reports as broken, with why; never offered.
    @Published var brokenProfiles: [String: String] = [:]
    /// Profiles naming a secret the vault does not hold, by manifest path,
    /// with why: the sheet checks every listed profile against the vault
    /// itself, since the service would refuse the whole grant for one
    /// missing secret and a Touch ID should not be spent finding that out.
    @Published var grantMissing: [String: String] = [:]
    /// The sheet over the Grants window, what it opens filled with (a
    /// re-approval), and the grant a re-approval replaces once it lands.
    @Published var grantSheet = false
    @Published var grantPrefill: GrantDraft?
    @Published var grantReplacing: String?
    @Published var grantBusy = false
    @Published var grantError: String?
    /// What just happened in the Grants window; clears on the next action.
    @Published var grantBanner: String?
    @Published var grantBannerFailed = false
    /// AI Jobs (jit design/agent-jobs.md): the approved jobs with their state,
    /// agents' proposals waiting for the human, whether Claude Desktop starts
    /// jit's MCP server, and what just happened in the window.
    @Published var jobs: [JobStatus] = []
    @Published var jobProposals: [JobProposal] = []
    @Published var claudeDesktopMCP: MCPStatus?
    @Published var claudeDesktopInstalled = false
    @Published var jobsBanner: String?
    @Published var jobsBannerFailed = false
    @Published var doctor: DoctorReport?
    @Published var doctorAt: Date?
    @Published var doctorRunning = false
    /// Why the last in-app doctor action failed, if it did.
    @Published var doctorMessage: String?
    /// The row (a finding's id, or "group:<kind>") whose action is running,
    /// from the moment it starts until the recheck after it lands. One at
    /// a time; every action button in the window is disabled meanwhile.
    @Published var doctorBusy: String?
    /// What is open over the Doctor window: its one question before a
    /// destructive fix, the profiles review, an action's output. All
    /// sheets on the window, so nothing about Doctor opens a window of
    /// its own any more.
    @Published var doctorSheet: DoctorSheet?
    /// An action finished while a check was already running: that check
    /// predates the action, so another follows it.
    var doctorRecheckPending = false
    /// The last check returned no report, so what is on screen (if
    /// anything) is from an earlier one.
    @Published var doctorFailed = false
    /// Whether macOS has granted the app Full Disk Access, checked when the scan window opens.
    @Published var fullDiskAccess = false
    /// The vault as `jit vault list` reports it: paths and headers, never a
    /// value. Reloaded after every vault operation.
    @Published var vaultListing: VaultListing?
    @Published var vaultHistory: VaultHistory?
    /// `jit vault orphans`, read when the maintenance sheet opens and after
    /// a prune; nil until then.
    @Published var vaultOrphans: VaultOrphans?
    /// The last `jit vault duplicates` comparison, while its sheet is open.
    @Published var vaultDuplicates: VaultDuplicates?
    /// When `vaultDuplicates` was read: a prune's dialog words itself from
    /// a comparison this recent, or runs one again first.
    var vaultDuplicatesAt: Date?
    /// The path (or action) a vault command is running for; one at a time,
    /// because most of them put a Touch ID prompt on screen.
    @Published var vaultBusy: String?
    /// Why the last vault operation failed, under the header until the next one.
    @Published var vaultMessage: String?
    /// A one-line confirmation ("copied, clears in 45s") that clears itself.
    @Published var vaultNotice: String?
    @Published var vaultSheet: VaultSheet?
    /// The one value on screen, while it is. The String here is the copy the
    /// app cannot wipe (see docs/design/vault-window.md §3a); it exists for
    /// the countdown and is dropped with the reveal. The bytes behind it are
    /// a `SecretBuffer` the controller owns and wipes.
    @Published var vaultReveal: VaultReveal?
    /// The tools jit knows on this Mac, as `jit wrap list --all` reports
    /// them; reloaded on every open of the Tools window and after a wrap.
    @Published var toolListing: ToolListing?
    @Published var toolsMessage: String?
    @Published var toolsNotice: String?
    /// The listing is being re-read (it runs each tool's export command,
    /// so it takes a moment); the header shows it.
    @Published var toolsRefreshing = false
    @Published var toolsSelected: String?
    /// The tool a wrap command is running for; one at a time, since most
    /// of them put a Touch ID prompt on screen.
    @Published var toolsBusy: String?
    @Published var toolsSheet: ToolsSheet?
    /// The AI Agents window's sheet; the same kinds, its own slot, so two
    /// windows never fight over one.
    @Published var agentsSheet: ToolsSheet?
    /// What the AI Agents window's last action did: its banner, with
    /// jit's own words one click away. The window has a banner region, so
    /// a success is said there and never in a modal over it.
    @Published var agentsOutcome: WindowOutcome?
    /// The Findings window's banner: what the last Protect, Clean Caches
    /// or Undo did. The next action clears it; a Protect's rescan keeps it.
    @Published var findingsOutcome: WindowOutcome?
    /// The scan window's sheet: what an in-app Protect printed.
    @Published var scanSheet: ToolsSheet?
    /// The file whose flagged lines the scan window is showing. A row
    /// carries one fact; the list of lines is a sheet on top of it.
    @Published var scanLines: ScanFileGroup?
    /// The setting being applied, so the spinner sits on that row.
    @Published var settingsApplying: SettingsOutcome.Row?
    /// What the last change did: the banner, or a row under the control.
    @Published var settingsOutcome: SettingsOutcome?
    @Published var launchAtLogin = false
    @Published var terminalApp = ""
    /// The bundle identifier of the editor scan rows open files with; "" is the system default.
    @Published var editorApp = ""
    @Published var editors: [Editor.Choice] = []
    /// A newer JitPass, as "1.6.3", once the daily check has found one.
    @Published var updateAvailable: String?
    @Published var updateChecking = false
    @Published var updateChecked: Date?
    @Published var updateMessage: String?
    @Published var checkForUpdates = true
    /// Whether a terminal's `jit` is this app's; nil for a build with no
    /// bundled jit, where the question has no answer.
    @Published var cliTool: CommandLineTool.State?

    /// "I'll set up in Terminal": the one place a saved flag outranks what
    /// is true, because only the user can know it.
    static let terminalSetupKey = "setupInTerminal"
    @Published var terminalSetup = UserDefaults.standard.bool(forKey: MenuModel.terminalSetupKey)

    var setup: VaultSetup {
        VaultSetup(status: cli)
    }

    /// The panel and the mark show "not set up" for a new user only.
    /// `-previewSetup YES` on the command line shows the state on a Mac
    /// that has a vault, to judge it by eye. It changes only what is drawn:
    /// every action still reads the real `setup`.
    var needsSetup: Bool {
        (setup == .needsSetup && !terminalSetup) || UserDefaults.standard.bool(forKey: "previewSetup")
    }

    /// Secrets on disk with no key that opens them: the panel offers
    /// Restore, in the same one-button shape as setup.
    var needsRestore: Bool {
        setup == .needsRestore
    }

    /// Either state replaces the session panel and the filled mark.
    var showsSetup: Bool {
        needsSetup || needsRestore
    }

    var grantsValue: String {
        switch grants.count {
        case 0: "none"
        case 1: "1 active"
        default: "\(grants.count) active"
        }
    }

    var vaultValue: String? {
        if let listing = vaultListing {
            let linked = listing.linkedCount
            return "\(listing.secrets.count) secrets" + (linked > 0 ? " · \(linked) linked" : "")
        }
        return cli?.vault.map { "\($0.secretsStored) secrets" }
    }

    // The Decoys row: the files, and today's reads when there were any,
    // since that is the event the files exist for. "Mount" is jit's word
    // for the mechanism and stays in the CLI.

    var consentValue: String? {
        consentEnabled.map { $0 ? "On" : "Off" }
    }

    /// `jit status`'s verdict on the zsh history guard; nil before the
    /// first status read.
    var guardInstalled: Bool? {
        cli?.guardStatus?.installed
    }

    /// Installed tools whose key sits in the open: a plaintext file, the
    /// tool's own login, or a shell export. What "to protect" counts.
    var toolsWithKeyInTheOpen: [ToolRecord] {
        (toolListing?.installed ?? []).filter { $0.keyState(scan: macScan).needsAction }
    }

    // The Tools row's dot: red for a broken shim, amber for an expired
    // session or a key in the open, green when wrapped tools are healthy.

    // The last verdict stays on screen while a recheck runs; "checking…"
    // appears only before the first result exists.

    var vaultSummary: String {
        guard let listing = vaultListing else {
            return vaultValue ?? "not read yet"
        }
        var parts = ["\(listing.secrets.count) secret" + (listing.secrets.count == 1 ? "" : "s")]
        if listing.linkedCount > 0 {
            parts.append("\(listing.linkedCount) linked")
        }
        if !listing.backups.isEmpty {
            parts.append("\(listing.backups.count) backups")
        }
        return parts.joined(separator: " · ")
    }

    // The Findings row, named for the window it opens (a list of what needs you, not a report of what is
    // protected): the count, and the day the schedule last ran. Never a folder's number, never the ledger.
}

/// The sheet the Vault window has open, if any.
enum VaultSheet: Identifiable, Equatable {
    /// Add a secret; with `replacing`, the path is fixed and the current
    /// value goes to history.
    case add(group: String?, replacing: String?)
    case link(group: String?, replacing: String?)
    case history(path: String)
    /// Orphans, backups, export, import, rekey: the commands that act on
    /// the vault as a whole.
    case maintenance
    /// The orphaned secrets, chosen from and deleted by project.
    case orphans
    /// The duplicates comparison, after its Touch IDs.
    case duplicates

    var id: String {
        switch self {
        case let .add(group, replacing): "add:\(group ?? ""):\(replacing ?? "")"
        case let .link(group, replacing): "link:\(group ?? ""):\(replacing ?? "")"
        case let .history(path): "history:\(path)"
        case .maintenance: "maintenance"
        case .orphans: "orphans"
        case .duplicates: "duplicates"
        }
    }
}

/// A value on screen: which row, the text, and seconds left.
struct VaultReveal: Equatable {
    var path: String
    var text: String
    var secondsLeft: Int
}
