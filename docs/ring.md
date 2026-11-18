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

## Target cursor

A marker over your target's head, drawn over everything (Cursor tab or `/goomui cursor ...`). It does what the
customtarget addon does: unload that one.

- **Styles:** *Gem* (light border, dark ring, lit facets; default), *Flat* (smooth centre), *Hollow* (outline only)
  and *Crystal* (an eight-faced crystal that turns; *Spin* off holds it still).
- **Colours:** a palette colour (HP, MP, TP, Spell, Crit, WS, ...), so it follows the colour preset; White; or
  *Target kind*, the ring colours (mobs, players, NPCs). Default MP.
- **Sub-target colour:** while you sub-target, your first target keeps a cursor in this colour, 10 px higher; item,
  `<stnpc>` and `<stpc>` picks use it too. Default TP ready.
- **Float:** drifts up and down 2.5 px.
- **Lift over players:** 12 px higher over players (0-40), clearing the master level stars on their nameplate.
- **Apply to all characters:** sends the cursor settings to every character with `/mss` (MultiSend). The Look tab
  has the same button for the colour preset, bar look and panels.
- **Placement:** the head point the game puts the name at (skeleton bone 2, read as customtarget reads it); doors and
  other objects: 8 px above their position. Same hiding rules as the rings.

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
