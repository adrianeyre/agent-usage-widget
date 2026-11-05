import AgentUsageCore
import AgentUsageViews
import SwiftUI

/// A sheet's title and one line under it, with an accessory on the right.
struct SheetHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Spacing.m)
            accessory()
        }
    }
}

/// `1 Sign in — 2 Details`, with the current step filled and finished steps ticked.
struct StepIndicator: View {
    let steps: [String]
    let current: Int

    var body: some View {
        HStack(spacing: Spacing.s) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                if index > 0 {
                    Capsule()
                        .fill(index <= current ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                        .frame(width: 18, height: 2)
                }
                HStack(spacing: Spacing.xs) {
                    ZStack {
                        Circle()
                            .fill(index <= current ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                        if index < current {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        } else {
                            Text("\(index + 1)").font(.system(size: 10, weight: .bold).monospacedDigit())
                        }
                    }
                    .foregroundStyle(index <= current ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: 18, height: 18)
                    Text(title)
                        .font(.caption.weight(index == current ? .semibold : .regular))
                        .foregroundStyle(index == current ? .primary : .secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(steps.count): \(steps[current])")
    }
}

/// The Providers as selectable cards: glyph, name and how it signs in.
struct ProviderPicker: View {
    let providers: [ProviderKind]
    @Binding var selection: ProviderKind
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: Spacing.m) {
            ForEach(providers, id: \.self) { provider in
                let selected = provider == selection
                Button {
                    selection = provider
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        HStack {
                            ProviderBadge(glyph: provider.glyphSystemName, name: provider.displayName, size: 26)
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                                .accessibilityHidden(true)
                        }
                        Text(provider.displayName)
                            .font(.callout.weight(.semibold))
                        Text(provider.addAccountHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(Spacing.m + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous)
                            .fill(selected ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.quinary))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous)
                            .strokeBorder(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator), lineWidth: selected ? 1.5 : 0.5)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(provider.displayName)
                .accessibilityHint(provider.addAccountHint)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .opacity(isEnabled ? 1 : 0.55)
    }
}

/// A short explanation set apart from the controls around it.
struct InfoCallout: View {
    let symbol: String
    let tint: Color
    let text: LocalizedStringKey

    init(symbol: String, tint: Color, text: String) {
        self.symbol = symbol
        self.tint = tint
        self.text = LocalizedStringKey(text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.callout)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.m + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

/// Where a sign-in stands: running, done or failed, in words and a symbol.
struct SignInStatus: View {
    enum State: Equatable {
        case idle, running, succeeded
        case failed(String)
    }

    let state: State
    var runningText = "Waiting for the browser…"

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small)
                Text(runningText).foregroundStyle(.secondary)
            }
            .font(.callout)
        case .succeeded:
            Label("Signed in", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout.weight(.medium))
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
