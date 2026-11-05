import AgentUsageCore
import SwiftUI

/// Draws one state at widget size, side by side in light and dark mode (§12 #10).
struct WidgetStatePreview: View {
    let state: PreviewData.State
    let size: WidgetSize

    var body: some View {
        let now = Date()
        HStack(spacing: 16) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                AccountWidgetView(account: PreviewData.account(state, now: now), now: now, size: size)
                    .padding(14)
                    .frame(width: size == .medium ? 338 : 158, height: 158)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .environment(\.colorScheme, scheme)
            }
        }
        .padding()
    }
}

#Preview("Medium · On pace") { WidgetStatePreview(state: .onPace, size: .medium) }
#Preview("Medium · Over pace") { WidgetStatePreview(state: .overPace, size: .medium) }
#Preview("Medium · Stale") { WidgetStatePreview(state: .stale, size: .medium) }
#Preview("Medium · Sign in required") { WidgetStatePreview(state: .signInRequired, size: .medium) }
#Preview("Medium · Re-authorise by") { WidgetStatePreview(state: .reauthoriseBy, size: .medium) }
#Preview("Medium · Limit reached") { WidgetStatePreview(state: .limitReached, size: .medium) }
#Preview("Medium · No active session") { WidgetStatePreview(state: .noActiveSession, size: .medium) }
#Preview("Medium · No Window length") { WidgetStatePreview(state: .noWindowLength, size: .medium) }
#Preview("Medium · Choose an Account") { WidgetStatePreview(state: .chooseAccount, size: .medium) }

#Preview("Small · On pace") { WidgetStatePreview(state: .onPace, size: .small) }
#Preview("Small · Over pace") { WidgetStatePreview(state: .overPace, size: .small) }
#Preview("Small · Stale") { WidgetStatePreview(state: .stale, size: .small) }
#Preview("Small · Sign in required") { WidgetStatePreview(state: .signInRequired, size: .small) }
#Preview("Small · Re-authorise by") { WidgetStatePreview(state: .reauthoriseBy, size: .small) }
#Preview("Small · Limit reached") { WidgetStatePreview(state: .limitReached, size: .small) }
#Preview("Small · No active session") { WidgetStatePreview(state: .noActiveSession, size: .small) }
#Preview("Small · No Window length") { WidgetStatePreview(state: .noWindowLength, size: .small) }
#Preview("Small · Choose an Account") { WidgetStatePreview(state: .chooseAccount, size: .small) }
