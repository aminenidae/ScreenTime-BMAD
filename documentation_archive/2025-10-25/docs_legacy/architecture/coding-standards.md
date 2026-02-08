# ScreenTime Reward System - Coding Standards

## Overview

This document outlines the coding standards and best practices for the ScreenTime Reward System development team. These standards ensure code consistency, maintainability, and quality across the entire codebase while following Apple's recommended practices for iOS development.

## Language and Framework Standards

### Swift Version

All code must be written in **Swift 5.0+** to ensure compatibility with our target platforms and access to modern language features.

### SwiftUI Framework

The user interface will be built using **SwiftUI** as the primary framework, with UIKit integration only where SwiftUI limitations exist.

## Code Structure and Organization

### Project Structure

```
ScreenTimeRewardSystem/
├── AppDelegate.swift
├── SceneDelegate.swift
├── Models/
│   ├── User/
│   ├── Tracking/
│   ├── Rewards/
│   └── Analytics/
├── Views/
│   ├── Parent/
│   ├── Child/
│   ├── Components/
│   └── Modifiers/
├── ViewModels/
├── Services/
│   ├── TrackingService.swift
│   ├── RewardService.swift
│   ├── FamilyService.swift
│   └── CloudKitService.swift
├── Utilities/
├── Extensions/
├── Protocols/
└── Resources/
    ├── Assets.xcassets
    ├── Preview Content/
    └── Info.plist
```

### Module Organization

Each functional area should be organized into modules with the following structure:
- **Models**: Data structures and business logic entities
- **Views**: SwiftUI views and user interface components
- **ViewModels**: View state management and business logic coordination
- **Services**: Core functionality implementation and external system integration
- **Utilities**: Helper functions and extensions
- **Extensions**: Swift type extensions
- **Protocols**: Interface definitions for dependency inversion

## Naming Conventions

### General Naming

1. **Use descriptive names** that clearly indicate the purpose of variables, functions, and types
2. **Follow Swift API Design Guidelines** for consistency with the broader Swift ecosystem
3. **Use camelCase** for variables and functions
4. **Use PascalCase** for types (classes, structs, enums, protocols)
5. **Use UPPER_SNAKE_CASE** for constants and enum cases

### File Naming

- Files should be named after the primary type they contain
- Use PascalCase for file names
- Exception: SwiftUI View files may use more descriptive names when containing multiple related views

### Function and Variable Naming

```swift
// Good
func calculateLearningProgress(for category: AppCategory) -> Double
let currentUserProfile: UserProfile

// Avoid
func calc(for cat: AppCategory) -> Double
let user: UserProfile
```

### Protocol Naming

- Protocols that describe what something is should read as nouns (e.g., `Collection`)
- Protocols that describe a capability should be named using the suffixes `able`, `ible`, or `ing` (e.g., `Equatable`, `ProgressReporting`)

## Code Formatting

### Indentation and Spacing

- Use **4 spaces** for indentation (not tabs)
- Use **1 blank line** to separate logical sections of code
- Use **2 blank lines** to separate type definitions
- Remove trailing whitespace

### Line Length

- Prefer to keep lines under **120 characters**
- Maximum line length is **200 characters**

### Braces

- Opening braces should be on the same line as the declaration
- Closing braces should be on their own line, aligned with the start of the declaration

```swift
// Good
struct UserView: View {
    var body: some View {
        Text("Hello, World!")
    }
}

// Avoid
struct UserView: View
{
    var body: some View
    {
        Text("Hello, World!")
    }
}
```

### Function Declarations

- Place each function parameter on a new line when the function declaration is too long
- Use trailing closure syntax when the last parameter is a closure

```swift
// Good
func performTrackingUpdate(
    for user: UserProfile,
    with completion: @escaping (Result<TrackingData, Error>) -> Void
) {
    // Implementation
}

// Also good for trailing closures
UIView.animate(withDuration: 0.3) {
    // Animation code
}
```

## Documentation and Comments

### Documentation Comments

Use Swift's documentation comment format for all public APIs:

```swift
/// Calculates the progress percentage for a learning category.
/// - Parameter category: The learning category to calculate progress for.
/// - Returns: A value between 0.0 and 1.0 representing the progress percentage.
func calculateProgress(for category: AppCategory) -> Double {
    // Implementation
}
```

### Inline Comments

- Use inline comments sparingly and only when the code's purpose is not immediately clear
- Focus on explaining *why* something is done, not *what* is being done
- Keep comments up to date with code changes

```swift
// Good
// Using DispatchQueue.main to ensure UI updates happen on main thread
DispatchQueue.main.async {
    self.updateProgressView()
}

// Avoid
// Update view
DispatchQueue.main.async {
    self.updateProgressView()
}
```

## Error Handling

### Error Types

