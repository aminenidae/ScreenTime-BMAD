//
//  StreakRecord+CoreDataProperties.swift
//  ScreenTimeRewards
//
//  Created by Amine Nidae on 2025-11-03.
//
//

public import Foundation
public import CoreData


public typealias StreakRecordCoreDataPropertiesSet = NSSet

extension StreakRecord {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<StreakRecord> {
        return NSFetchRequest<StreakRecord>(entityName: "StreakRecord")
    }

    @NSManaged public var streakID: String?
    @NSManaged public var childDeviceID: String?
    @NSManaged public var streakType: String?
    @NSManaged public var currentStreak: Int16
    @NSManaged public var longestStreak: Int16
    @NSManaged public var lastActivityDate: Date?

}

extension StreakRecord : Identifiable {

}
