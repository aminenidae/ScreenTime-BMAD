import SwiftUI
import FamilyControls
import ManagedSettings

struct ChallengeBuilderAppSelectionRow: View {
    let token: ManagedSettings.ApplicationToken
    let title: String
    var subtitle: String?
    let isSelected: Bool
    var onToggle: () -> Void

    // Configuration support
    var configuration: AppScheduleConfiguration?
    var onConfigure: (() -> Void)?
    var isConfigured: Bool { configuration != nil }

    var body: some View {
        Button(action: {
            onToggle()
            // Also trigger configure if a handler is provided
            onConfigure?()
        }) {
            HStack(spacing: 12) {
                iconView

                // App name and config status
                VStack(alignment: .leading, spacing: 4) {
                    if #available(iOS 15.2, *) {
                        Label(token)
                            .labelStyle(.titleOnly)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ChallengeBuilderTheme.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text(title.isEmpty ? "App" : title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ChallengeBuilderTheme.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    // Configuration status subtitle
                    if isSelected {
                        configStatusView
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // Configure button for selected apps
                if isSelected && onConfigure != nil {
                    Button(action: { onConfigure?() }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .foregroundColor(isConfigured ? AppTheme.vibrantTeal : .orange)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(height: 88)
            .frame(maxWidth: 600)
            .background(rowBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Config Status View

    @ViewBuilder
    private var configStatusView: some View {
        if let config = configuration {
            // Configured state
            Text(config.displaySummary)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.vibrantTeal)
                .lineLimit(1)
        } else if onConfigure != nil {
            // Unconfigured state
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text("Tap to configure")
                    .font(.system(size: 12))
            }
            .foregroundColor(.orange)
        }
    }

    // MARK: - Styling

    private var rowBackground: Color {
        if isSelected {
            if isConfigured {
                return ChallengeBuilderTheme.primary.opacity(0.1)
            } else if onConfigure != nil {
                return Color.orange.opacity(0.08)
            }
            return ChallengeBuilderTheme.primary.opacity(0.1)
        }
        return ChallengeBuilderTheme.surface
    }

    private var borderColor: Color {
        if isSelected {
            if isConfigured {
                return ChallengeBuilderTheme.primary
            } else if onConfigure != nil {
                return .orange.opacity(0.6)
            }
            return ChallengeBuilderTheme.primary
        }
        return ChallengeBuilderTheme.border.opacity(0.3)
    }

    @ViewBuilder
    private var iconView: some View {
        if #available(iOS 15.2, *) {
            Label(token)
                .labelStyle(.iconOnly)
                .scaleEffect(1.35)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "app")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                )
        }
    }
}
