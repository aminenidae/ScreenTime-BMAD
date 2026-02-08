//
//  AppProgress+CoreDataProperties.swift
//  ScreenTimeRewards
//
//  Created by Claude on 2025-11-11.
//
//

public import Foundation
public import CoreData


public typealias AppProgressCoreDataPropertiesSet = NSSet

extension AppProgress {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<AppProgress> {
        return NSFetchRequest<AppProgress>(entityName: "AppProgress")
    }

    @NSManaged public var appProgressID: String?
    @NSManaged public var challengeID: String?
    @NSManaged public var appLogicalID: String?
    @NSManaged public var currentMinutes: Int32
    @NSManaged public var targetMinutes: Int32
    @NSManaged public var isCompleted: Bool
    @NSManaged public var lastUpdated: Date?

}

extension AppProgress : Identifiable {

}
