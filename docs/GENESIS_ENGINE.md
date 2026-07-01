# GENESIS Engine Policy

## Position

GENESIS is not just a reference game. For Project_ZAKO, GENESIS is the engine baseline.

The current source of GENESIS behavior and look is:

```text
/Users/hashimotoshinya/TSG_Godot
```

Project_ZAKO should be developed as a game built on that GENESIS baseline, not as a visually separate rewrite.

## Preserve From GENESIS

- True top-down vertical shooter camera
- Screen plane as `X/Y`, altitude/depth as `Z`
- HIGH / MID / LOW altitude play
- Low-poly box/plate visual language
- Glossy materials, simple silhouettes, readable depth
- Space background, star-system atmosphere, and shader mood
- Bullet, explosion, enemy marker, and HUD readability conventions
- Mobile/Metal stability assumptions

## ZAKO Adds On Top

- Zako reincarnation loop
- 2 vs 20 asymmetric battle prototype
- Role switching between zako, pilot, boss, and hero-side slots
- Anonymous radio / battlefield chatter
- Player selection lottery
- Persistent war-state presentation
- Faction-relative vertical shooter play: hero-side and enemy-side players both get a forward-scrolling top-down shooter feel

## Rule Of Thumb

When a system exists in GENESIS, inherit it first. Only replace it when ZAKO's game rule truly requires a different behavior.

If a visual or control decision feels uncertain, default to the existing GENESIS/TSG_Godot behavior and prove the change in-game before diverging.

## Faction View

Enemy-side play is not just the hero-side screen rotated 180 degrees.

Both factions must feel like a proper vertical shooter from their own side:

- The local player advances forward from the bottom of their screen.
- Local input keeps the same feel as GENESIS: left/right dodge, forward pressure, retreat/back movement.
- The battlefield state is shared, but camera, scroll direction, markers, and control mapping are faction-relative.
- The enemy-side view may be a 180-degree transform of the world coordinate frame, but gameplay presentation must preserve the same vertical-STG sensation as hero-side play.
- Any networking model should keep world simulation authoritative and convert only presentation/input through the faction view layer.

In short: one shared war, two faction-relative vertical shooter experiences.
