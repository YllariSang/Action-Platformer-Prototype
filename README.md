# Action-Platformer-Prototype
---
Made in the Godot Engine 4.7 - Stable. 2D Action Platformer Prototype. A school project for the subject Game Development in the course of BSIT 3rd Year 2nd Semester. This is a 2D game and will stay 2D.

> **Development notes:** see [AGENTS.md](AGENTS.md) for the project conventions that agents and contributors are expected to follow.

---

## GAME PROTOTYPE CONTENT:

### Controls:
| Action | Key |
| --- | --- |
| Move | `A` / `D` |
| Jump (double jump, wall jump) | `Space` |
| Dash (i-frames) | `Left Shift` |
| Parry | `Right Mouse` |
| Shoot / charge Railgun | `Left Mouse` (hold) |
| Heal (2 Sparks) | `Q` (hold) |
| Restart | `R` |

### Mechanics:
- PARRYING!??!11!1!!
- Dash with I-Frames
- Wall dash, slide, and jump
- Shooting Kirklets
- Bullet jumping
- 5 HP, no passive regeneration
- Healing costs 2 Sparks, so parrying is your only recovery

### MAIN GAMEPLAY LOOOOOOOOOOOOOOOOPPPPP:
- Game will revolve around using parry to accumulate ammo called "Spark", said ammo has a maximum capacity of 6/6 and can be utilized in different ways. Normal shots costs 1/6, railgun costs 3/6, healing costs 2/6, reflecting enemy projectiles can be done while performing a parry in 6/6.

The game is hard, very much like a metroidvania if I make more levels but I want to focus on boss battles only, we will see the direction.

### Health &amp; Sparks:
You have 5 HP and nothing regenerates on its own. An open parry is a hard immunity, so nothing an enemy throws can connect while your guard is up — the attack is eaten, reflected, or whiffs into recovery, but it never costs you HP. A hit taken during parry recovery costs double, and a dash i-frame cancels any hit outright. Spending 2 Sparks restores 1 HP, which means every parry is either offence or survival — you cannot do both from the same Spark.

Healing is a **hold**, not a tap. `Q` roots you in place for 0.6s, and you cannot parry, dash, or shoot through it. That is deliberate: a tap would be an instant 1 HP for the same 2 Sparks a parry pays, with no timing to get right, which quietly made the parry pointless. Sparks are charged on *completion*, so letting go costs only the time and the standing-still. You can press `Q` while already running and the channel starts anyway — the commitment is the hold, not standing still first. Letting go of `Q` cancels it, and so does pressing a direction *after* the channel is under way, or taking a hit. You have to find a gap, and you cannot heal into the i-frames a hit just granted you. If you press `Q` at full health, or short on Sparks, you are told once; hold it as long as you like and the message does not repeat until you let go.

### HUD:
Health and Sparks are shown on a fixed screen-space HUD in the top-left, not above the player. Red pips are HP, amber pips are Sparks, and the `[Q] HEAL 2` hint in the top-right lights up green whenever a heal is actually affordable.

### Weapons:
A normal shot costs 1 Spark for 15 damage. The railgun is a 1.0s hold costing 3 Sparks for 60 damage and punching through up to 3 targets, so it is 20 damage per Spark against the normal shot's 15. It used to be 45, which was exactly 15 per Spark too, so three normal shots matched it for the same cost and there was never a reason to charge. A wall still stops it.

### Enemy aggro:
Regular enemies are leashed. Past `aggro_range` they give up: no chase, no telegraphed dash, no live hitbox, and a flier stops shooting mid-burst. They drain out to a grey tint, trudge back to the spawn point, and re-engage the moment you come back into range. Backing off after a dash windup cancels the attack, but a dash that is already in flight still lands — the leash is not a free escape button. The boss is not leashed; it is a set piece.

### Art pipeline:
Visuals currently use `icon.svg` as a placeholder throughout; real artwork is being prepared. Feedback is built so that swapping in finished art is a texture change rather than a code change: hit flashes run through a small shader (`Shaders/feedback_flash.gdshader` via `SpriteFeedback`) that layers on top of each entity's colour tint, so a stunned enemy stays visibly stunned while it flashes on impact.
