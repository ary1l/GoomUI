# Rings and GEO

[← Back to the README](../README.md)

## Target rings

Rings on the ground under your target and sub-target: facing arrow, runes, rear fade (Ring tab or
`/goomui ring ...`).

- **Range fill:** the ring fills when the target is within *Base range* (center to center). *Add both hitboxes*
  adds your hitbox and the target's.
- **Depth test:** off by default. On, rings hide behind terrain; if they vanish entirely, Ashita's render target has
  no depth surface: turn it off.
- Hidden when the game interface is hidden, in cutscenes, and while the map or expanded log menus are open.

## GEO bubbles

Only geomancers in your party or alliance (you included) count. Geo-, Indi- and Entrust casts by anyone else are
ignored.

- **Bubble boundary:** a circle for the luopan, the Indi carrier and each Entrust target, coloured by element;
  radius from Widened Compass at cast time.
- **Debuff bubbles:** ring the mobs inside the luopan's bubble; tagged mobs (already on your group's hate list)
  differ from untagged ones.
- **Buff bubbles:** ring the party members inside (*Ring party in buff bubbles*).
- **Cure tagging:** a Cure on an ally tags the mobs that ally has hate with (*Cure on ally tags that ally's mobs*).
- **Indicolure timer:** 180 s + gear + 2 s per Indicolure Spell Effect Dur. job point level, times augment %. Job
  points are read from 0x08D.
