import Foundation
import StoreKit

@MainActor
public class SubscriptionManager: ObservableObject {
    public static let shared = SubscriptionManager()
    
    @Published public private(set) var products: [Product] = []
    @Published public private(set) var purchasedProductIDs = Set<String>()
    
    private let productIDs = [
        "com.caocap.pro.monthly",
        "com.caocap.pro.yearly"
    ]
    
    private var updates: Task<Void, Never>? = nil
    
    init() {
        // Start listening for transactions
        updates = Task {
            for await result in Transaction.updates {
                await handle(transactionResult: result)
            }
        }
    }
    
    deinit {
        updates?.cancel()
    }
    
    public func fetchProducts() async {
        do {
            products = try await Product.products(for: productIDs)
            // Sort by price or duration if needed
        } catch {
            print("Failed to fetch products: \(error)")
        }
    }
    
    public func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()
            return transaction
        case .userCancelled, .pending:
            return nil
        @unknown default:
            return nil
        }
    }
    
    public func updatePurchasedProducts() async {
        var newPurchasedProductIDs = Set<String>()
        
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            
            if transaction.revocationDate == nil {
                newPurchasedProductIDs.insert(transaction.productID)
            }
        }
        
        self.purchasedProductIDs = newPurchasedProductIDs
    }
    
    public func restorePurchases() async throws {
        try await AppStore.sync()
        await updatePurchasedProducts()
    }
    
    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else { return }
        
        if transaction.revocationDate == nil {
            purchasedProductIDs.insert(transaction.productID)
        } else {
            purchasedProductIDs.remove(transaction.productID)
        }
        
        await transaction.finish()
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

public enum StoreError: Error {
    case failedVerification
}
