import SwiftUI

extension View {
    /// Standard card surface: solid fill + soft shadow, paired with `Color.appPageBackground`
    /// behind it. Explicit colors instead of system control colors, since those lost contrast
    /// against each other under Liquid Glass.
    func cardBackground(cornerRadius: CGFloat = Constants.UI.cornerRadius, fill: Color = .appCardBackground) -> some View {
        modifier(CardBackgroundModifier(cornerRadius: cornerRadius, fill: fill))
    }
}

private struct CardBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat
    let fill: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
    }
}