Define specific error types for each module:

```swift
enum TrackingError: Error {
    case permissionDenied
    case dataUnavailable
    case synchronizationFailed
}
```

### Error Handling Patterns

- Use `Result` type for functions that can fail
- Prefer throwing functions for synchronous operations
- Use completion handlers with `Result` for asynchronous operations
- Always handle errors appropriately - don't ignore them

```swift
// Good
func loadUserProfile() throws -> UserProfile {
    // Implementation
}

func saveUserProfile(_ profile: UserProfile, completion: @escaping (Result<Void, Error>) -> Void) {
    // Implementation
}
```

## Memory Management

### Avoiding Retain Cycles

- Use `[weak self]` or `[unowned self]` in closures when referencing `self`
- Prefer `weak` over `unowned` unless you're certain about the object's lifecycle

```swift
// Good
DispatchQueue.main.async { [weak self] in
    self?.updateUI()
}
```

### Proper Deinitialization

- Implement `deinit` for classes that need cleanup
- Cancel ongoing operations in `deinit`
- Remove observers and notifications

## SwiftUI Specific Standards

### View Structure

- Prefer struct over class for Views
- Use `@State` for view-local data
- Use `@Binding` for data that should be mutated by a child view
- Use `@ObservedObject` for external view models
- Use `@EnvironmentObject` for app-wide state

### View Modifiers

- Chain view modifiers for readability
- Group related modifiers
- Extract complex modifier chains into custom view modifiers

```swift
// Good
Text("Hello, World!")
    .font(.title)
    .foregroundColor(.blue)
    .padding()
    .background(Color.gray)
```

### View Composition

- Break complex views into smaller, reusable components
- Use `View` protocol extensions for common styling
- Prefer value types over reference types for view data

## Testing Standards

### Unit Test Naming

Use the format `test_whatIsBeingTested_expectedBehavior`:

```swift
func test_calculateProgress_withCompletedTarget_returnsOne() {
    // Test implementation
}
```

### Test Organization

- Group related tests using `XCTestCase` subclasses
- Use `setUp()` and `tearDown()` for test initialization and cleanup
- Make tests independent and repeatable
- Test both success and failure cases

## Security Considerations

### Data Protection

- Mark sensitive data with appropriate file protection levels
- Use Keychain Services for storing credentials
- Encrypt sensitive data in transit and at rest
- Validate and sanitize all input data

### Privacy Compliance

- Minimize data collection to what is strictly necessary
- Implement proper user consent mechanisms
- Provide clear privacy disclosures
- Follow COPPA and GDPR guidelines

## Performance Guidelines

### Efficient Data Structures

- Choose appropriate collection types for use cases
- Use lazy evaluation when processing large datasets
- Avoid unnecessary object creation in loops
- Prefer value types over reference types when possible

### Asynchronous Operations

- Perform heavy operations off the main thread
- Use `DispatchQueue` for background processing
- Prefer `OperationQueue` for complex dependency management
- Use `async/await` when available for cleaner asynchronous code

## Code Review Process

### Review Checklist

All code must pass the following checks during review:

1. [ ] Follows naming conventions
2. [ ] Proper error handling
3. [ ] Memory management considerations
4. [ ] Documentation comments for public APIs
5. [ ] Unit tests for new functionality
6. [ ] No commented-out code
7. [ ] No TODO comments without associated issues
8. [ ] Security and privacy compliance
9. [ ] Performance considerations
10. [ ] SwiftUI best practices followed

### Review Process

1. All code changes must be reviewed by at least one other team member
2. Reviews should focus on correctness, maintainability, and adherence to standards
3. Address all review comments before merging
4. Use pull requests for all code changes

## Tools and Automation

### SwiftLint

All code must pass SwiftLint validation with the project's configuration. Key rules enforced:

- `force_cast`: Forbidden
- `force_try`: Forbidden
- `implicit_getter`: Warning
- `line_length`: Max 120 characters
- `function_body_length`: Max 40 lines
- `type_body_length`: Max 200 lines

### Continuous Integration

- All pull requests must pass automated tests
- Code coverage should be maintained above 80%
- Security scanning should pass without critical issues
- Build times should be optimized

## Version Control Standards

### Commit Messages

Use the following format for commit messages:

```
type(scope): brief description

Detailed explanation of the changes if necessary.

Resolves: #123
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes
- `refactor`: Code refactoring
- `test`: Test-related changes
- `chore`: Maintenance tasks

### Branching Strategy

- Use `main` for production-ready code
- Use feature branches for new development
- Use `hotfix/` prefix for urgent fixes
- Delete branches after merging

This coding standards document ensures consistent, maintainable, and high-quality code across the ScreenTime Reward System project. All team members are expected to follow these guidelines and participate in maintaining and improving them as the project evolves.