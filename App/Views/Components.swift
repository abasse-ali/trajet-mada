import Charts
import SwiftUI
import TrajetCore

/// Icône SVG du catalogue d'assets, teintée.
struct Icon: View {
    let name: String
    var size: CGFloat
    var color: Color

    init(_ name: String, size: CGFloat = 18, color: Color = .primary) {
        self.name = name
        self.size = size
        self.color = color
    }

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

struct ModeIcon: View {
    let mode: Mode
    var size: CGFloat = 18
    var color: Color = .accentColor

    var body: some View {
        Icon(mode.iconName, size: size, color: color)
    }
}

/// Disposition en lignes qui passent à la ligne quand la place manque.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// « Toulouse › [train] Paris › [avion] Antsiranana »
struct RouteChain: View {
    let steps: [PricedStep]

    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: 4) {
            if let first = steps.first {
                Text(NetworkData.place(first.from).short)
                    .font(.subheadline.weight(.medium))
            }
            ForEach(steps) { step in
                HStack(spacing: 4) {
                    Icon("ui.chevron", size: 11, color: .secondary)
                    ModeIcon(mode: step.mode, size: 15)
                    Text(NetworkData.place(step.to).short)
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }
}

struct Pill: View {
    let text: String
    var icon: String? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Icon(icon, size: 11, color: color) }
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.13), in: Capsule())
    }
}

extension PriceQuality {
    var color: Color {
        switch self {
        case .live: return .green
        case .cached: return .teal
        case .tariff: return .indigo
        case .unknown: return .orange
        }
    }

    var icon: String {
        switch self {
        case .live: return "ui.bolt"
        case .cached: return "ui.check"
        case .tariff: return "ui.ticket"
        case .unknown: return "ui.info"
        }
    }
}

struct QualityPill: View {
    let quality: PriceQuality

    var body: some View {
        Pill(text: quality.label, icon: quality.icon, color: quality.color)
    }
}

/// Boutons de réservation qui ouvrent le site du transporteur.
struct BookingLinks: View {
    let links: [BookingLink]

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(links) { link in
                Link(destination: link.url) {
                    HStack(spacing: 5) {
                        Text(link.label)
                            .font(.footnote.weight(.semibold))
                        Icon("ui.external", size: 11, color: .accentColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

/// Meilleur prix total aller-retour selon la date de départ.
struct PriceChart: View {
    let data: [DayPrice]

    var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("Départ", item.day.localDate(), unit: .day),
                y: .value("Prix", item.price)
            )
            .foregroundStyle(Color.accentColor.gradient)
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartYAxisLabel("€")
        .frame(height: 180)
    }
}
