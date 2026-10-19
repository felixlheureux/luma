import SwiftUI

/// Existing generated-data review remains available while task 059 adds the
/// small approved Maintenance action set.
struct MaintenanceEntryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Check supported caches and generated files before choosing what to remove.")
                .font(.caption).foregroundStyle(.secondary)
            CleanView()
        }
    }
}
