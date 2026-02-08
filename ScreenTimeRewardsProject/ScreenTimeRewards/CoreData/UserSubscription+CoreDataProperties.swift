import Foundation
import CoreData

extension UserSubscription {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<UserSubscription> {
        NSFetchRequest<UserSubscription>(entityName: "UserSubscription")
    }

    @NSManaged public var autoRenewEnabled: Bool
    @NSManaged public var expiryDate: Date?
    @NSManaged public var graceEndDate: Date?
    @NSManaged public var lastValidatedDate: Date?
    @NSManaged public var originalTransactionID: String?
    @NSManaged public var purchaseDate: Date?
    @NSManaged public var subscriptionID: String?
    @NSManaged public var subscriptionStatus: String?
    @NSManaged public var subscriptionTier: String?
    @NSManaged public var transactionID: String?
    @NSManaged public var trialEndDate: Date?
    @NSManaged public var trialStartDate: Date?
    @NSManaged public var userDeviceID: String?
}

extension UserSubscription: Identifiable { }
