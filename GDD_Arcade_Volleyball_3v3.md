# Game Design Document
## "SPIKE ZONE" — 2D Arcade Volleyball (3v3)

---

## 1. High Concept

A fast-paced, arcade-style 2.5D volleyball game where two teams of three battle across a side-view court. Matches are short, readable, and punchy — closer to a fighting game in pacing than a sports sim. The core hook is the **Awakening** system: rallies build tension and speed until a critical hit triggers a slow-motion "Zone Perception" state where the game rewards precision over reflex.

**Pillars:**
- **Readable chaos** — even at high speed, players always know who's hitting, where the ball is going, and whose turn it is to touch it.
- **Role identity over generic stats** — a Setter should never feel replaceable by a Spiker.
- **Earned slowdown** — Zone Perception is a reward state you build toward, not a random gimmick.

---

## 2. Match Structure

- **Format:** 3v3, best of 3 sets, first to 15 points (win by 2), cap at 21.
- **Court:** Single-screen side view, net in the center, 3 player slots per side (Front, Mid, Back — mapped loosely to role, not rigid position lock).
- **Session length target:** 3–5 minutes per set, 10–15 minutes per match. This is an arcade game — nothing should require a bathroom break.

---

## 3. Player Roles

Each team fields exactly one of each role. No duplicate roles — this is a hard rule, not a soft suggestion, because it's what makes team comp and Synergy Traits (see doc #7) meaningful.

### 3.1 Setter
- **Identity:** The playmaker. Weak offense, strong ball control.
- **Core Stats (baseline, 1–10 scale):** Power 3 / Accuracy 9 / Speed 6 / Reach 5
- **Special Action — "Dime Set":** When a Setter performs the 2nd touch, they get a brief input window to redirect the ball to any teammate with near-perfect placement accuracy, rather than the default "nearest teammate" auto-target.
- **Passive:** Reduces the "drop-off" accuracy penalty that normally applies to off-angle receives.
- **Fantasy:** The player who makes everyone else look good.

