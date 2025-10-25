# Task M Validation Test Plan
**Date:** 2025-10-25
**Project:** ScreenTime-BMAD / ScreenTimeRewards
**Author:** Code Agent

## Overview
This document outlines the validation test plan for Task M fixes to ensure proper state management and picker stability. The tests will verify that all the requirements have been met and that the cross-category data loss issue has been resolved.

## Test Objectives
1. Verify that familySelection is properly rehydrated from masterSelection after every save and before launching any picker
2. Confirm that orphaned Application entries are properly trimmed so updateSnapshots() ignores them
3. Ensure the masterSelection = familySelection assignment remains removed
4. Validate that the .familyActivityPicker completion properly logs errors, performs one retry after a full state reset, and surfaces a user-facing message if the retry fails
5. Confirm that the reward → learning picker sequence works correctly with both categories intact

## Test Environment
- Device: iPhone or iPad running iOS 16.6+
- Xcode 15.0+
- ScreenTimeRewards project build

## Test Cases

### Test Case 1: State Rehydration Verification
**Objective:** Verify that familySelection is properly rehydrated from masterSelection

**Steps:**
1. Launch the app
2. Add apps to both Learning and Reward categories
3. Save the configuration
4. Check console logs for "Rehydrating familySelection from masterSelection"
5. Open the Learning picker and verify that Reward apps are still present
6. Open the Reward picker and verify that Learning apps are still present

**Expected Results:**
- ✅ familySelection is rehydrated from masterSelection after every save
- ✅ Both categories persist when switching between pickers
- ✅ No "Skipping orphaned token" messages in console

### Test Case 2: Orphaned Application Entry Trimming
**Objective:** Confirm that orphaned Application entries are properly trimmed

**Steps:**
1. Add apps to both Learning and Reward categories
2. Save the configuration
3. Remove an app from one category
4. Check console logs for "Skipping orphaned token" messages
5. Verify that the removed app no longer appears in snapshots
6. Open the picker for the opposite category and verify apps are still present

**Expected Results:**
- ✅ Orphaned tokens are properly identified and skipped
- ✅ Removed apps do not appear in snapshots
- ✅ Apps in the opposite category remain intact

### Test Case 3: MasterSelection Assignment Verification
**Objective:** Ensure the masterSelection = familySelection assignment remains removed

**Steps:**
1. Review the onCategoryAssignmentSave() method in AppUsageViewModel.swift
2. Confirm that the line "masterSelection = familySelection" is commented out or removed
3. Add apps to both categories and save
4. Verify that apps from both categories persist after save

**Expected Results:**
- ✅ The problematic line is removed or commented out
- ✅ Apps from both categories persist after save operations

### Test Case 4: FamilyActivityPicker Error Handling
**Objective:** Validate error handling and retry mechanism

**Steps:**
1. Force a FamilyActivityPicker error (if possible) or simulate one
2. Check console logs for error detection and handling
3. Verify that one retry attempt is made
4. Confirm that a user-facing error message is displayed if retry fails

**Expected Results:**
- ✅ Errors are properly logged and detected
- ✅ One retry attempt is made with full state reset
- ✅ User-facing error message is displayed if retry fails

### Test Case 5: Reward → Learning Picker Sequence
**Objective:** Confirm that the reward → learning picker sequence works correctly

**Steps:**
1. Add apps to Reward category and save
2. Immediately open the Learning picker
3. Verify that Reward apps are still present in the selection
4. Add apps to Learning category and save
5. Check that both categories remain intact
6. Capture .xcresult file for verification

**Expected Results:**
- ✅ Reward apps persist when opening Learning picker
- ✅ Learning apps can be added without affecting Reward apps
- ✅ Both categories remain intact after save operations
- ✅ .xcresult file shows both categories intact

## Test Data Collection
- Console logs with debug statements
- .xcresult files for each test case
- Screenshots showing app states before and after operations
- Verification of code changes in AppUsageViewModel.swift

## Success Criteria
All test cases must pass with the following criteria:
- ✅ No cross-category data loss
- ✅ Proper state rehydration
- ✅ Orphaned token handling
- ✅ Error handling and retry mechanism
- ✅ Both categories persist through picker operations

## Test Execution Schedule
- Test Case 1: State Rehydration Verification - 30 minutes
- Test Case 2: Orphaned Application Entry Trimming - 30 minutes
- Test Case 3: MasterSelection Assignment Verification - 15 minutes
- Test Case 4: FamilyActivityPicker Error Handling - 45 minutes
- Test Case 5: Reward → Learning Picker Sequence - 30 minutes

## Test Results Documentation
Test results will be documented in:
- Console log captures
- .xcresult files
- Screenshots of app states
- Updated DEVELOPMENT_PROGRESS.md with test results

## Risk Mitigation
- If errors occur, review console logs for specific error messages
- If picker issues persist, verify that all state reset methods are properly implemented
- If cross-category data loss continues, double-check the familySelection rehydration logic