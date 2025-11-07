import SwiftUI

struct ChallengeTemplateCard: View {
    let template: ChallengeTemplate
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon
                Image(systemName: template.icon)
                    .font(.system(size: 40))
                    .foregroundColor(Color(hex: template.colorHex))

                // Title
                Text(template.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                // Description
                Text(template.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                // Stats
                HStack {
                    Label("\(template.suggestedTarget) min", systemImage: "clock")
                        .font(.caption2)
                    Spacer()
                    Label("+\(template.suggestedBonus)%", systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .frame(width: 180, height: 220)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: template.colorHex).opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: template.colorHex), lineWidth: 2)
            )
        }
    }
}