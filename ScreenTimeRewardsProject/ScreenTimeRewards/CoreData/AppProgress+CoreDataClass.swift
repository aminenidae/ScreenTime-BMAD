//
//  AppProgress+CoreDataClass.swift
//  ScreenTimeRewards
//
//  Created by Claude on 2025-11-11.
//
//

public import Foundation
public import CoreData

public typealias AppProgressCoreDataClassSet = NSSet

@objc(AppProgress)
public class AppProgress: NSManagedObject {

    var progressPercentage: Double {
        guard targetMinutes > 0 else { return 0.0 }
        return (Double(currentMinutes) / Double(targetMinutes)) * 100.0
    }
}
