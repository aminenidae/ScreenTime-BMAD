//
//  AvatarState+CoreDataProperties.swift
//  ScreenTimeRewards
//

public import Foundation
public import CoreData

public typealias AvatarStateCoreDataPropertiesSet = NSSet

extension AvatarState {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<AvatarState> {
        return NSFetchRequest<AvatarState>(entityName: "AvatarState")
    }

    @NSManaged public var stateID: String?
    @NSManaged public var avatarID: String?
    @NSManaged public var childDeviceID: String?
    @NSManaged public var currentStageLevel: Int16
    @NSManaged public var currentMood: String?
    @NSManaged public var totalNurturingMinutes: Int32
    @NSManaged public var lastInteractionDate: Date?
    @NSManaged public var equippedAccessoriesJSON: String?
    @NSManaged public var unlockedAccessoriesJSON: String?
    @NSManaged public var createdAt: Date?
}

extension AvatarState: Identifiable {

}
