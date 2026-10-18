import SwiftUI
import Combine
import AppKit
import LumaCore

@MainActor @Observable final class StorageVolumeModel {
    var volumes: [StorageVolume] = []
    var loading = false
    var issue: String?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var unmountObserver: AnyCancellable?
    @ObservationIgnored private var observationGeneration = UUID()

    func refresh() {
        guard !loading else { return }
        loading = true
        refreshTask = Task {
            let result = await Task.detached(priority: .utility) { StorageVolume.mounted() }.value
            guard !Task.isCancelled else { loading = false; return }
            volumes = result; loading = false
        }
    }

    func observe(_ scope: StorageScope, invalidated: @escaping @MainActor () -> Void) {
        stopObserving(); issue = nil
        let generation = observationGeneration
        unmountObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification).sink { [weak self] notification in
            guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            Task { @MainActor [weak self] in
                guard let self, self.observationGeneration == generation, Data(url.standardizedFileURL.path.utf8) == Data(scope.volume.identity.mountPath.utf8) else { return }
                self.issue = "The volume was unmounted. Choose the target and scan again, even if it has reappeared."
                invalidated(); self.refresh()
            }
        }
        observationTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                    let worker = Task.detached(priority: .utility) { try scope.validate() }
                    try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                } catch is CancellationError { return }
                catch {
                    guard !Task.isCancelled else { return }
                    issue = "The volume is unavailable or the analysis root changed. Choose the target and scan again."
                    invalidated(); refresh(); return
                }
            }
        }
    }

    func stopObserving() {
        observationGeneration = UUID()
        observationTask?.cancel(); observationTask = nil
        unmountObserver?.cancel(); unmountObserver = nil
    }

    deinit { refreshTask?.cancel(); observationTask?.cancel() }
}

struct StorageVolumePicker: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Analysis target").font(.headline)
                Spacer()
                Button("Refresh volumes") { model.storageVolumes.refresh() }.buttonStyle(.glass).disabled(model.storageVolumes.loading)
                Button("Choose a folder") { model.chooseFolder(for: .storage) }.buttonStyle(.glass).disabled(!model.canStartScan)
            }
            if model.storageVolumes.loading { ProgressView("Reading local volume information…").controlSize(.small) }
            Menu("Analyze a supported local volume") {
                ForEach(model.storageVolumes.volumes) { volume in
                    Button("\(volume.name) · \(volume.filesystem) · \(volume.identity.mountPath)\(volume.isReadOnly ? " · Read-only" : "")") {
                        model.destination = .storage
                        model.startScan(.init(.storage, root: URL(fileURLWithPath: volume.identity.mountPath), storageVolumeIdentity: volume.identity))
                    }
                }
                if model.storageVolumes.volumes.isEmpty { Text("No supported local volumes available") }
            }.menuStyle(.borderlessButton).fixedSize().disabled(!model.canStartScan)
            Text("External volumes and targets outside your home are inspection-only. Network, provider-managed and unidentified volumes remain unsupported.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let issue = model.storageVolumes.issue { Label(issue, systemImage: "externaldrive.badge.exclamationmark").font(.system(size: 12)).foregroundStyle(Palette.peach) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
        .onAppear { model.storageVolumes.refresh() }
    }
}

struct StorageVolumeSummary: View {
    let scope: StorageScope
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(scope.volume.name, systemImage: "externaldrive").font(.headline)
                Spacer()
                StatusPill(text: scope.inspectionOnly ? "Inspection only" : "Your files", tint: Palette.mint)
            }
            Text("\(scope.volume.filesystem) · \(scope.volume.isReadOnly ? "Read-only volume" : "Read/write volume") · \(scope.volume.identity.mountPath)").font(.system(size: 11)).textSelection(.enabled)
            Text("Analysis root: \(scope.root.path)").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            HStack(spacing: 24) {
                metric("Reported capacity", scope.volume.capacity)
                metric("Filesystem free space", scope.volume.free)
                metric("Available for important usage", scope.volume.availableForImportantUsage)
            }
            Text("Volume observations are from scan time. APFS volumes may share capacity. Available for important usage is a system estimate that may include reclaimable space; purgeable bytes are not measured separately. Scanned logical bytes are partial where access is unavailable and are never guaranteed physical recovery.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
    }
    private func metric(_ name: String, _ value: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value.map(formatBytes) ?? "Unavailable").font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
    }
}
