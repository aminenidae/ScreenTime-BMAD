# Website Design Guide: ScreenTime Rewards
**Target URL:** `www.i6dev.ca/screentimerewards/`
**Host:** i6dev.ca (Existing site, new subdirectory)
**Status:** Design Draft
**App Name:** ScreenTime Rewards

---

## 1. Project Overview & Strategy
**Product:** An iOS parental control app that gamifies screen time. Children earn screen time by using educational apps and "pay" to use entertainment apps.
**Target Audience:** Parents concerned about their children's device usage, looking for a positive reinforcement tool rather than just strict blocking.
**Core Value Proposition:** "Turn Screen Time into Learning Time."
**Monetization:** Freemium with Subscription (Monthly Individual & Family Plans).

### Technical Requirements
*   **Hosting:** The site must live in a subdirectory: `/screentimerewards/`.
*   **Responsive:** Mobile-first design (parents will likely visit from their iPhones).
*   **Performance:** Fast loading, optimized images (app screenshots).
*   **Navigation:** Global navigation should be consistent within the subdirectory context.

---

## 2. Site Structure (Sitemap)

The website will consist of the following pages:

1.  **Home / Landing Page** (`/screentimerewards/`)
2.  **Features & How it Works** (Can be a section on Home or separate page `/screentimerewards/features`)
3.  **Support & FAQ** (`/screentimerewards/support`)
4.  **Privacy Policy** (`/screentimerewards/privacy`)
5.  **Terms of Service** (`/screentimerewards/terms`)

---

## 3. Visual Identity (Branding)
*   **Color Palette:** Match the app's iOS design.
    *   **Primary (Learning):** Vibrant Blue (e.g., System Blue / Teal) - Represents education, focus.
    *   **Secondary (Rewards):** Playful Orange/Coral - Represents fun, games, rewards.
    *   **Backgrounds:** Clean White or very light gray (`#F5F5F7` - Apple style).
    *   **Text:** Dark Slate / Black for high contrast.
*   **Typography:** San Francisco (SF Pro) or a close web alternative (Inter, Roboto, system-ui) to maintain that "Native iOS" feel.
*   **Tone:** Encouraging, Safe, Trustworthy, Modern.

---

## 4. Page-by-Page Requirements

### A. Landing Page (`index.html`)
**Goal:** Convert visitors to App Store downloads.

*   **Hero Section:**
    *   **Headline:** "Turn Screen Time into Learning Time."
    *   **Subheadline:** "The parental control app that rewards your child for using educational apps."
    *   **CTA:** Large "Download on the App Store" badge (SVG).
    *   **Visual:** High-quality iPhone mockups showing the "Learning" vs "Rewards" split view.
*   **Feature Highlights (The "Why"):**
    *   *Gamified Balance:* "Kids earn points by reading or learning, then spend them on games."
    *   *Remote Monitoring:* "Check usage and assign apps from your own phone via iCloud."
    *   *Privacy First:* "Built with Apple's Screen Time API. Your data never leaves your iCloud."
*   **Social Proof:** Placeholder for parent testimonials ("Changed how my kids view their iPad!").
*   **Footer:** Links to Privacy, Terms, Support, Contact.

### B. Privacy Policy (`privacy.html`)
**Goal:** Satisfy Apple's App Store requirements and build trust.

*   **Critical Content:**
    *   **Screen Time API:** Explicitly state that usage data is processed *on-device* or synced via *private CloudKit container*. The developer does *not* see which apps are used.
    *   **Data Collection:** No personal data selling.
    *   **Children's Privacy:** Compliance with COPPA/GDPR-K (since it's a kids' app).
    *   **Account Deletion:** Instructions on how to clear data (e.g., "Deleting the app removes local data; iCloud data can be managed in iOS Settings").

### C. Terms of Service (`terms.html`)
**Goal:** Legal protection and Subscription details.

*   **Subscription Terms:**
    *   Details on "Individual" ($7.99/mo) and "Family" ($12.99/mo) plans.
    *   Free Trial duration (30 days).
    *   Auto-renewal and cancellation policies (Standard Apple EULA reference).
*   **Usage:** Rules against reverse engineering, etc.

### D. Support / FAQ (`support.html`)
**Goal:** Reduce support emails and help with setup.

*   **Common FAQs to draft:**
    *   *Why can't I see the specific apps my child used?* (Answer: Apple Privacy restrictions hide app names unless configured specifically).
    *   *How do I pair a child device?* (Step-by-step guide with screenshots).
    *   *What happens when the trial ends?*
    *   *My child's game isn't blocking. Why?* (Answer: "If the app was already open, they may need to restart it once for the shield to activate.")
*   **Contact:** Email link (`support@i6dev.ca` or similar).

---

## 5. Implementation Notes for Web Dev Agent
1.  **Framework:** Use a lightweight Static Site Generator (SSG) or simple HTML/Tailwind CSS. Do not overengineer with heavy frameworks unless necessary for the main site.
2.  **Assets:**
    *   You will need to generate or request "App Store" badges.
    *   Use generic placeholders for iPhone frames until actual screenshots are provided.
3.  **Copy:** Use the text provided in the "Page-by-Page" section as the initial content.
4.  **Routing:** Ensure all links are relative or absolute to `/screentimerewards/` to avoid breaking when deployed to the subdirectory.

---
**Next Steps:**
Pass this guide to the Web Developer Agent to begin coding the static pages.
