//
//  CollectedCard+CoreDataProperties.swift
//  ScreenTimeRewards
//

public import Foundation
public import CoreData

public typealias CollectedCardCoreDataPropertiesSet = NSSet

extension CollectedCard {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CollectedCard> {
        return NSFetchRequest<CollectedCard>(entityName: "CollectedCard")
    }

    @NSManaged public var collectionID: String?
    @NSManaged public var cardID: String?
    @NSManaged public var childDeviceID: String?
    @NSManaged public var seriesID: String?
    @NSManaged public var collectedAt: Date?
    @NSManaged public var isFavorite: Bool
    @NSManaged public var viewCount: Int16
}

extension CollectedCard: Identifiable {

}
