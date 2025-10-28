import XCTest
import SwiftUI
@testable import ScreenTimeRewards

final class DeviceSelectionViewTests: XCTestCase {
    
    func testDeviceSelectionViewExists() {
        let view = DeviceSelectionView()
        XCTAssertNotNil(view)
    }
    
    func testDeviceTypeCardViewParentMode() {
        let cardView = DeviceTypeCardView(mode: .parentDevice, isSelected: false) {
            // Action handler
        }
        
        XCTAssertNotNil(cardView)
    }
    
    func testDeviceTypeCardViewChildMode() {
        let cardView = DeviceTypeCardView(mode: .childDevice, isSelected: false) {
            // Action handler
        }
        
        XCTAssertNotNil(cardView)
    }
}