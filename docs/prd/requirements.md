# Requirements

## Functional Requirements
1. FR1: Track time spent on designated learning apps using Apple's Screen Time API
2. FR2: Automatically unlock selected reward apps after learning targets are met
3. FR3: Provide a parental dashboard for setting learning targets and selecting reward apps
4. FR4: Display progress tracking and analytics for both parents and children
5. FR5: Enable customizable duration goals for different categories of learning apps
6. FR6: Offer a child-friendly interface for viewing progress and claiming rewards
7. FR7: Support family account management with parent and child profiles
8. FR8: Provide notifications to parents and children about progress and rewards
9. FR9: Enable parents to have full control over all settings from their device
10. FR10: Restrict children to only visualize earned rewards and claim/redeem them
11. FR11: Implement a reward points system where learning time converts to points (e.g., 10 minutes = 10 points)
12. FR12: Allow parents to configure reward redemption rates (e.g., 10 points = 10 minutes of access to reward apps)
13. FR13: Block all apps on child's device except learning apps and authorized apps set by parent
14. FR14: Enable parents to set downtime schedules and other family control framework features

## Non-Functional Requirements
1. NFR1: Support iOS 14+ and iPadOS 14+ devices
2. NFR2: Maintain battery consumption below 5% during normal operation
3. NFR3: Ensure all data transmission is encrypted using Apple's native encryption frameworks
4. NFR4: Comply with COPPA, GDPR, and Apple's App Store guidelines
5. NFR5: Achieve app store rating of 4.0+ stars within first 3 months
6. NFR6: Support up to 5 child profiles per family account
7. NFR7: Provide offline functionality for tracking when internet is unavailable with CloudKit synchronization when online
8. NFR8: Ensure app size remains under 50MB
9. NFR9: Comply with all Apple family control and privacy restrictions
10. NFR10: Handle Apple's private tokens and device management limitations gracefully
11. NFR11: Utilize only Apple's native frameworks and CloudKit for all backend services
12. NFR12: Ensure seamless synchronization across all Apple devices using CloudKit
