# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.


When talking to me, don't use technical jargon! I'm not a programmer! I'm the CEO of the company, and I'm interested in the bottom line. Use simple language that anyone can understand. For example, instead of saying: "3. Ratio change applied immediately — versioning gap on the live path                                                                   
   
  decideEffectiveFromDay (AppScheduleService.swift:289) does the right thing on write: if usage_<id>_today > 0, the new version is        
  recorded with effectiveFromDay = tomorrow. So versions[ACCE5205] correctly has 1:10 for today and 1:1 starting tomorrow.
                                                                                                                                          
  The bug: nobody on the today path consults versionActive. Both readers go to the current schedule:                                      
  - Extension: computeEffectivePoolBalance builds ratioByLearningID from linked.rewardMinutesEarned / linked.ratioLearningMinutes
  (DeviceActivityMonitorExtension.swift:1675).                                                                                            
  - Main app: AppUsageViewModel lines 139, 227, 270 — schedule.rewardMinutesEarned / schedule.ratioLearningMinutes.
                                                                                                                                          
  saveSchedule also calls syncGoalConfigsToExtension() immediately after the save, which rewrites the extension's goal config with the new
   ratio. So today's live calc switches to 1:1 the moment you save, dropping 24×10=240 to 24×1=24.                                        
                                                                                                                                          
  versionActive(logicalID, on: today) is only used inside getHistoricalRemainingMinutes() — i.e., for dailyHistory rows that have already 
  rolled over. Today never goes through it.              
                                                                                                                                          
  You're not wrong about the intent — the implementation just doesn't honor it for today. Fix is to route the live todayEarned ratio      
  through versionActive(on: todayKey) instead of reading the current schedule directly. Same change in three places (extension
  computeEffectivePoolBalance, AppUsageViewModel × ~3 sites). Want me to sketch the patch?", you rather say: "3. Why the ratio change dropped today's earnings

  Good news first: the save side is correct. When you change the ratio while there's already usage today, the app records the new ratio as
   effective tomorrow and keeps today pinned to the old ratio. That table is right.

  Bad news: nothing reads it for today. The "what did I earn today?" calculation still looks up the current ratio on the schedule, not the
   historically-pinned one. And right after you save, the new ratio gets pushed straight to the extension. So today's calc instantly
  switches from 1:10 to 1:1 → 24 × 10 = 240 collapses to 24 × 1 = 24.

  The intent (today stays at the old ratio, new ratio takes over tomorrow) is in place. The piece that uses that intent on today's live
  calc was never wired up. Past days correctly use it, today doesn't.

  Fix is small — three places where today's calc reads the current ratio need to instead ask "what was the ratio active for today?" Want me to write it up?"
