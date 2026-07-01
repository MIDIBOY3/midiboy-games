# Project_ZAKO Game Design

## Terminology

- HERO: the rare powerful player side, equivalent to the traditional player ship side.
- HERO Unit: a unit controlled by, or representing, the HERO side.
- ZAKO: the mass enemy-side player role.
- ZAKO Unit: a fragile enemy-side unit controlled by an online player or used as a reincarnation target.

When the local player is in ZAKO mode, the HERO Unit should continue moving through the battlefield under autopilot. ZAKO play is then built around approaching, threatening, surviving, or being destroyed by that HERO Unit.

Current local prototype control:

- `F9` toggles HERO/ZAKO side.
- ZAKO prototype mode suppresses GENESIS/TSG progression: click-stars, motherships, gates, star-system selection, BOSS/BUDDY key flow, endings, and story events.
- In ZAKO mode, HERO Unit runs on autopilot.
- The local ZAKO prototype is a 1v1 sandbox: one HERO Unit and one controllable Toroid ZAKO Unit only.
- Gates, click-stars, mothership beacons, carrier takeover events, normal enemy spawning, and extra enemies are suppressed in ZAKO mode.
- A local ZAKO Unit spawns about ten screen-heights ahead of the HERO Unit in world space, where enemies belong.
- Placing a ZAKO generates an enemyFrontChunk about ten screens ahead of HERO. It is saved as world chunk data, including terrain cells, turret placements, enemy spawn points, obstacles, and hazards.
- enemyFrontChunk data is kept when activeActor switches back to HERO; it becomes hidden/inactive, then reactivates when HERO later reaches the same worldY.
- HERO and ZAKO share one terrain chunk system. Chunk data may remain loaded between them, but only chunks around the current activeActor are visible, rebuilt, and used for terrain collision.
- F9 side switching updates activeActor/cameraTarget, ensures chunks around that actor, and recalculates visible chunks; the ten-screen gap between HERO and ZAKO is not continuously drawn or updated.
- ZAKO camera rolls the world 180 degrees immediately, with no diagonal spin transition.
- ZAKO input is mapped through that 180-degree world roll, so the screen still plays like HERO's bottom-to-top vertical shooter while the ZAKO Unit attacks the HERO Unit.
- Space background shader scroll and drifting star names keep flowing top-to-bottom on screen in ZAKO mode, because the ZAKO Unit is also advancing through the field.

## Core Idea

Project_ZAKO is a casual persistent online vertical shooter built on the GENESIS Engine.

It is not a stage-clear game. It has no fixed area objective, final boss route, or end condition in the usual arcade sense.

The game is a 24/7 war state:

- The world keeps moving 365 days a year.
- Players can join or leave at any time.
- A session can be 15 seconds, 5 minutes, or longer.
- The central question is always: which side is winning right now?

## Player Fantasy

All combatants are online players.

- Hero-side players are the rare powerful units.
- Enemy-side players are the mass of fragile zako units, turrets, formations, and boss parts.
- A player can be destroyed quickly and re-enter as another role.
- Being a zako is not punishment. It is the main casual play loop.

The model is: become a Xevious-like zako such as a Toroid and attack the Solvalou.

## Always-On War

The game should present a live battlefield rather than a campaign map.

At any moment, the player should understand:

- Hero side is pushing.
- Enemy side is pushing.
- The battle is balanced.
- A local front is collapsing.
- A famous player or anonymous unit just changed the flow.

Progress is not "clear the stage." Progress is the visible movement of war pressure over time.

## Join And Leave

The game must respect casual participation:

- Join instantly.
- Spawn into an active role.
- Fight briefly.
- Die, pass through, or survive.
- Leave without betraying a team or ruining a match.

No player should feel locked into a long ranked match, clan obligation, or voice-chat responsibility.

## Enemy Approach Loop

Enemy-side play is a vertical shooter in its own right.

The enemy player spawns at a distance from the hero-side player/front.

Flow:

- Spawn ahead of the hero-side front.
- Approach through incoming hero-side fire.
- Enter the hero-side screen as an enemy unit.
- Try to destroy or disrupt the hero-side player.
- If destroyed, reincarnate as another unit.
- If the enemy survives and passes through, warp/redeploy ahead of the hero-side front for another approach.

Enemy-side success can be:

- Destroying the hero-side player.
- Forcing movement.
- Absorbing fire.
- Surviving through the screen.
- Helping the current war pressure shift.

## Faction-Relative Shooter Feel

Hero-side and enemy-side players must both feel like they are playing a forward-scrolling top-down vertical shooter.

Enemy-side play is not merely the hero-side camera rotated.

Both sides should experience:

- Own unit near the lower part of the screen.
- Forward movement toward the top of the screen.
- Incoming danger entering from ahead.
- Same basic GENESIS input feel.

The server/world can use one shared coordinate system, but each client view should transform presentation and input according to faction.

## No Final Destination

There can be temporary fronts, local events, bosses, star systems, mother ships, and click-star routes, but these are not the final purpose.

They exist to produce live war texture:

- Where is the fight now?
- Who is pressuring whom?
- What can I join for a few minutes?
- What happened while I was gone?

The game should feel like a living battlefield that happens to be playable as a vertical shooter.
