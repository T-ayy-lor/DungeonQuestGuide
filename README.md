# Dungeon Quest Guide

An addon for **World of Warcraft: Forever** that guides you step by step to every quest you can take for a dungeon, before you go in.

## Usage

Click the minimap button or type `/dqg` to open the dungeon list: every dungeon with quests for your character, by level, with its level range, its bosses' levels and how many quests you can take there. Click a dungeon to start its guide.

The guide lists the steps in this order:

1. **Quest chains first:** every step of every prerequisite chain.
2. **Then the dungeon quests out in the world.**
3. **Then the dungeon:** the entrance, with the quests picked up inside listed under it.

Within each part, the nearest step comes next. Steps tick themselves off as you pick quests up and hand them in. The Dungeon Journal's arrow leads to the step you're on, and with TomTom installed there is also a map and minimap pin.

- Click a step to point the arrow at it instead.
- Right-click a quest to leave it out (or put it back).
- "All dungeons" / "Back to guide" switches between the list and the guide without stopping it.
- `/dqg <dungeon>` starts a dungeon directly (short names work too: `/dqg dm`, `/dqg sfk`). `/dqg stop` stops the guide.

## Requirements

- **DungeonJournal** (the `ForeverDungeonJournal` folder) by Exehn: required. The guide reads its dungeons, quests, quest chains and NPC locations, and uses its arrow. You never need to open it.
- **TomTom**: optional, for map and minimap pins.
- **QuestieDB**: optional, fills in quest-giver locations the journal doesn't have.

## Install

Copy the `DungeonQuestGuide` folder into your WoW `Interface/AddOns` folder, then restart the game.

## Feedback

Anything that guides you wrong: open an issue on GitHub.

## License

MIT
