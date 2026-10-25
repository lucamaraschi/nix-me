import SwiftUI

enum OxidePalette {
    static let background = Color(red: 0.031, green: 0.059, blue: 0.067)
    static let sidebar = Color(red: 0.055, green: 0.090, blue: 0.094)
    static let panel = Color(red: 0.086, green: 0.137, blue: 0.133)
    static let panelRaised = Color(red: 0.105, green: 0.145, blue: 0.153)
    static let terminal = Color(red: 0.018, green: 0.032, blue: 0.035)
    static let border = Color.white.opacity(0.12)
    static let borderStrong = Color.white.opacity(0.22)
    static let primary = Color(red: 0.87, green: 0.87, blue: 0.87)
    static let secondary = Color(red: 0.63, green: 0.65, blue: 0.65)
    static let muted = Color(red: 0.38, green: 0.40, blue: 0.40)
    static let green = Color(red: 0.0, green: 0.85, blue: 0.57)
    static let amber = Color(red: 1.0, green: 0.64, blue: 0.21)
    static let cyan = Color(red: 0.26, green: 0.78, blue: 0.84)
    static let red = Color(red: 1.0, green: 0.35, blue: 0.31)
}

struct OxideGridBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [OxidePalette.background, Color(red: 0.025, green: 0.044, blue: 0.051)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Canvas { context, size in
                var grid = Path()
                stride(from: 0.0, through: size.width, by: 44).forEach { x in
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                stride(from: 0.0, through: size.height, by: 44).forEach { y in
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(Color.white.opacity(0.018)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
    }
}

struct OxideButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, destructive, ghost }

    @Environment(\.isEnabled) private var isEnabled
    let variant: Variant

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(0.35)
            .foregroundStyle(foreground)
            .padding(.horizontal, variant == .ghost ? 8 : 14)
            .padding(.vertical, variant == .ghost ? 6 : 9)
            .background(background(configuration.isPressed))
            .overlay(Rectangle().stroke(border, lineWidth: variant == .ghost ? 0 : 1))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
    }

    private var foreground: Color {
        switch variant {
        case .primary: OxidePalette.background
        case .secondary, .destructive, .ghost: OxidePalette.primary
        }
    }

    private var border: Color {
        switch variant {
        case .primary: OxidePalette.green
        case .secondary: OxidePalette.borderStrong
        case .destructive: OxidePalette.red.opacity(0.8)
        case .ghost: .clear
        }
    }

    private func background(_ pressed: Bool) -> Color {
        switch variant {
        case .primary: OxidePalette.green.opacity(pressed ? 0.72 : 1)
        case .secondary: OxidePalette.panelRaised.opacity(pressed ? 1 : 0.72)
        case .destructive: OxidePalette.red.opacity(pressed ? 0.28 : 0.14)
        case .ghost: pressed ? OxidePalette.panelRaised : .clear
        }
    }
}

extension View {
    func oxidePanel(padding: CGFloat = 16, border: Color = OxidePalette.border) -> some View {
        self
            .padding(padding)
            .background(OxidePalette.panel.opacity(0.82))
            .overlay(Rectangle().stroke(border))
    }

    func oxideLabel(color: Color = OxidePalette.muted) -> some View {
        self
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(color)
    }
}
