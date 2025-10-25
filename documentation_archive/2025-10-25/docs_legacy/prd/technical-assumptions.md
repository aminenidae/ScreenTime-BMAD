# Technical Assumptions

## Repository Structure
Monorepo structure for simplified management and deployment

## Service Architecture
Native iOS application with minimal backend services for account management and synchronization, fully leveraging Apple's CloudKit for data storage and synchronization

## Testing Requirements
Unit testing for core logic, integration testing for Apple API interactions, and manual testing for UI/UX

## Additional Technical Assumptions and Requests
1. Native Swift development with SwiftUI for UI components
2. Integration with Apple's Screen Time and Device Management APIs
3. Core Data for local storage with iCloud/CloudKit synchronization for family data sharing
4. CloudKit for all backend data storage, synchronization, and family account management
5. Analytics framework for usage tracking and improvement insights
6. Implementation of Apple's Family Sharing controls for parent-child device management
7. Compliance with Apple's privacy requirements including App Tracking Transparency
8. Handling of Apple's private tokens for device management and Screen Time API access
9. Exclusive use of Apple's native frameworks and services (no third-party backend services)
10. CloudKit integration for seamless data synchronization across all family devices
11. End-to-end encryption of all sensitive family data using Apple's security frameworks
12. Implementation of app blocking functionality using Apple's device management frameworks
13. Integration with Apple's Downtime and other family control features
