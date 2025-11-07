//
//  Item+CoreDataProperties.swift
//  
//
//  Created by Amine Nidae on 2025-11-03.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias ItemCoreDataPropertiesSet = NSSet

extension Item {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Item> {
        return NSFetchRequest<Item>(entityName: "Item")
    }

    @NSManaged public var timestamp: Date?

}

extension Item : Identifiable {

}
