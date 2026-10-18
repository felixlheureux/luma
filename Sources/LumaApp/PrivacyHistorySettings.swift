import SwiftUI
import LumaCore

struct PrivacyView: View {
    @Environment(AppModel.self) private var model
    private let permissions: [(String, String, String, String)] = [
        ("Camera", "camera", "Choose which apps can use your camera.", "Privacy_Camera"),
        ("Microphone", "mic", "Choose which apps can access your microphone.", "Privacy_Microphone"),
        ("Screen recording", "rectangle.dashed.badge.record", "Review access to your display and system audio.", "Privacy_ScreenCapture"),
        ("Accessibility", "accessibility", "Review apps allowed to control your Mac.", "Privacy_Accessibility"),
        ("Full Disk Access", "internaldrive", "Manage access to protected application and user data.", "Privacy_AllFiles"),
        ("Files & folders", "folder", "Manage access to Documents, Desktop, and Downloads.", "Privacy_FilesAndFolders")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Surface {
                HStack(spacing: 19) {
                    SymbolTile(symbol: "hand.raised", tint: Palette.blue, size: 60)
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Privacy starts with leaving things alone.").font(.system(size: 19, weight: .semibold))
                        Text("Luma runs locally, without telemetry. Ordinary cleanup never removes your passwords, cookies, history, or browser sessions.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    }
                }
            }
            SectionHeading(title: "Application permissions", detail: "Managed by macOS")
            Surface(padding: 12) {
                VStack(spacing: 0) {
                    ForEach(permissions, id: \.0) { entry in
                        InsightRow(symbol: entry.1, tint: Palette.blue, title: entry.0, subtitle: entry.2, value: "Review") {
                            model.openSettings("com.apple.preference.security?\(entry.3)")
                        }
                        if entry.0 != permissions.last?.0 { Divider().padding(.leading, 56) }
                    }
                }.padding(.horizontal, 8)
            }
            Surface {
                VStack(alignment: .leading, spacing: 13) {
                    SectionHeading(title: "Browser data", detail: "Clear it where you can see the effects")
                    Text("For now, manage cookies, sessions, and website storage directly in your browser. These can hold sign-ins and offline documents, so Luma’s cache rules deliberately exclude them.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    Button("Open Safari privacy settings") {
                        if let url = URL(string: "x-safari-settings:privacy") { NSWorkspace.shared.open(url) }
                    }.buttonStyle(.glass)
                }
            }
        }
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var acknowledging: RecoveryNotice?
    private var ungroupedRecords: [CleanupRecord] {
        model.history.filter { record in !model.cleanupSession.sessions.contains { $0.id == record.planID } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let error = model.journalError {
                Surface {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Activity needs attention", systemImage: "exclamationmark.circle").font(.headline)
                        Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("Cleanup stays paused while Luma cannot verify its activity records. Existing files and records are left in place.").font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("Check again") { model.checkRecovery() }.buttonStyle(.glass).disabled(model.busy)
                    }
                }
            }
            if !model.recoveryNotices.isEmpty {
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeading(title: "Interrupted operations", detail: "Review before cleaning again")
                        ForEach(model.recoveryNotices) { notice in
                            VStack(alignment: .leading, spacing: 9) {
                                Text(notice.original.lastPathComponent).font(.system(size: 13, weight: .semibold))
                                Text(notice.original.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                                Text(notice.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                                HStack {
                                    Button("Open original folder") { NSWorkspace.shared.open(notice.original.deletingLastPathComponent()) }
                                    Button("Open Trash", action: openTrash)
                                    Spacer()
                                    Button("Mark reviewed") { acknowledging = notice }
                                }.buttonStyle(.glass).controlSize(.small).disabled(model.busy)
                            }
                        }
                        Button("Check recovery again") { model.checkRecovery() }.buttonStyle(.glass).disabled(model.busy)
                    }
                }
            }
            CleanupSessionHistory()
            if model.history.isEmpty && model.cleanupSession.sessions.isEmpty {
                EmptyState(symbol: "clock.arrow.circlepath", title: "A clean slate", message: "Files moved by Luma will appear here, with their original and Trash locations. No changes have been recorded.", actionTitle: "Open Trash in Finder", actionSymbol: "trash") {
                    openTrash()
                }
            } else {
                if !ungroupedRecords.isEmpty {
                    Surface(padding: 18) {
                        VStack(spacing: 0) {
                            ForEach(ungroupedRecords) { record in
                                HStack(spacing: 14) {
                                    SymbolTile(symbol: record.restored ? "arrow.uturn.backward" : "trash", tint: record.restored ? Palette.mint : Palette.accent, size: 36)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(record.original.lastPathComponent).font(.system(size: 12, weight: .semibold))
                                        Text(record.original.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                        Text("\(record.date.formatted()) · \(formatBytes(record.bytes)) · \(record.restored ? "Restored" : "Moved to Trash")").font(.system(size: 10)).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    if !record.restored {
                                        if record.identity != nil {
                                            Button("Restore") { model.restore(record) }.buttonStyle(.glass).controlSize(.small).disabled(model.busy || !model.recoveryNotices.isEmpty)
                                        } else {
                                            Button("Open Trash", action: openTrash).buttonStyle(.glass).controlSize(.small)
                                                .help("This older entry has no saved file identity; inspect and restore it in Finder.")
                                        }
                                    } else { Image(systemName: "checkmark.circle").foregroundStyle(Palette.mint) }
                                }.padding(.vertical, 13)
                                if record.id != ungroupedRecords.last?.id { Divider() }
                            }
                        }
                    }
                }
                Label("Restore verifies the item’s saved identity and preserves anything already at its original path. Older entries can be restored in Finder.", systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                openTrashButton
            }
        }.frame(maxWidth: .infinity)
        .alert("Mark this operation reviewed?", isPresented: Binding(get: { acknowledging != nil }, set: { if !$0 { acknowledging = nil } })) {
            Button("Cancel", role: .cancel) { acknowledging = nil }
            Button("Mark reviewed") { if let notice = acknowledging { model.acknowledgeRecovery(notice) }; acknowledging = nil }
        } message: { Text("First inspect the original folder and Trash in Finder. This dismisses the recovery notice; it does not move or restore any files.") }
    }
    private var openTrashButton: some View {
        Button("Open Trash in Finder", action: openTrash).buttonStyle(.glass)
    }
    private func openTrash() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("luma.appearance") private var appearance = "system"
    @AppStorage("luma.menuBar") private var menuBar = true
    var body: some View {
        TabView {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }.pickerStyle(.segmented)
                    Toggle("Show Luma in the menu bar", isOn: $menuBar)
                }
                Section("Saved analysis") {
                    Text("Storage metadata and duplicate hashes from folders you explicitly scan are stored locally. Every scan checks current paths and access. Cleanup always verifies current data.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Clear analysis cache") { model.clearAnalysisCache() }.disabled(model.busy)
                    if let status = model.analysisCacheStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
                }
                Section("Privacy & safety") {
                    LabeledContent("Telemetry", value: "None")
                    LabeledContent("Cleanup method", value: "macOS Trash")
                    LabeledContent("Background scanning", value: "Off — scans run on request")
                    Text("Luma does not request root access or install a background helper.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }
            VStack(alignment: .leading, spacing: 16) {
                Text("Ignored paths").font(.headline)
                Text("These items cannot be selected for cleanup. Remove an exclusion to include it in future reviews.").font(.system(size: 12)).foregroundStyle(.secondary)
                List {
                    ForEach(model.ignored.sorted(), id: \.self) { path in
                        HStack { Text(path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled); Spacer(); Button("Remove") { model.unignore(path) } }
                    }
                    if model.ignored.isEmpty { Text("No ignored paths yet.").foregroundStyle(.secondary) }
                }.clipShape(RoundedRectangle(cornerRadius: 12))
            }.padding(24).tabItem { Label("Ignore list", systemImage: "eye.slash") }
            VStack(spacing: 16) {
                LumaMark().frame(width: 70, height: 70)
                Text("Luma").font(.system(size: 28, weight: .semibold))
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") · Native. Transparent. Yours.").foregroundStyle(.secondary)
                Text("An open-source foundation for understanding and maintaining your Mac.\nLicensed under GPL-3.0-or-later.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("Early development build · macOS 26+").font(.caption).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).tabItem { Label("About", systemImage: "info.circle") }
        }.padding(12).frame(width: 550, height: 410)
    }
}
