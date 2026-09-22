import SwiftUI

struct SignalRow: View {
    @Binding var signal: SignalControl

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                Image(systemName: signal.icon)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(signal.title).font(.system(size: 14, weight: .semibold))
                Text(signal.subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            WeightPicker(weight: $signal.weight)
        }
    }
}
