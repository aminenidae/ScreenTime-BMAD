//
//  ChallengeProgress+CoreDataClass.swift
//  ScreenTimeRewards
//
//  Created by Amine Nidae on 2025-11-03.
//
//

public import Foundation
public import CoreData

public typealias ChallengeProgressCoreDataClassSet = NSSet

@objc(ChallengeProgress)
public class ChallengeProgress: NSManagedObject {

    var progressPercentage: Double {
        guard targetValue > 0 else { return 0.0 }
        return (Double(currentValue) / Double(targetValue)) * 100.0
    }
}
