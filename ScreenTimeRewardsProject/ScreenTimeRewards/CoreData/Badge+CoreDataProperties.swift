//
//  Badge+CoreDataProperties.swift
//  ScreenTimeRewards
//
//  Created by Amine Nidae on 2025-11-03.
//
//

public import Foundation
public import CoreData


public typealias BadgeCoreDataPropertiesSet = NSSet

extension Badge {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Badge> {
        return NSFetchRequest<Badge>(entityName: "Badge")
    }

    @NSManaged public var badgeID: String?
    @NSManaged public var badgeName: String?
    @NSManaged public var badgeDescription: String?
    @NSManaged public var iconName: String?
    @NSManaged public var unlockedAt: Date?
    @NSManaged public var criteriaJSON: String?
    @NSManaged public var childDeviceID: String?

}

extension Badge : Identifiable {

}
