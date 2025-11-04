//
//  ChallengeProgress+CoreDataProperties.swift
//  ScreenTimeRewards
//
//  Created by Amine Nidae on 2025-11-03.
//
//

public import Foundation
public import CoreData


public typealias ChallengeProgressCoreDataPropertiesSet = NSSet

extension ChallengeProgress {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChallengeProgress> {
        return NSFetchRequest<ChallengeProgress>(entityName: "ChallengeProgress")
    }

    @NSManaged public var progressID: String?
    @NSManaged public var challengeID: String?
    @NSManaged public var childDeviceID: String?
    @NSManaged public var currentValue: Int32
    @NSManaged public var targetValue: Int32
    @NSManaged public var isCompleted: Bool
    @NSManaged public var completedDate: Date?
    @NSManaged public var bonusPointsEarned: Int32
    @NSManaged public var lastUpdated: Date?

}

extension ChallengeProgress : Identifiable {

}
