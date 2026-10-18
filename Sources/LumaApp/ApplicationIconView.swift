import SwiftUI
import LumaCore

struct ApplicationIconView: View {
    let app: ApplicationRecord
    var size: CGFloat = 38
    var body: some View {
        Group {
            if let data = app.iconPNG, let icon = NSImage(data: data) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "macwindow").resizable().scaledToFit().foregroundStyle(.secondary).padding(5)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
