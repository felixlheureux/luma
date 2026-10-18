import SwiftUI
import LumaCore

struct DeviceBackupsView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var displayLimit = 20
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: "Local iPhone & iPad backups")
                            Text("Keep a way back.").font(.system(size: 25, weight: .semibold))
                            Text("A backup can be your only copy. Age and encryption never make it disposable.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(model.deviceBackups == nil ? "Inspect local backups" : "Inspect again") { model.runScan(.backups) }
                            .buttonStyle(.glass).disabled(!model.canStartScan)
                    }
                    Label("Inspection only. Manage changes in Finder.", systemImage: "lock.shield").font(.system(size: 12, weight: .medium))
                    DisclosureGroup("What this inspection covers") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Luma reads backup summaries and sizes in the standard Mac backup folder. Payload files and manifest databases are not read. iCloud and relocated backups are not included.")
                            Text("Backup/restore idleness and restorability are unknown. No backup or internal file can be selected for removal here.")
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                    }.font(.system(size: 11))
                }
            }
            if let inventory = model.deviceBackups {
                Surface(padding: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("\(inventory.backups.count) observed backup folders").font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Text("Known logical size: \(inventory.knownBytes.map(formatBytes) ?? "Unknown")")
                        }
                        if inventory.backups.contains(where: { $0.bytes == nil }) { Text("Some sizes are unknown and absent from this total.").foregroundStyle(.secondary) }
                        Text(inventory.activity.rawValue).fontWeight(.medium)
                        Text("Finished metadata does not verify restorability. Known sizes can include folders with unrecognized metadata.").foregroundStyle(.secondary)
                        if inventory.locationState == .found || inventory.locationState == .empty {
                            Button("Reveal backup location in Finder") { NSWorkspace.shared.activateFileViewerSelecting([inventory.root]) }.buttonStyle(.glass)
                        }
                    }.font(.system(size: 11))
                }
                if inventory.backups.isEmpty {
                    ContentUnavailableView(emptyTitle(inventory.locationState), systemImage: "externaldrive",
                        description: Text(emptyDescription(inventory.locationState)))
                }
                ForEach(Array(inventory.backups.prefix(displayLimit))) { backup in
                    Surface(padding: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SymbolTile(symbol: "externaldrive", size: 38)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: backup.title).font(.system(size: 16, weight: .semibold))
                                    Text("Backup \(backup.ordinal)").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                SafetyBadge(level: backup.safety)
                            }
                            HStack {
                                Text(backup.bytes.map { "\(formatBytes($0)) logical size" } ?? "Size unknown")
                                Spacer()
                                Text(backup.state.rawValue).foregroundStyle(.secondary)
                            }.font(.system(size: 12))
                            Text(backup.backupDate.map { "Recorded backup date: \($0.formatted())" } ?? "Backup date unknown").font(.system(size: 11))
                            Text(backup.encrypted.map { $0 ? "Encryption reported" : "Not encrypted (reported)" } ?? "Encryption unknown")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(backup.detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Reveal this backup in Finder") { NSWorkspace.shared.activateFileViewerSelecting([backup.url]) }
                                .buttonStyle(.glass).font(.system(size: 11))
                                .accessibilityLabel("Reveal backup \(backup.ordinal) in Finder")
                        }
                    }
                }
                if inventory.backups.count > displayLimit { Button("Show more backups") { displayLimit += 20 }.buttonStyle(.glass) }
            }
            Surface(padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Manage backups with Finder").font(.system(size: 14, weight: .semibold))
                    Text("Connect and select your iPhone or iPad in Finder. Under General, choose Manage Backups, then review available copies. Keep a usable backup before making changes.")
                    Text("Finder changes are outside Luma’s Activity and Undo. Luma does not create backups, decrypt them, test restores or modify the device.").foregroundStyle(.secondary)
                    Link("Apple’s backup management steps", destination: URL(string: "https://support.apple.com/en-us/108809")!)
                }.font(.system(size: 11))
            }
        }
    }
    private func emptyTitle(_ state: CoverageState) -> String {
        switch state { case .empty: "No local backup folders found"; case .missing: "Standard backup folder not present"; default: "Backup inspection unavailable" }
    }
    private func emptyDescription(_ state: CoverageState) -> String {
        switch state {
        case .empty, .missing: "This check does not cover iCloud or backups moved elsewhere. No files were changed."
        default: "Check ignored locations or access and retry. Unavailable data is not an empty backup."
        }
    }
}
