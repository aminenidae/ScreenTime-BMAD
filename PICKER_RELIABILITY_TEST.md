# Picker Reliability Test Checklist

**Purpose:** Verify picker timeout detection and error handling work correctly
**Date Created:** 2025-10-16
**Priority:** 🔴 HIGH - Addresses remote view connection crashes from community research

---

## Test Preparation

### Prerequisites
- [ ] Build succeeds without errors
- [ ] Physical iOS device connected
- [ ] Screen Time permission granted (or ready to grant)
- [ ] Xcode console open and visible

### Build and Deploy
```bash
# Clean build
cd ScreenTimeRewardsProject
xcodebuild clean -project ScreenTimeRewards.xcodeproj -scheme ScreenTimeRewards

# Build and run on device
# (Use Xcode: Product → Run on your device)
```

---

## Test Suite 1: Normal Picker Operation

### Test 1.1: Picker Opens Successfully
**Goal:** Verify picker opens normally without timeout

**Steps:**
1. Launch app
2. Tap slider icon (top right)
3. Grant authorization if prompted
4. Wait for FamilyActivityPicker to appear
5. Select 3-5 apps within 10 seconds
6. Tap Done

**Expected Results:**
- ✅ Picker opens within 2-3 seconds
- ✅ No timeout alert appears
- ✅ Apps are selected successfully
- ✅ Category assignment sheet opens automatically

**Console Logs to Check:**
```
[AppUsageViewModel] Starting picker timeout timer (15.0 seconds)
[AppUsageViewModel] Picker selection changed - cancelling timeout
[AppUsageViewModel] Cancelled picker timeout timer
```

**Status:** [ ] PASS / [ ] FAIL
**Notes:**

---

### Test 1.2: Picker Opened Multiple Times
**Goal:** Verify timeout handling across multiple picker sessions

**Steps:**
1. Open picker (slider icon)
2. Select apps and complete
3. Reset selection (Reset Data button)
4. Open picker again
5. Select different apps
6. Repeat 5-10 times

**Expected Results:**
- ✅ Each picker session works independently
- ✅ Timeout timer resets each time
- ✅ No memory leaks (app stays responsive)
- ✅ Retry count resets on successful selection

**Console Logs Pattern:**
```
[AppUsageViewModel] Starting picker timeout timer (15.0 seconds)
[AppUsageViewModel] Picker selection changed - cancelling timeout
[Repeat for each session]
```

**Test Attempts:**
1. [ ] Attempt 1 - PASS/FAIL
2. [ ] Attempt 2 - PASS/FAIL
3. [ ] Attempt 3 - PASS/FAIL
4. [ ] Attempt 4 - PASS/FAIL
5. [ ] Attempt 5 - PASS/FAIL
6. [ ] Attempt 6 - PASS/FAIL
7. [ ] Attempt 7 - PASS/FAIL
8. [ ] Attempt 8 - PASS/FAIL
9. [ ] Attempt 9 - PASS/FAIL
10. [ ] Attempt 10 - PASS/FAIL

**Status:** [ ] PASS (all attempts) / [ ] FAIL (some failures)
**Failure Rate:** ___%
**Notes:**

---

## Test Suite 2: Timeout Detection

### Test 2.1: Deliberate Timeout Trigger
**Goal:** Verify timeout alert appears after 15 seconds of inactivity

**Steps:**
1. Open picker (slider icon)
2. Grant authorization
3. When picker appears, **DO NOT** select any apps
4. Wait for 15+ seconds
5. Watch for timeout alert

**Expected Results:**
- ✅ Alert appears at ~15 seconds
- ✅ Alert title: "Picker Issue Detected"
- ✅ Alert message includes troubleshooting steps
- ✅ Alert shows "Retry attempt: 1"
- ✅ Two buttons available: "Retry" and "Cancel"

**Console Logs:**
```
[AppUsageViewModel] Starting picker timeout timer (15.0 seconds)
[AppUsageViewModel] ⚠️ Picker timeout triggered - no apps selected after 15.0 seconds
```

**Status:** [ ] PASS / [ ] FAIL
**Actual timeout duration:** _____ seconds
**Notes:**

---

### Test 2.2: Timeout Recovery via Retry
**Goal:** Verify retry button re-opens picker successfully

