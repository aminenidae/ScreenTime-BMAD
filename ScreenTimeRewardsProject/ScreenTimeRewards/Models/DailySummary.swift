import Foundation
import CoreData

@objc(DailySummary)
public class DailySummary: NSManagedObject {

}

extension DailySummary {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<DailySummary> {
        return NSFetchRequest<DailySummary>(entityName: "DailySummary")
    }
    
    @NSManaged public var summaryID: String?
    @NSManaged public var date: Date?
    @NSManaged public var deviceID: String?
    @NSManaged public var totalLearningSeconds: Int32
    @NSManaged public var totalRewardSeconds: Int32
    @NSManaged public var totalPointsEarned: Int32
    @NSManaged public var appsUsedJSON: String?
    @NSManaged public var lastUpdated: Date?
}