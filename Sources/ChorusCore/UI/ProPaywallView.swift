import SwiftUI

/// Paywall shown when a free Host tries to connect a second Speaker.
public struct ProPaywallView: View {
    @ObservedObject private var store: ProEntitlementStore
    @Environment(\.dismiss) private var dismiss

    public init(store: ProEntitlementStore) {
        self.store = store
    }

    public var body: some View {
        ChorusNavigationContainer {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .foregroundStyle(GlassTheme.accent)

                Text(L10n.text("pro.paywall.title"))
                    .font(.system(.title2, design: .rounded).weight(.bold))

                Text(L10n.text("pro.paywall.body"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                feature(L10n.text("pro.paywall.feature.multi"))
                feature(L10n.text("pro.paywall.feature.lifetime"))

                if let error = store.lastError {
                    Text(error)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red.opacity(0.85))
                }

                Spacer(minLength: 0)

                Button {
                    Task {
                        if await store.purchase() {
                            dismiss()
                        }
                    }
                } label: {
                    if store.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(L10n.format("pro.paywall.buy", store.displayPrice))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(GlassPrimaryButtonStyle(enabled: !store.isBusy))
                .disabled(store.isBusy)

                Button(L10n.text("pro.paywall.restore")) {
                    Task { await store.restore() }
                }
                .buttonStyle(GlassSecondaryButtonStyle())
                .disabled(store.isBusy)
                .frame(maxWidth: .infinity)

                Button(L10n.text("action.close")) {
                    dismiss()
                }
                .buttonStyle(GlassSecondaryButtonStyle())
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            #if os(macOS)
            .frame(minWidth: 420, idealWidth: 460, minHeight: 420, idealHeight: 480)
            #endif
            .navigationTitle(L10n.text("pro.paywall.nav"))
            .task {
                await store.refresh()
            }
        }
    }

    private func feature(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(GlassTheme.mint)
            Text(text)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
