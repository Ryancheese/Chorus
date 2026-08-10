import Combine
import Foundation
import StoreKit

/// StoreKit 2 entitlements for Chorus Host Pro (Apple platforms only).
@MainActor
public final class ProEntitlementStore: ObservableObject {
    public static let productID = "com.chorus.host.pro"

    @Published public private(set) var isPro = false
    @Published public private(set) var product: Product?
    @Published public private(set) var isBusy = false
    @Published public private(set) var lastError: String?

    private var updatesTask: Task<Void, Never>?

    public init() {
        updatesTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
        Task { [weak self] in
            await self?.refresh()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    public var displayPrice: String {
        product?.displayPrice ?? "—"
    }

    public func refresh() async {
        isBusy = true
        defer { isBusy = false }
        lastError = nil
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            lastError = error.localizedDescription
        }
        await updateEntitlement()
    }

    public func purchase() async -> Bool {
        isBusy = true
        defer { isBusy = false }
        lastError = nil

        if product == nil {
            await refresh()
        }
        guard let product else {
            lastError = L10n.text("pro.error.unavailable")
            return false
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateEntitlement()
                return isPro
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    public func restore() async {
        isBusy = true
        defer { isBusy = false }
        lastError = nil
        do {
            try await AppStore.sync()
            await updateEntitlement()
            if !isPro {
                lastError = L10n.text("pro.error.restore.empty")
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            if let transaction = try? checkVerified(update) {
                await transaction.finish()
                await updateEntitlement()
            }
        }
    }

    private func updateEntitlement() async {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "chorus.pro.debugUnlocked") {
            isPro = true
            return
        }
        #endif

        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == Self.productID {
                entitled = true
                break
            }
        }
        isPro = entitled
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
