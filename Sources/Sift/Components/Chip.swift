import SwiftUI

struct Chip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Theme.accentPrimary.opacity(0.9) : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : Color.white.opacity(0.14), lineWidth: 1)
                )
                .foregroundStyle(isSelected ? .white : .white.opacity(0.75))
        }
        .buttonStyle(.plain)
    }
}
