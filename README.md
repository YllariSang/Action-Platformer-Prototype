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
| Heal (2 Sparks) | `Q` |
| Restart | `R` |

### Mechanics:
- PARRYING!??!11!1!!
- Dash with I-Frames
- Wall dash, slide, and jump
- Shooting Kirklets
- Bullet jumping
- 3 HP, no passive regeneration
- Healing costs 2 Sparks, so parrying is your only recovery

### MAIN GAMEPLAY LOOOOOOOOOOOOOOOOPPPPP:
- Game will revolve around using parry to accumulate ammo called "Spark", said ammo has a maximum capacity of 6/6 and can be utilized in different ways. Normal shots costs 1/6, railgun costs 3/6, healing costs 2/6, reflecting enemy projectiles can be done while performing a parry in 6/6.

The game is hard, very much like a metroidvania if I make more levels but I want to focus on boss battles only, we will see the direction.

### Health &amp; Sparks:
You have 3 HP and nothing regenerates on its own. A hit taken during parry recovery costs double, and a dash i-frame cancels any hit outright. Spending 2 Sparks restores 1 HP, which means every parry is either offence or survival — you cannot do both from the same Spark.

### HUD:
Health and Sparks are shown on a fixed screen-space HUD in the top-left, not above the player. Red pips are HP, amber pips are Sparks, and the `[Q] HEAL 2` hint in the top-right lights up green whenever a heal is actually affordable.

### Art pipeline:
Visuals currently use `icon.svg` as a placeholder throughout; real artwork is being prepared. Feedback is built so that swapping in finished art is a texture change rather than a code change: hit flashes run through a small shader (`Shaders/feedback_flash.gdshader` via `SpriteFeedback`) that layers on top of each entity's colour tint, so a stunned enemy stays visibly stunned while it flashes on impact.
