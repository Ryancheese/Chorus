import SwiftUI

/// Shared SwiftUI shims so Speaker can run on iOS 15 while keeping newer polish on iOS 16/17+.
public extension View {
    /// iOS 17 / macOS 14 two-parameter `onChange`, with iOS 15–16 fallback.
    @ViewBuilder
    func chorusOnChange<V: Equatable>(
        of value: V,
        perform: @escaping (_ newValue: V) -> Void
    ) -> some View {
        if #available(iOS 17, macOS 14, *) {
            onChange(of: value) { _, newValue in
                perform(newValue)
            }
        } else {
            #if os(iOS)
            onChange(of: value, perform: perform)
            #else
            onChange(of: value) { newValue in
                perform(newValue)
            }
            #endif
        }
    }

    @ViewBuilder
    func chorusScrollBounceBasedOnSize() -> some View {
        if #available(iOS 16.4, macOS 13.3, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }

    @ViewBuilder
    func chorusContentTransitionOpacity() -> some View {
        if #available(iOS 16, macOS 13, *) {
            contentTransition(.opacity)
        } else {
            self
        }
    }

    @ViewBuilder
    func chorusSymbolEffectVariableColor(isActive: Bool) -> some View {
        if #available(iOS 17, macOS 14, *) {
            symbolEffect(.variableColor.iterative, isActive: isActive)
        } else {
            self
        }
    }
}

/// `NavigationStack` on modern OS; `NavigationView` on iOS 15.
public struct ChorusNavigationContainer<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 16, macOS 13, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                #if os(iOS)
                .navigationViewStyle(.stack)
                #endif
        }
    }
}

/// `ViewThatFits` on iOS 16+; prefer labeled controls, else icons on iOS 15.
public struct ChorusHorizontalFitBar<Primary: View, Fallback: View>: View {
    private let primary: Primary
    private let fallback: Fallback

    public init(
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder fallback: () -> Fallback
    ) {
        self.primary = primary()
        self.fallback = fallback()
    }

    public var body: some View {
        if #available(iOS 16, macOS 13, *) {
            ViewThatFits(in: .horizontal) {
                primary
                fallback
            }
        } else {
            fallback
        }
    }
}
