# FloatList — Marketing Strategy

Scope: a realistic, low-budget go-to-market plan for a **solo designer/developer**
shipping a native macOS menu-bar todo app. Optimized for leverage, not reach.

---

## 1. Positioning

**One-liner**
> FloatList is the fastest way to capture a thought on macOS — a floating,
> glassy list that lives in your menu bar and disappears when you're done.

**Category anchor:** *menu-bar todo*, not "productivity app."
Don't compete with Things, Todoist, or TickTick on features. Compete on
*friction* and *feel*.

**Three-pillar narrative:**
1. **Always one hotkey away.** Global shortcut, no window management.
2. **Designed, not configured.** Liquid-glass panel, haptics, Dynamic-Island-style
   morphs — it feels like Apple shipped it.
3. **Gets out of the way.** Menu-bar-only, no dock icon, no account, no sync nag.

**Anti-positioning (what FloatList is NOT):**
- Not a project manager. No deadlines, assignments, or tags.
- Not cross-platform. macOS-native is the feature.
- Not cloud-first. Local-first is a selling point to the target audience.

---

## 2. Target audience

Rank in this order — don't dilute messaging across all of them at once:

1. **Apple-taste power users** — devs, designers, PMs who collect menu-bar
   utilities (Raycast, Shottr, Ice, CleanShot). They will pay for polish and
   tell their followers.
2. **Writers / researchers** who want a scratchpad for ideas without opening
   Notion.
3. **Students** on M-series MacBooks looking for free/cheap native apps.

Audience 1 is the wedge. They drive the others via word-of-mouth and screenshots.

---

## 3. Pricing & business model

Pick one and commit — don't launch undecided:

**Recommended: one-time purchase, $9.99 (intro) → $14.99.**
- Matches indie Mac norms (Ice donation-ware, Shottr $8, Bartender $16).
- No subscription fatigue for a utility this focused.
- Optional: "Pro" $19 one-time unlock later for sync / iOS companion.

Distribution: **Mac App Store first**, direct DMG later.
- MAS gets you discoverability and trust; no payments infra to build.
- Direct sale (Gumroad/Paddle) later when you want higher margin + email list.

Free tier: 7-day trial via TestFlight or a time-limited DMG.
Do NOT ship a freemium feature-gated version as a solo dev — it doubles support
load and weakens the product story.

---

## 4. Launch plan (90 days)

### Weeks -4 to 0 — Pre-launch
- Lock the name, icon, and one hero screenshot (the glassy panel over a desktop).
- Build a **single landing page**: hero video (8–12s silent loop), 3 feature
  screenshots, "Add to App Store" button, email capture.
  - Stack suggestion: Framer or a static site on Vercel. Don't build a CMS.
- Record a **15-second vertical demo** (hotkey → capture → swipe-complete).
  This one asset will carry the entire launch.
- Set up: Twitter/X, Bluesky, Mastodon (indieapps.space), a Threads account.
  Post build-in-public clips weekly, ~3 per week, 30 days before launch.
- Start a **waitlist** (Buttondown or ConvertKit free tier). Aim: 300+ emails
  before launch.
- Apply for MAS review with 2 weeks of buffer.

### Week 0 — Launch day (Tuesday, 9am PT)
Ship on all of these, same day, in order:
1. **Product Hunt** — schedule 24h ahead. Have first 10 comments lined up with
   friends/betas. Post the 15s demo as the top asset.
2. **Hacker News / Show HN** — title format: `Show HN: FloatList – a floating
   macOS menu-bar todo (native, no account)`. Post mid-morning ET.
3. **r/macapps, r/macOS, r/productivity** — different posts, each with the
   demo and a short "why I built this."
4. **X / Bluesky / Threads** — one thread per platform with the demo pinned.
5. **Email the waitlist** with a 25% launch discount code (if selling direct)
   or just the App Store link.

### Weeks 1–4 — Post-launch momentum
- **Reach out to 10 Apple-scene creators** personally (not a press blast):
  MacStories (Federico Viticci), 9to5Mac (app section), Basic Apple Guy,
  Parker Ortolani, Mike Rockwell (Initial Charge), Jason Snell (Six Colors),
  Nilay's The Vergecast if timing aligns, Tyler Stalman, Riley Testut, Kyle Hughes.
  Send a personal 4-sentence email + demo GIF + promo code. No press kit bloat.
- Submit to **directories**: alternativeto.net, Setapp (for later), Uses.tech
  listings, There's An AI For That (if any AI features), macapps.link, AppAgg.
- Ship a **1.1 update in week 3** with the top-3 requested things. Announce it
  — updates are free marketing and signal momentum.

### Weeks 5–12 — Compounding
- Start a small **monthly changelog newsletter**. Keep it short; people open it.
- Partner with 1–2 complementary menu-bar apps for a **cross-promo blurb** in
  each other's newsletters (Ice, Shottr, Raycast extensions, etc.).
- Write **one technical blog post** per month on something you actually did
  (e.g., "Building a Dynamic-Island-style morph with SwiftUI springs"). Post to
  your own site, cross-post to Hacker News. These age well.

---

## 5. Content & channels — what a solo person can sustain

Pick two channels and go deep; ignore the rest.

**Recommended two: X/Bluesky + YouTube Shorts (or TikTok).**

- **X/Bluesky**: build-in-public, reply to other indie devs, share polish
  clips. ~1 post/day, 2 substantive ones per week.
- **Short-form video**: 15–30s screen recordings set to music. The panel is
  visually distinctive — this is your unfair advantage. Aim for 2/week.

Do NOT try to run: a podcast, a Discord community, a blog with weekly cadence,
and a YouTube long-form channel. You'll burn out by month 3.

**Asset production rule:** every new feature must ship with a ≤15s demo clip.
If it doesn't have a clip, it didn't ship. This builds a library of marketing
over time with zero extra effort.

---

## 6. Metrics that actually matter

For a solo app, track 4 numbers weekly in a single spreadsheet:

1. **Paying users this week** (or downloads if free).
2. **Waitlist / email subscribers.**
3. **Active users** (anonymous heartbeat ping, opt-in).
4. **Refund rate.** >3% means the landing page oversells.

Ignore: DAU/MAU ratios, NPS, funnel dashboards. Overkill at this scale.

---

## 7. Risks & mitigations

| Risk | Mitigation |
| --- | --- |
| Launch day flops on Product Hunt | Stagger channels across 2 weeks instead of one-shot. HN and MacStories can work months after PH. |
| Apple rejects the nonactivating panel behavior at MAS review | Have a direct-DMG fallback ready on day one. |
| Feature-request firehose drowns solo dev | Public roadmap (one Notion/Linear page). Say "not now" clearly. |
| You get bored | Pre-commit to 90 days of public building before judging success. |

---

## 8. 12-month direction

Only pursue if months 1–3 show signal (>500 paying users or >2k waitlist):

- **iOS companion + iCloud sync** → unlocks a Pro upgrade tier.
- **Setapp submission** → steady monthly revenue, lower marketing burden.
- **Shortcuts + URL scheme** → Raycast/Alfred integrations, which
  power-user communities love to share.
- **Team licensing** only if inbound asks for it. Don't chase B2B solo.

---

## 9. First-week action checklist

- [ ] Lock positioning one-liner (Section 1)
- [ ] Record the 15-second hero demo
- [ ] Put up landing page + waitlist
- [ ] Schedule Product Hunt launch
- [ ] Draft 10 personal outreach emails to Apple-scene creators
- [ ] Write the Show HN post and the r/macapps post
- [ ] Decide pricing and submit to MAS review
