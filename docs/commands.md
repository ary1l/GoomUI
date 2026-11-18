# Commands

[← Back to the README](../README.md)

`/goomui` and `/gui` are the same command. Anything not listed prints the list in game.

## General

| Command | Does |
|---|---|
| `/goomui` | settings window |
| `/goomui look` | current colour preset and bar look |
| `/goomui look next\|prev\|<preset>` | colour preset |
| `/goomui look shape soft\|flat\|glass` | bar shape |
| `/goomui look texture none\|segmented\|striped\|quarters\|scanline\|fade` | bar texture |
| `/goomui look frame [on\|off]` | bar frame (no word flips it) |
| `/goomui look panel tinted\|dark\|clear\|framed` | panel backgrounds |
| `/goomui look opacity <0.25-2>` | panel opacity |

## Party list

| Command | Does |
|---|---|
| `/goomui setup` | drag boxes + list options; again (or *Save + close*) saves |
| `/goomui lowfi` | text-only mode for this character |
| `/goomui crew` | crew link: receive port, boxes seen |
| `/goomui perf` | 10 s timing report |
| `/goomui tdebug` | target / sub-target values per party row (for a missing `>` / highlight) |

## Treasure pool

| Command | Does |
|---|---|
| `/goomui pool` | window on / off (also Bar tab) |
| `/goomui pool demo` | sample items, to place it (drag the window; buttons send nothing in the demo) |

## Rings and GEO

| Command | Does |
|---|---|
| `/goomui ring` | ring status |
| `/goomui ring on\|off\|depth\|arrow\|runes\|fade\|flip` | toggles |
| `/goomui ring scale <n>` \| `slices <n>` | size / smoothness |
| `/goomui ring range on\|off\|geo\|hitbox` | range fill toggles |
| `/goomui ring range base <n>` \| `fill <n>` | range in yalms / fill strength |
| `/goomui geo [on\|off\|buffs\|cure\|bubble\|clear]` | GEO bubble rings |
| `/goomui geo radius\|cap\|scan\|slices <n>` | bubble radius, max rings, scan radius, slices |

## AAEV

| Command | Does |
|---|---|
| `/goomui aaev on\|off` | enable / disable (off = no packet parsing) |
| `/goomui aaev` | show / hide the chart |
| `/goomui aaev show\|hide` | force shown / hidden |
| `/goomui aaev demo` | sample data |
| `/goomui aaev lock\|unlock` | drag charts (Free position; under chat / under bar follow their spot) |
| `/goomui aaev simple\|full` | uniform squares / damage-scaled bars |
| `/goomui aaev bars <n>` | bars kept |
| `/goomui aaev delay <n>` \| `autohide` \| `always` | hiding after disengage |
| `/goomui aaev zone` \| `zonereset` | zone accuracy / reset it |
| `/goomui aaev config` \| `reload` \| `help` | settings tab / reload settings / help |
