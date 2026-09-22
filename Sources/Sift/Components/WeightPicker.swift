import SwiftUI

struct WeightPicker: View {
    @Binding var weight: Weight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Weight.allCases) { option in
                Text(option.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(weight == option ? Theme.accentPrimary : Color.clear))
                    .foregroundStyle(weight == option ? .white : .white.opacity(0.55))
                    .contentShape(Capsule())
                    .onTapGesture { weight = option }
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}