**Steps:**
1. Trigger timeout (wait 15 seconds without selecting)
2. When alert appears, tap "Retry"
3. Wait for picker to reopen
4. This time, select 2-3 apps quickly
5. Tap Done

**Expected Results:**
- ✅ Picker closes and reopens within 1 second
- ✅ Retry count increments to 2
- ✅ Timeout timer resets to 15 seconds
- ✅ Apps can be selected successfully
- ✅ Category assignment proceeds normally

**Console Logs:**
```
[AppUsageViewModel] Retrying picker open (attempt 1)
[AppUsageViewModel] Starting picker timeout timer (15.0 seconds)
[AppUsageViewModel] Picker selection changed - cancelling timeout
```

**Status:** [ ] PASS / [ ] FAIL
**Notes:**

---

### Test 2.3: Timeout Cancellation
**Goal:** Verify cancel button dismisses picker without crash

**Steps:**
1. Trigger timeout (wait 15 seconds without selecting)
2. When alert appears, tap "Cancel"
3. Verify picker closes
4. Try opening picker again

**Expected Results:**
- ✅ Picker closes immediately
- ✅ App remains responsive
- ✅ Can open picker again successfully
- ✅ Retry count resets to 0 on next successful selection

**Status:** [ ] PASS / [ ] FAIL
**Notes:**

---

### Test 2.4: Multiple Timeout Retries
**Goal:** Verify retry mechanism works across multiple attempts

**Steps:**
1. Open picker, wait for timeout (15 sec)
2. Tap "Retry", wait for timeout again (15 sec)
3. Tap "Retry", wait for timeout again (15 sec)
4. Tap "Retry", this time select apps

**Expected Results:**
- ✅ Alert shows "Retry attempt: 1" on first timeout
- ✅ Alert shows "Retry attempt: 2" on second timeout
- ✅ Alert shows "Retry attempt: 3" on third timeout
- ✅ Successful selection resets retry count to 0

**Console Logs:**
```
[AppUsageViewModel] Retrying picker open (attempt 1)
[AppUsageViewModel] Retrying picker open (attempt 2)
[AppUsageViewModel] Retrying picker open (attempt 3)
[AppUsageViewModel] Picker selection changed - cancelling timeout
```

**Status:** [ ] PASS / [ ] FAIL
**Retry count behavior:** [ ] Correct / [ ] Incorrect
**Notes:**

---

## Test Suite 3: Edge Cases

### Test 3.1: Rapid Picker Open/Close
**Goal:** Verify timeout handling when picker is opened and closed quickly

**Steps:**
1. Open picker
2. Immediately dismiss (swipe down or tap outside)
3. Open picker again
4. Dismiss again
5. Repeat 5 times
6. On 6th attempt, actually select apps

**Expected Results:**
- ✅ No spurious timeout alerts
- ✅ Timeout timer cancels on dismiss
- ✅ App remains stable
- ✅ Final selection works correctly

**Status:** [ ] PASS / [ ] FAIL
**Notes:**

---

### Test 3.2: Background/Foreground During Picker
**Goal:** Verify timeout handling when app goes to background

**Steps:**
1. Open picker
2. While picker is open (before timeout), press home button
3. Wait 10 seconds
4. Reopen app
5. Observe picker state

**Expected Results:**
- ✅ Picker may close or remain open (platform behavior)
- ✅ If picker remains open, timeout continues counting
- ✅ No crash or freeze
- ✅ User can dismiss and retry

**Status:** [ ] PASS / [ ] FAIL
**Picker state on return:** [ ] Open / [ ] Closed
**Notes:**

---

### Test 3.3: Low Memory Conditions
**Goal:** Verify timeout handling under memory pressure

**Steps:**
1. Open several memory-intensive apps (Photos, Safari with many tabs)
2. Return to ScreenTimeRewards
3. Open picker
4. Wait for timeout or select apps

**Expected Results:**
- ✅ Picker loads (may be slower)
- ✅ Timeout timer works correctly
- ✅ No memory-related crashes
- ✅ Selection completes successfully

**Status:** [ ] PASS / [ ] FAIL
**Notes:**

---

### Test 3.4: Authorization Denied Then Granted
**Goal:** Verify timeout when authorization flow is interrupted

