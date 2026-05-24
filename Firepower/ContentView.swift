import SwiftUI

// Shared UI utilities used across the app.

// MARK: - Button style

struct FirepowerButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let v = UInt64(h, radix: 16) ?? 0
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8)  & 0xFF) / 255
        let b = Double(v & 0xFF)         / 255
        self.init(red: r, green: g, blue: b)
    }
}
