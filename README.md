# ScreenTime Reward System - Architecture Documentation

## Overview

This repository contains the architecture documentation for the ScreenTime Reward System, a native iOS/iPadOS application that implements a reward-based screen time management system for children. The system motivates educational engagement by unlocking "Reward Apps" only after children complete designated duration targets on "Learning Apps".

## Documentation Structure

### Core Architecture Documents

1. [Full Stack Architecture](docs/architecture.md) - Complete system architecture including technology choices, component design, and integration strategies
2. [Technology Stack](docs/architecture/tech-stack.md) - Detailed breakdown of frameworks, tools, and libraries used in the implementation
3. [Coding Standards](docs/architecture/coding-standards.md) - Development guidelines and best practices for maintaining code quality
4. [Source Tree](docs/architecture/source-tree.md) - Detailed overview of the project structure and organization

### Product Requirements

1. [Product Requirements Document (PRD)](docs/prd.md) - Complete product specification including goals, requirements, and user stories
2. [Front-End Specification](docs/front-end-spec.md) - Detailed UI/UX design specifications and user experience guidelines
3. [Project Brief](docs/project-brief.md) - High-level overview of the project vision, goals, and target users

### Technical Feasibility

1. [Technical Feasibility Study](docs/technical-feasibility-study.md) - Analysis of the technical viability within Apple's ecosystem
2. [Technical Feasibility Testing Plan](docs/technical-feasibility-testing-plan.md) - Detailed plan for validating core technical concepts
3. [Technical Feasibility Checklist](docs/technical-feasibility-checklist.md) - Validation checklist for all technical requirements

## System Overview

The ScreenTime Reward System is designed to work exclusively within Apple's ecosystem, utilizing native frameworks and services to ensure compatibility, security, and performance while maintaining all data within Apple's privacy-compliant infrastructure.

### Key Features

- **Learning App Tracking**: Monitor time spent on designated educational apps with automatic categorization
- **Reward App Unlocking**: Automatically unlock selected entertainment apps after learning targets are met
- **Parental Dashboard**: Comprehensive interface for parents to set learning targets, select reward apps, and monitor progress
- **Child Progress View**: Simple, engaging interface for children to view their progress and claim rewards
- **Family Account Management**: Support for parent and child profiles with appropriate access controls

### Technical Architecture

The system follows a layered architecture approach:

1. **User Interface Layer**: SwiftUI-based interfaces for both parent and child users
2. **Business Logic Layer**: Core application services and view models
3. **Data Layer**: Core Data for local storage with CloudKit synchronization
4. **Integration Layer**: Apple framework integrations (Screen Time API, Family Sharing, etc.)

## Development Guidelines

All development should follow the guidelines outlined in:

- [Coding Standards](docs/architecture/coding-standards.md)
- [Technology Stack](docs/architecture/tech-stack.md)
- [Source Tree](docs/architecture/source-tree.md)

## Prerequisites

- Xcode 12+
- iOS 14+ development target
- Apple Developer account
- Access to Apple's Screen Time and Family Sharing APIs

## Contributing

Please read the [Coding Standards](docs/architecture/coding-standards.md) before contributing to this project.

## License

This project is proprietary and confidential. All rights reserved.