**Steps:**
1. If authorization already granted, revoke in Settings → Screen Time
2. Open picker (will request authorization)
3. Deny authorization
4. Try opening picker again
5. This time, grant authorization
6. Wait for picker, select apps

**Expected Results:**
- ✅ First attempt shows authorization error (not timeout)
- ✅ Second attempt opens picker successfully
- ✅ Timeout timer starts after authorization granted
- ✅ Selection works normally

**Status:** [ ] PASS / [ ] FAIL
**Notes:**

---

## Test Suite 4: Real-World Remote View Failure Simulation

### Test 4.1: Screen Time Disabled
**Goal:** Simulate system configuration that might cause picker failure

**Steps:**
1. Go to Settings → Screen Time
2. Disable Screen Time completely
3. Return to app
4. Try opening picker

**Expected Results:**
- ✅ Authorization request appears
- ✅ If authorization fails, appropriate error shown (not timeout)
- ✅ App doesn't crash

**Status:** [ ] PASS / [ ] FAIL
**Error message shown:**
**Notes:**

---

### Test 4.2: Network Offline
**Goal:** Verify picker works offline (shouldn't need network)

**Steps:**
1. Enable Airplane Mode
2. Open picker
3. Select apps

**Expected Results:**
- ✅ Picker opens successfully (FamilyControls is local)
- ✅ App selection works
- ✅ No network-related errors
- ✅ Timeout detection still functions

**Status:** [ ] PASS / [ ] FAIL
**Notes:**

---

### Test 4.3: Device Restart
**Goal:** Verify picker works after device restart

**Steps:**
1. Complete app selection and configuration
2. Restart device
3. Launch app
4. Try opening picker again
5. Select different apps

**Expected Results:**
- ✅ Picker opens normally after restart
- ✅ No stale state issues
- ✅ Timeout detection works
- ✅ Selection completes successfully

**Status:** [ ] PASS / [ ] FAIL
**Notes:**

---

## Summary & Results

### Overall Statistics

**Total Tests:** 14
**Tests Passed:** ____
**Tests Failed:** ____
**Success Rate:** ____%

### Picker Reliability Metrics

**Normal Operation:**
- Open success rate: ____% (out of 10+ attempts)
- Average open time: ____ seconds
- Failures encountered: ____

**Timeout Detection:**
- Timeout triggers correctly: [ ] YES / [ ] NO
- Timeout duration accuracy: ±____ seconds
- Retry mechanism works: [ ] YES / [ ] NO

**Error Handling:**
- Alert displays correctly: [ ] YES / [ ] NO
- Retry button works: [ ] YES / [ ] NO
- Cancel button works: [ ] YES / [ ] NO
- Error messages helpful: [ ] YES / [ ] NO

### Known Issues Discovered

1. **Issue:**
   **Frequency:**
   **Severity:**
   **Workaround:**

2. **Issue:**
   **Frequency:**
   **Severity:**
   **Workaround:**

3. **Issue:**
   **Frequency:**
   **Severity:**
   **Workaround:**

---

## Recommendations

### Immediate Actions Required

1. [ ] **Action:**
   **Reason:**
   **Priority:**

2. [ ] **Action:**
   **Reason:**
   **Priority:**

### Future Improvements

1. [ ] **Improvement:**
   **Benefit:**

2. [ ] **Improvement:**
   **Benefit:**

---

## Test Sign-Off

**Tester Name:** __________________
**Date Completed:** __________________
**iOS Version:** __________________
**Device Model:** __________________

**Overall Assessment:** [ ] PASS - Picker reliable / [ ] FAIL - Issues found / [ ] CONDITIONAL PASS - Minor issues

**Recommendation:** [ ] Proceed to ManagedSettings testing / [ ] Fix picker issues first / [ ] Needs further investigation

**Notes:**

---

## Next Steps

Based on test results:

### If ALL TESTS PASS:
✅ Proceed to **Task 2: ManagedSettings Blocking Implementation**
- Create ManagedSettings test suite
- Implement app blocking functionality
- Test dynamic unlocking

### If SOME TESTS FAIL:
⚠️ Review failures and determine:
- Are failures reproducible?
- Are they showstoppers or minor issues?
- Can we proceed with ManagedSettings testing in parallel?

### If MAJOR FAILURES:
🔴 Address critical issues before proceeding:
- Document failure patterns
- Investigate root cause
- Consider alternative picker strategies