### 3.2 Spiker
- **Identity:** The finisher. High power, built to end rallies.
- **Core Stats:** Power 9 / Accuracy 5 / Speed 7 / Reach 6
- **Special Action — "Finish Spike":** A charged 3rd-touch attack. Holding the attack input charges a power meter; releasing at the apex of the jump triggers a high-velocity smash with a VFX payoff (see doc #4). Uncharged spikes are weaker but faster to execute — a risk/reward timing choice.
- **Passive:** Gains bonus Power when attacking a ball that was set by a teammate (rewards teamwork over solo-carrying).
- **Fantasy:** The hammer. The one everyone is setting up for.

### 3.3 Blocker
- **Identity:** The wall. Defense and net presence.
- **Core Stats:** Power 5 / Accuracy 6 / Speed 5 / Reach 9
- **Special Action — "Read Block":** While near the net, the Blocker can pre-jump into a block stance; a well-timed block doesn't just stop the ball, it redirects it back at reduced power, giving their team a free extra touch.
- **Passive:** Largest hitbox/reach stat in the game; also has the highest floor-recovery speed after a dig.
- **Fantasy:** The safety net. Turns opponent spikes into your team's opportunity.

**Design note:** Stats above are baseline archetypes, not final tuning — expect balance passes once the Synergy Trait and Gacha rarity systems (docs #7 and #9) are layered on top, since those will push effective stats well beyond baseline.

---

## 4. Core Rule: The 1-2-3 Touch System

This is the single most important rule in the game and the one all UI/UX must communicate clearly at a glance.

**The Rule:** A team gets exactly 3 touches (or fewer) to return the ball across the net. The ball must change which player is touching it between the 1st and 2nd touch, and again between the 2nd and 3rd (no player may touch the ball twice in a row, matching real volleyball's "no consecutive touch" rule).

| Touch | Conventional Role | Purpose |
|---|---|---|
| **1st Touch** | Any role, usually Blocker/Back player | **Dig/Receive** — absorb the incoming ball, redirect it upward and toward the Setter |
| **2nd Touch** | Usually Setter | **Set** — place the ball precisely for the attacker |
| **3rd Touch** | Usually Spiker | **Attack** — send the ball over the net to score or continue the rally |

**Enforcement & Feedback:**
- A **touch counter UI** (3 pips) sits above the active team's side, filling in per touch, so both players always know how many touches remain.
- The **last eligible toucher is visually tagged** (a colored ring under their feet) so it's instantly clear who *can't* touch it next.
- If a team touches the ball a 4th time, or the same player touches it twice consecutively, it's an immediate fault and a point for the opposing team.
- Teams are **not required to use all 3 touches** — a Setter can choose to "dump" the ball over on the 2nd touch as a surprise attack, trading power for unpredictability. This is a deliberate skill expression, not an exploit.

---

## 5. The Awakening Mechanic

### 5.1 Concept
Most of the match is played at high, arcade-y speed — fast ball travel, snappy inputs, low visual clutter. But rallies build a hidden **Tension Meter**, and when specific trigger conditions are met, the game "Awakens" into **Zone Perception** mode: a bullet-time-style slowdown that turns the current touch into a high-stakes, high-precision moment.

Think of it as the inverse of most sports games' momentum systems — instead of speeding up for the big play, the world *slows down* so the player can feel like they're reacting with superhuman timing.

### 5.2 Tension Meter — What Builds It
- Consecutive successful touches without a fault (small, steady gain).
- Successful blocks and digs on high-power incoming balls (medium gain — defense is rewarded, not just offense).
- A Spiker's charged Finish Spike meter reaching 100% (large gain, and the most common trigger).
- Long rallies overall (a soft rally-length bonus, to reward volleys that go back and forth many times).

### 5.3 Awakening Trigger & Transition
When the Tension Meter fills:
1. The **next touch** — usually a 3rd-touch attack — becomes the "Awakening Touch."
2. On input, time-scale drops sharply (e.g., game logic runs at ~15–20% speed) while player input responsiveness is **not** scaled down equally — the player still moves and reacts at near-normal perceived speed relative to the slowed world. This is the core of the "Zone Perception" feel: everything else is slow, you are not.
3. Visual treatment shifts: desaturated background, a glowing ball trail, a screen-edge vignette in the team's color, and the crowd/ambient audio ducks under a low sub-bass drone.
4. The player gets an extended, precise input window to aim the shot — e.g., a directional reticle appears on the opposing court showing exact landing prediction, adjustable in slow-time.
5. On release/commit, the game snaps back to normal speed with a hard hit-stop and camera punch (see doc #10), and the outcome resolves (kill shot, dig, block, etc.)

### 5.4 Design Intent
- Awakening must be **earned**, never random — the player should always be able to explain, after the fact, why it triggered.
- It should feel like a *reward for good defense and rally-building*, not purely an offensive cooldown special — this is why blocks/digs feed the meter too. Otherwise the mechanic collapses into "just spam spike charge," which undermines the Setter/Blocker roles.
- Duration should be short (1.5–2.5 real-world seconds) — it's a punctuation mark on the rally, not a new pace for the whole game. Overusing it kills the "arcade" pillar.
- Both teams can trigger their own Awakening in the same rally (e.g., a Blocker Awakens on a dig, then a few touches later the Spiker Awakens on the return attack) — this creates a back-and-forth "who blinks first" tension that should be a marquee highlight-reel moment.

### 5.5 Failure States
Zone Perception is not auto-win. A poorly-aimed Awakening Touch can still be dug, blocked, or missed. The slowdown gives precision, not guaranteed success — this is what keeps it from feeling like an "I win" button and keeps the opposing team engaged rather than passive during the slowdown.

---

## 6. Scoring & Fault Conditions
- Point scored when: ball lands in opponent's court, opponent commits a touch fault, opponent hits the ball out of bounds, or opponent fails to return within 3 touches.
- Net violations, foot faults, etc. are intentionally simplified or omitted for arcade accessibility — the 1-2-3 touch rule is the one rule we want players to feel in their bones; we should avoid burying it under real-volleyball rule complexity.

---

## 7. Systems Referenced in Other Docs
This GDD defines roles and core rules. The following are specified in companion documents and should stay consistent with the definitions above:
- Flame Engine architecture & game loop (state machine: Serving → Rallying → Scoring)
- BallComponent physics (parabolic arcs, hitbox interactions)
- VFX pipeline for Finish Spikes
- Camera/resolution scaling
- AI opponent behavior and difficulty scaling
- Active Synergy Traits (role-pairing buffs)
- Persistence layer (stats, currency, unlocks)
- Economy & Gacha balancing
- "Juice" — camera shake, hit-stop, Awakening color treatment

---

## 8. Open Questions for Playtesting
- Exact Tension Meter fill rates per action (needs numeric tuning pass).
- Whether Awakening should be a per-team resource (bank it, choose when to "spend" it) vs. purely automatic — automatic is simpler to teach but a banked version could add a deeper skill ceiling for competitive players.
- Whether AI opponents should be able to trigger Awakening themselves, or whether it should be a player-exclusive "hero moment" to protect game feel against the AI difficulty doc's "not perfect" design goal.
