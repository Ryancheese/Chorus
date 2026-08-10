import Foundation

/// Launch switches. Flip `proPaywallEnabled` when App Store IAP is ready to ship.
public enum ChorusFeatureFlags {
    /// When false, Host allows unlimited speakers and hides upgrade / paywall UI.
    public static let proPaywallEnabled = false
}
