import SwiftUI
import Charts
import LumaCore

// Use the property wrapper explicitly: the macOS 27 command-line SDK also
// declares a State macro whose plugin currently ships only with full Xcode.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Palette {
    // Keep action fills deep purple in both appearances so white labels retain contrast.
    static let accent = Color(red: 0.38, green: 0.36, blue: 0.86)
    static let mint = adaptive(light: (0.15, 0.53, 0.44), dark: (0.38, 0.79, 0.67))
    static let blue = adaptive(light: (0.24, 0.49, 0.79), dark: (0.45, 0.68, 0.97))
    static let peach = adaptive(light: (0.69, 0.40, 0.20), dark: (0.92, 0.69, 0.49))
    static let canvas = adaptive(light: (0.965, 0.965, 0.975), dark: (0.075, 0.078, 0.10))
    static let surface = adaptive(light: (1, 1, 1), dark: (0.115, 0.12, 0.15))

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let values = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: values.0, green: values.1, blue: values.2, alpha: 1)
        })
    }
}

struct AmbientBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Palette.canvas
            if !reduceTransparency {
                RadialGradient(colors: [Palette.accent.opacity(scheme == .dark ? 0.11 : 0.065), .clear], center: .topTrailing, startRadius: 0, endRadius: 600)
                RadialGradient(colors: [Palette.mint.opacity(0.055), .clear], center: .bottomLeading, startRadius: 0, endRadius: 500)
            }
        }.ignoresSafeArea()
    }
}

struct Surface<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var padding: CGFloat = 22
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface.opacity(reduceTransparency || contrast == .increased ? 1 : scheme == .dark ? 0.88 : 0.78), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(contrast == .increased ? 0.5 : scheme == .dark ? 0.075 : 0.055)))
    }
}

struct SymbolTile: View {
    let symbol: String
    var tint: Color = Palette.accent
    var size: CGFloat = 42
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.43, weight: .medium))
            .foregroundStyle(tint).frame(width: size, height: size)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.7).foregroundStyle(.secondary)
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 17, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Spacer()
            if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(.tertiary) }
        }
    }
}

struct StatusPill: View {
    let text: String
    var tint: Color = Palette.mint
    var body: some View {
        HStack(spacing: 5) { Circle().fill(tint).frame(width: 5, height: 5); Text(text).font(.system(size: 10, weight: .medium)) }
            .padding(.horizontal, 10).padding(.vertical, 6).background(tint.opacity(0.09), in: Capsule()).foregroundStyle(tint)
    }
}

struct SafetyBadge: View {
    let level: SafetyLevel
    var body: some View {
        Text(level.rawValue).font(.system(size: 10, weight: .medium))
            .foregroundStyle(level == .safe ? Palette.mint : level == .review ? Palette.peach : Palette.blue)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background((level == .safe ? Palette.mint : level == .review ? Palette.peach : Palette.blue).opacity(0.09), in: Capsule())
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol = "arrow.right"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) { Text(title); Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(.white)
        }.buttonStyle(.glassProminent).tint(Palette.accent)
    }
}

struct Sparkline: View {
    let values: [Double]
    var tint = Palette.accent
    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { sample in
            AreaMark(x: .value("Sample", sample.offset), y: .value("Usage", sample.element))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Sample", sample.offset), y: .value("Usage", sample.element))
                .foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 1.8)).interpolationMethod(.catmullRom)
        }.chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: 0...100)
            .accessibilityLabel("Usage history").frame(height: 40)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String
    var actionSymbol = "magnifyingglass"
    var action: () -> Void
    var body: some View {
        VStack(spacing: 17) {
            Image(systemName: symbol).font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Palette.accent)
                .frame(width: 90, height: 90).glassEffect(.regular.tint(Palette.accent.opacity(0.06)), in: .rect(cornerRadius: 28))
            Text(title).font(.system(size: 24, weight: .semibold))
            Text(message).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5).frame(maxWidth: 380)
            PrimaryButton(title: actionTitle, symbol: actionSymbol, action: action).padding(.top, 5)
        }.frame(maxWidth: .infinity).padding(.vertical, 70)
    }
}

struct InsightRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    let value: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SymbolTile(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 14)
                Text(value).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }.padding(.vertical, 11).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
