//
//  Challenge+CoreDataProperties.swift
//  ScreenTimeRewards
//
//  Created by Amine Nidae on 2025-11-03.
//
//

public import Foundation
public import CoreData


public typealias ChallengeCoreDataPropertiesSet = NSSet

extension Challenge {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Challenge> {
        return NSFetchRequest<Challenge>(entityName: "Challenge")
    }

    @NSManaged public var challengeID: String?
    @NSManaged public var title: String?
    @NSManaged public var challengeDescription: String?
    @NSManaged public var goalType: String?
    @NSManaged public var targetValue: Int32
    @NSManaged public var bonusPercentage: Int16
    @NSManaged public var targetAppsJSON: String?
    @NSManaged public var rewardAppsJSON: String?
    @NSManaged public var startDate: Date?
    @NSManaged public var endDate: Date?
    @NSManaged public var startTime: Date?
    @NSManaged public var endTime: Date?
    @NSManaged public var isActive: Bool
    @NSManaged public var createdBy: String?
    @NSManaged public var assignedTo: String?
    @NSManaged public var activeDays: String?
    @NSManaged public var learningToRewardRatioData: String?

}

extension Challenge : Identifiable {

}
