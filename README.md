# Hood Zombies

A round based zombie survival FPS built in Godot 4.7.2. Fight through escalating rounds in a walled compound, earn points for every hit and kill, and spend them on doors, weapons, perks, and upgrades to survive as long as you can.

Everything in the game is original: the setting, the four playable characters, the weapon names, the perk names, and the dialogue. The systems follow the classic round based survival formula, rebuilt from scratch in GDScript.

## What is in the game

- Round based survival with an escalating points economy
- Barricades that zombies tear down and you rebuild, priced doors that open new zones of the compound
- A mystery box with a weighted weapon pool, and a Forge Bench that upgrades the weapon in your hands
- Six perks with original effects: Deadeye Tonic, Heavy Caliber, Iron Heart, Quick Hands, Street Runner, and Vital Surge
- Eight weapons, from the Street-9 starter pistol to an LMG and a sniper rifle, all defined as data resources
- Four playable characters, each with their own dialogue pool that reacts to game events, with subtitles
- Full controller support alongside keyboard and mouse, including disconnect handling and menu navigation
- Save data and settings persistence, quality toggle, pause and game over flow

## Running it

1. Install Godot 4.7.2.
2. Clone this repository and import the project in Godot.
3. Press play. The main scene is scenes/ui/main_menu.tscn.

## Tests

The game ships with an automated test suite: 12 unit suites and 11 integration suites covering the player controller, weapons, zombie logic, rounds and economy, barricades and doors, the mystery box, perks and upgrades, saves and settings, dialogue, and controller input.

Run it headless:

```
godot --headless --script res://tools/run_tests.gd
```

Current status: 110 tests passing, 0 failing.

## Project structure

- scripts/ holds the GDScript code, organized by system: player, enemies, weapons, combat, economy, rounds, perks, interactables, dialogue, characters, ui, visuals, audio, and core
- resources/ holds the data that drives the game: weapon, perk, character, enemy, and configuration resources that can be tuned without touching code
- scenes/ holds the Godot scenes for the player, enemies, interactables, environment, and UI
- tests/ holds the unit and integration suites, and tools/ holds the test runner plus development and performance tools

## License

Copyright (c) 2026 Syed Ahmed Hussain. All rights reserved.
