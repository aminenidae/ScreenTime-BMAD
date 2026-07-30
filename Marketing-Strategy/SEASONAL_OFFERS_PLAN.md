# Seasonal Limited-Time Offers — Plan

**Status:** Not started. Blocked until 1.0.9 (3) is approved and live.
**Written:** 2026-07-29
**Owner:** CEO decides the offer; engineering wires the display.

---

## The one rule that shapes everything

**The discount must come from App Store Connect. The app can only describe it.**

There is no way to apply a real discount from our code. Showing "40% off" while Apple
charges full price is deceptive and is a rejection under App Review 2.3.1 — and it
generates refund requests, which is worse than the rejection.

So every plan below splits the same way: Apple owns the money, we own the story.

---

## Prerequisite: consolidate the subscription groups first

**This is a blocker, not a nice-to-have.**

A customer is eligible for one introductory offer **per subscription group**. We currently
ship three groups. So the same parent could claim the same seasonal discount three separate
times — once per group.

Consolidating the three groups into one is already on the pre-launch list for compliance
reasons. This is a second, commercial reason to do it. Do not run a promotion before it is
done.

---

## What we get for free once the 14-day Apple trial is removed

Every subscription has exactly one introductory-offer slot per customer. Today that slot
holds Apple's 14-day free trial, which is being removed after this build ships (the app
grants its own 14 days from the Keychain — nothing to do with Apple).

Once removed, **the slot is empty and available for a seasonal price discount.** That is
the whole mechanism. It also means the two can never collide.

And the pitch that results is stronger than the competitor's:

> **14 days free — then 40% off your first year.**

They lead with a discount and no trial. We would lead with both, and both would be true.

---

## Step 1 — Set the offer up in App Store Connect

For each subscription in the (single, consolidated) group:

1. Open the subscription → **Introductory Offers** → add one
2. Choose **Pay Up Front** (annual) or **Pay As You Go** (monthly) — not Free Trial
3. Set the offer price, e.g. Family annual $29.99 instead of $49.99
4. Set a **start date and an end date** — this is what makes it genuinely limited. Apple
   stops offering it when the window closes; there is nothing for us to remember to
   switch off
5. Choose territories — worth running US + Canada first, matching where the ad spend is

Eligibility is automatic: Apple only shows it to people who have never subscribed in that
group. We do not check anything ourselves.

### Sensible windows

| Campaign | Window | Note |
|---|---|---|
| Back to School | early Aug → mid Sep | Strongest fit for a parental-control app |
| New Year | 26 Dec → mid Jan | "New year, new screen-time habits" |
| Summer | mid Jun → end Jul | Weaker — screen-time anxiety is lower in holidays |

Pick one per year to start. See the eligibility trap below for why not all three.

---

## Step 2 — App-side work

Roughly half a day, mostly copy and French. Our paywall currently reads prices from the
store but knows nothing about offers, so this is new.

- **Read the offer from Apple, never hardcode it.** RevenueCat exposes the introductory
  offer on the store product. Same principle as `annualSavingsPercent` today: if the
  number is calculated from the store, it can never go stale or contradict what the
  customer is actually charged.
- **`Views/Subscription/PromoBadge.swift`** — already the single sticker style. A seasonal
  badge is a new string through the existing component, not a new component.
- **Show the standard price struck through** next to the offer price. This is the one
  genuinely persuasive thing the competitor does that we should copy. It must be the real
  standard price pulled from the store.
- **`Views/Subscription/SubscriptionDisclosureText.swift`** — single source of the legal
  fine print. It must state the offer price, the offer duration, **and** the price it
  renews at. Guideline 3.1.2. One file to change, by design.
- **Season name** — "Back to School offer" as a heading on the paywall, plus the trial
  banner if the offer is running. Needs French.
- **Hide all of it when no offer is live.** The paywall must read correctly with the offer
  absent, because that is its state most of the year.

### A countdown timer is allowed — if it is honest

A competitor shows "02 DAY : 23 HR : 59 MIN : 58 SEC", which is three days minus two
seconds and almost certainly resets on every visit. That is a dark pattern and a
rejection risk.

Counting down to the **real end date configured in ASC** is legitimate and we may do it.
The rule: if the customer closes the app and reopens it an hour later, the timer must be
an hour shorter. If we cannot guarantee that, ship no timer.

Also worth remembering the audience: we are asking a parent to trust us with their child's
phone. Manufactured urgency undercuts the thing we are actually selling.

---

## The eligibility trap: one offer per customer, ever

An introductory offer only reaches people who have **never** subscribed in that group. So:

- A parent who takes the Back to School offer is **not** eligible for New Year
- We cannot run a rolling series of discounts at the same audience
- Introductory offers are an **acquisition** tool only

Discounting to existing or lapsed customers needs different Apple tools — **promotional
offers** (requires server-side signature signing, meaningfully more work) or **win-back
offers** (iOS 18+, Apple surfaces them on the App Store). Both are separate projects.
Do not promise a retention campaign on the back of this work.

---

## What to measure

The analytics funnel is already wired and labelled per user (`onboarding_funnel`), and
RevenueCat is joined to Firebase. What is missing for a promo is the ability to tell
offer-takers from full-price buyers.

- Add the offer identifier as a RevenueCat attribute at purchase, so BigQuery can split
  the two cohorts
- The number that matters is **not** conversion during the window. It is **renewal at
  full price 12 months later.** A discount that buys subscribers who all churn at renewal
  has cost us money and taught us nothing
- Compare against the same weeks unpromoted, if we have them

---

## Ordering

1. 1.0.9 (3) approved and live
2. Remove Apple's 14-day introductory offers in ASC (already decided)
3. Consolidate the three subscription groups into one
4. Configure the seasonal introductory offer with real dates
5. App-side display work, French included
6. Ship as 1.1.0, ahead of the campaign window
7. Only then start the ad spend against it

**Do not start step 4 before step 3.** Changing products underneath a binary in review is
also worth avoiding — hence step 1 first.
