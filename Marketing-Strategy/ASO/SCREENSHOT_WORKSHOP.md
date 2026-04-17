# App Store Screenshot Workshop
## Brain Coinz — Executable Playbook

**App:** Brain Coinz (`i6dev.ScreenTimeRewards`)
**Target:** 8 production-ready App Store screenshots at 1290×2796px
**References:**
- [`APP_STORE_SCREENSHOT_PLAN.md`](APP_STORE_SCREENSHOT_PLAN.md) — narrative story arc & view mapping
- [`APP_STORE_SCREENSHOT_PROMPTS.md`](APP_STORE_SCREENSHOT_PROMPTS.md) — AI image generation prompts

---

## Prerequisites

### 1. Install Adam Lyttle's ASO Screenshot Skill
```bash
claude install-skill github.com/adamlyttleapps/claude-skill-aso-appstore-screenshots
```

### 2. Python + Pillow
```bash
pip install Pillow
```

### 3. SF Pro Display Black Font
Download from [developer.apple.com/fonts](https://developer.apple.com/fonts) and install to:
```
/Library/Fonts/SF-Pro-Display-Black.otf
```

### 4. Gemini MCP (Recommended for AI Enhancement Phase)
Configure Gemini MCP in Claude Code settings — used for the AI polish step. Optional but produces significantly better headline overlays.

### 5. Simulator
- Open Xcode → Window → Devices and Simulators
- Add **iPhone 15 Pro Max** if not present
- Boot it before starting capture

---

## Simulator Setup

| Setting | Value |
|---------|-------|
| Device | iPhone 15 Pro Max (1290×2796) |
| Status bar time | 9:41 AM |
| Battery | Full (or hide status bar) |
| Appearance | Light Mode |
| Language | English |

**Set status bar time:**
```bash
# Boot simulator first, then:
xcrun simctl status_bar booted override --time "9:41"
```

**Test data to configure before capturing:**
- Time bank balance: **45 MIN AVAILABLE**
- Streak: **7 days**
- Learning apps: 3–4 with recognizable icons (Duolingo, Khan Academy, etc.)
- Reward apps: 3–4 (games, YouTube — use generic icons if needed)
- Usage values: realistic (e.g., "15 min earned today", not "999 min")

---

## Step 1 — Raw Screenshot Capture Checklist

Run the app on the iPhone 15 Pro Max simulator. Capture each screen with:
```bash
xcrun simctl io booted screenshot ~/Desktop/braincoinz_raw_N.png
```

Replace `N` with the screenshot number.

| # | Name | Screen to Navigate To | File Path | Notes |
|---|------|-----------------------|-----------|-------|
| 1 | THE HOOK | Child mode → Rewards tab → Time Bank visible | `Views/ChildMode/ChildDashboardView.swift` | Ensure `TimeBankCard` shows "45 MIN AVAILABLE" with full ring |
| 2 | EARN | Child mode → Learning tab | `Views/LearningTabView.swift` | Show 3+ learning apps with "X min earned today" |
| 3 | LEARN FIRST (shield) | Open reward app without completing learning goal | `ShieldConfigurationExtension/` | **Real device or triggered state required** — see shield capture instructions below |
| 4 | PAYOFF | Child mode → Rewards tab with time unlocked | `Views/RewardsTabView.swift` | Show apps as UNLOCKED, time available displayed |
| 5 | AUTO-LOCK (shield) | Exhaust all reward time, try to open reward app | `ShieldConfigurationExtension/` | **Real device or triggered state required** — see shield capture instructions below |
| 6 | HABITS | Parent mode → Dashboard → Streaks section visible | `Views/ParentMode/Components/StreaksSummarySection.swift` | Show "7 Day Streak" with flame icon |
| 7 | PARENT | Parent mode → Dashboard overview | `Views/ParentMode/ParentDashboardView.swift` | Show usage stats, time earned vs used, charts |
| 8 | CLOSE | Mode selection screen | `Views/ModeSelectionView.swift` | Show both Parent Space / Child Space cards clearly |

### Shield Screenshots (3 & 5) — Real Device Required

Screenshots 3 and 5 are iOS system-level shield overlays — they cannot be captured from the simulator.

**Screenshot 3 — Learning Goal Shield:**
1. On real device (child mode): configure a reward app (e.g., YouTube)
2. Ensure learning goal is **not** completed for the day
3. Tap the reward app to open it
4. System shield appears: "Learning Time First!" with teal background
5. Take screenshot via side button or `xcrun simctl io booted screenshot` if using device via Xcode

**Screenshot 5 — Time's Up Shield:**
1. On real device (child mode): earn some reward time, then use it all up
2. Alternatively: set available time to 1 minute, use it, then try to open a reward app
3. System shield appears: "Reward Time Finished" with orange background
4. Take screenshot

---

## Step 2 — compose.py Parameters (All 8 Screenshots)

`compose.py` assembles the raw screenshot into an App Store marketing image with headline text, background, and device frame.

**Basic invocation:**
```bash
python compose.py \
  --bg "#RRGGBB" \
  --verb "ACTION" \
  --desc "SUPPORTING TEXT" \
  --screenshot ~/Desktop/braincoinz_raw_N.png \
  --output ~/Desktop/braincoinz_composed_N.png
```

**Canvas:** 1290×2796px. Device frame: 1030px wide, positioned at Y=720.

### All 8 Invocations

**Screenshot 1 — THE HOOK**
```bash
python compose.py \
  --bg "#00A6A6" \
  --verb "REWARD" \
  --desc "SCREEN TIME, DON'T RESTRICT IT" \
  --screenshot ~/Desktop/braincoinz_raw_1.png \
  --output ~/Desktop/braincoinz_composed_1.png
```

**Screenshot 2 — EARN**
```bash
python compose.py \
  --bg "#E8F4FD" \
  --verb "EARN" \
  --desc "TIME WITH LEARNING APPS" \
  --screenshot ~/Desktop/braincoinz_raw_2.png \
  --output ~/Desktop/braincoinz_composed_2.png
```

**Screenshot 3 — ENFORCE (Learning Shield)**
```bash
python compose.py \
  --bg "#00A6A6" \
  --verb "LEARN" \
  --desc "FIRST, PLAY LATER" \
  --screenshot ~/Desktop/braincoinz_raw_3.png \
  --output ~/Desktop/braincoinz_composed_3.png
```

**Screenshot 4 — PAYOFF (Reward Apps)**
```bash
python compose.py \
  --bg "#FFB347" \
  --verb "UNLOCK" \
  --desc "YOUR FAVORITE APPS" \
  --screenshot ~/Desktop/braincoinz_raw_4.png \
  --output ~/Desktop/braincoinz_composed_4.png
```

**Screenshot 5 — AUTO-LOCK (Time's Up Shield)**
```bash
python compose.py \
  --bg "#FF6B6B" \
  --verb "AUTO-LOCK" \
  --desc "WHEN TIME'S UP" \
  --screenshot ~/Desktop/braincoinz_raw_5.png \
  --output ~/Desktop/braincoinz_composed_5.png
```

**Screenshot 6 — HABITS (Streaks)**
```bash
python compose.py \
  --bg "#1A365D" \
  --verb "BUILD" \
  --desc "HEALTHY SCREEN HABITS" \
  --screenshot ~/Desktop/braincoinz_raw_6.png \
  --output ~/Desktop/braincoinz_composed_6.png
```

**Screenshot 7 — PARENT (Dashboard)**
```bash
python compose.py \
  --bg "#FF8A80" \
  --verb "PARENTS" \
  --desc "STAY IN CONTROL" \
  --screenshot ~/Desktop/braincoinz_raw_7.png \
  --output ~/Desktop/braincoinz_composed_7.png
```

**Screenshot 8 — CLOSE (Mode Selection)**
```bash
python compose.py \
  --bg "#00A6A6" \
  --verb "ONE APP" \
  --desc "FOR THE WHOLE FAMILY" \
  --screenshot ~/Desktop/braincoinz_raw_8.png \
  --output ~/Desktop/braincoinz_composed_8.png
```

### Color Reference

| # | Name | Background | Purpose |
|---|------|------------|---------|
| 1 | THE HOOK | `#00A6A6` Teal | Brand-first, commands attention |
| 2 | EARN | `#E8F4FD` Light blue | Calm, educational feel |
| 3 | ENFORCE | `#00A6A6` Teal | Authority, matches shield color |
| 4 | PAYOFF | `#FFB347` Orange-yellow | Celebratory, reward emotion |
| 5 | AUTO-LOCK | `#FF6B6B` Coral-red | Urgency without being harsh |
| 6 | HABITS | `#1A365D` Deep navy | Aspiration, long-term trust |
| 7 | PARENT | `#FF8A80` Salmon | Warm authority, parent-appealing |
| 8 | CLOSE | `#00A6A6` Teal | Bookend with Screenshot 1 |

---

## Step 3 — Running the Skill End-to-End

The skill automates the full pipeline. Invoke via Claude Code after composing:

```bash
claude "Run the ASO App Store screenshots skill for Brain Coinz"
```

### What Each Phase Does

| Phase | What Happens |
|-------|-------------|
| **1. Benefit Discovery** | Skill reads the codebase to identify the app's core value props and maps them to screenshot slots |
| **2. Screenshot Pairing** | Matches each benefit to your raw `.png` files; prompts you if a screenshot is missing |
| **3. compose.py Scaffold** | Generates the compose.py invocations (you can use the ones above directly instead) |
| **4. AI Enhancement** | Uses Gemini MCP (or Claude's vision) to critique each composed image for readability, hierarchy, and message clarity |
| **5. Showcase** | Outputs a side-by-side preview of all 8 at thumbnail scale (how they appear in search results) |

**Tip:** Run Phases 1–3 manually using the parameters above for faster iteration. Use the skill primarily for Phase 4 (AI critique) and Phase 5 (thumbnail review).

---

## Step 4 — Review Checklist

Before exporting, verify all 8 against this checklist:

### Visual Quality
- [ ] Headline text readable at 150px thumbnail size (App Store search result size)
- [ ] Verb is noticeably larger/bolder than the supporting description
- [ ] No test data visible (no "999 min", no "[placeholder]", no dev UI flags)
- [ ] Status bar shows 9:41 AM and full battery on all simulator screenshots
- [ ] Device frame consistent across all 8 — iPhone 15 Pro Natural Titanium

### Narrative Arc
- [ ] Screenshot 1 creates curiosity ("REWARD screen time?")
- [ ] Screenshot 2 answers "how does it work?"
- [ ] Screenshot 3 shows enforcement (critical differentiator)
- [ ] Screenshot 4 delivers the payoff
- [ ] Screenshot 5 shows automatic limits (parents don't have to police)
- [ ] Screenshot 6 conveys long-term value (habits, not just blocking)
- [ ] Screenshot 7 addresses parent concerns (oversight, control)
- [ ] Screenshot 8 closes as a family solution (not just a kid app)

### App Store Compliance
- [ ] No pricing shown in screenshots
- [ ] No claims about reviews, rankings, or awards unless substantiated
- [ ] Shield screenshots (3 & 5) accurately represent the real shield UI

---

## Step 5 — Export & Upload

### Required Dimensions
| Size | Device | Required? |
|------|--------|-----------|
| 1290×2796 | iPhone 15 Pro Max (6.7") | **Required** |
| 1242×2688 | iPhone 11 Pro Max (6.5") | Strongly recommended (covers older devices) |

To export at 6.5" from the 6.7" composed images, resize with Pillow:
```python
from PIL import Image
img = Image.open("braincoinz_composed_1.png")
img_resized = img.resize((1242, 2688), Image.LANCZOS)
img_resized.save("braincoinz_6_5_1.png")
```

Or use `sips` (macOS built-in):
```bash
sips -z 2688 1242 braincoinz_composed_1.png --out braincoinz_6_5_1.png
```

### Upload to App Store Connect
1. App Store Connect → Your App → **App Store** tab
2. Select the iOS app version (current or new draft)
3. Under **iPhone Screenshots**, select **6.7-inch Display**
4. Drag all 8 files in order (1 → 8)
5. Repeat for **6.5-inch Display** with the resized set
6. Save — screenshots apply to all localizations unless overridden per locale

**Upload order:** Follow the narrative sequence: 1 Hook → 2 Earn → 3 Enforce → 4 Payoff → 5 Auto-Lock → 6 Habits → 7 Parent → 8 Close.

---

## Quick Reference

```
Raw capture:    xcrun simctl io booted screenshot ~/Desktop/braincoinz_raw_N.png
Compose:        python compose.py --bg "#HEX" --verb "VERB" --desc "TEXT" --screenshot raw.png --output composed.png
Skill:          claude "Run the ASO App Store screenshots skill for Brain Coinz"
Resize 6.5":    sips -z 2688 1242 composed.png --out resized.png
Upload:         App Store Connect → App Store → iPhone Screenshots
```
