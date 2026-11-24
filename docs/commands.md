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
| `/goomui look set <preset> <shape> <texture> <frame on\|off> <panel> <opacity>` | all at once (what *Apply to all* sends) |
| `/goomui scale <0.5-3>` | UI scale: text and sizes of every goomui window (small / high-DPI screens) |

## Party list

| Command | Does |
|---|---|
| `/goomui setup` | drag boxes + list options; again (or *Save + close*) saves |
| `/goomui lowfi` | text-only mode for this character |
| `/goomui crew` | crew link: receive port, boxes seen |
| `/goomui perf` | 10 s timing report |
| `/goomui tdebug` | target / sub-target values per party row (for a missing `>` / highlight) |
| `/goomui tinfo` | what the target bar reads for your current target and sub-target (for a target it does not show) |

## Treasure pool

| Command | Does |
|---|---|
| `/goomui pool` | treasure pool on / off (also Target bar page) |
| `/goomui pool open` | show / hide the window (same as clicking the summary) |
| `/goomui pool dock` | summary by the party list on / off (off: the window alone) |
| `/goomui pool demo` | sample items, to place it (drag the window; buttons send nothing in the demo) |

## Rings and GEO

| Command | Does |
|---|---|
| `/goomui ring` | ring status |
| `/goomui ring on\|off\|depth\|arrow\|runes\|fade\|flip` | toggles |
| `/goomui ring ddebug` | depth facts for one frame (depth surface, render target, game Z states, draw results), for the depth test |
| `/goomui ring scale <n>` \| `slices <n>` | size / smoothness |
| `/goomui ring range on\|off\|geo\|hitbox` | range fill toggles |
| `/goomui ring range base <n>` \| `fill <n>` | range in yalms / fill strength |
| `/goomui geo [on\|off\|buffs\|cure\|bubble\|clear]` | GEO bubble rings |
| `/goomui geo radius\|cap\|scan\|slices <n>` | bubble radius, max rings, scan radius, slices |

## Target cursor

| Command | Does |
|---|---|
| `/goomui cursor [on\|off]` | target cursor (no word: toggle) |
| `/goomui cursor style gem\|flat\|hollow\|crystal` | style |
| `/goomui cursor color\|sub <colour>` | cursor / sub-target colour (`white`, `kind`, `mp`, `tp`, ...; a wrong name lists them) |
| `/goomui cursor size <n>` | 0.5-3 |
| `/goomui cursor lift <px>` | how much higher over players, 0-40 (clears their master level stars) |
| `/goomui cursor float\|spin [on\|off]` | drift up and down / turn the crystal (no word: toggle) |
| `/goomui cursor set <on\|off> <style> <colour> <sub> <size> <float> <spin> [lift]` | all at once (what *Apply to all* sends) |

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
| `/goomui aaev config` \| `reload` \| `help` | settings page / reload settings / help |
