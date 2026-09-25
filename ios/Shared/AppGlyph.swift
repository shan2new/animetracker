import SwiftUI

/// A hand-drawn, single-ink replacement for the app's SF Symbol images.
/// Its point size follows the inherited text font so existing type styles stay aligned.
struct AppGlyph: View {
    @Environment(\.font) private var font
    @Environment(\.imageScale) private var imageScale

    let systemName: String
    private let decorative: Bool

    init(systemName: String, decorative: Bool = false) {
        self.systemName = systemName
        self.decorative = decorative
    }

    private var ruleNumber: String? {
        let pieces = systemName.split(separator: ".")
        guard pieces.count == 3,
              pieces[1] == "circle",
              pieces[2] == "fill",
              Int(pieces[0]) != nil else { return nil }
        return String(pieces[0])
    }

    private var assetName: String {
        if ruleNumber != nil { return "Glyph-number-circle" }
        guard let assetName = AppGlyphCatalog.assets[systemName] else {
            assertionFailure("Missing authored SVG for app glyph: \(systemName)")
            return "Glyph-info-circle"
        }
        return assetName
    }

    private var accessibleName: String {
        if let ruleNumber { return "Rule \(ruleNumber)" }
        let known: [String: String] = [
            "arrow.left": "Back",
            "chevron.down": "Close",
            "gobackward.10": "Rewind 10 seconds",
            "goforward.10": "Forward 10 seconds",
            "magnifyingglass": "Search",
            "square.and.arrow.up": "Share",
            "xmark": "Close",
        ]
        if let knownName = known[systemName] { return knownName }
        return systemName
            .replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".", with: " ")
            .capitalized
    }

    private var glyph: some View {
        AppGlyphLayout(scale: imageScale) {
            ZStack {
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                if let ruleNumber {
                    // The numeral is CUT OUT of the disc (the verified mark's check is, too): the
                    // disc is a template in the caller's ink, and a numeral in that same ink was a
                    // blank grey disc — the Community rules' bullets, 26 Sep.
                    Text(ruleNumber)
                        .font(font)
                        .fontWeight(.bold)
                        .scaleEffect(0.56)
                        .foregroundStyle(.black)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()

            // Text metrics provide the same font-sensitive intrinsic size as a symbol image.
            Text("M")
                .font(font)
                .hidden()
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder var body: some View {
        if decorative {
            glyph.accessibilityHidden(true)
        } else {
            glyph.accessibilityLabel(accessibleName)
        }
    }
}

/// Mirrors the intrinsic sizing of `Image(systemName:)`: text styles set glyph size, while a
/// surrounding frame continues to set hit areas and alignment without stretching the drawing.
private struct AppGlyphLayout: Layout {
    let scale: Image.Scale

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard subviews.count > 1 else { return .zero }
        let metrics = subviews[1].sizeThatFits(.unspecified)
        let factor: CGFloat = switch scale {
        case .small: 0.82
        case .medium: 1
        case .large: 1.18
        @unknown default: 1
        }
        let requested = max(1, metrics.height * factor)
        let offeredWidth = proposal.width.map { max(0, $0) } ?? requested
        let offeredHeight = proposal.height.map { max(0, $0) } ?? requested
        let side = min(requested, min(offeredWidth, offeredHeight))
        return CGSize(width: side, height: side)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard subviews.count > 1 else { return }
        subviews[0].place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
        subviews[1].place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
    }
}

struct AppGlyphLabel: View {
    private let title: String
    private let systemName: String

    init(_ title: String, systemName: String) {
        self.title = title
        self.systemName = systemName
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            AppGlyph(systemName: systemName, decorative: true)
        }
    }
}
