# Dungeon Quest Guide

An addon for **World of Warcraft: Forever** that guides you step by step to every quest you can take for a dungeon, before you go in.

## Usage

The guide is off whenever you log in: no arrow, pin or window until you pick a dungeon (or right-click the minimap button to carry on with the last one).

Click the minimap button or type `/dqg` to open the dungeon list: every dungeon with quests for your character, by level, with its level range, its bosses' levels and how many quests you can take there. Click a dungeon to start its guide.

The guide numbers the steps in the order you do them:

1. **Quest chains first:** every step of every prerequisite chain.
2. **Then the dungeon quests out in the world.**
3. **Then the dungeon:** the entrance, and what to do inside (quests picked up inside, items to loot that start a quest, chain steps done or handed in inside).
4. **After the dungeon:** quests whose chain carries on from something inside, like a quest started by an item that drops there. They come last, because you can't start them before the run.

A chain that starts in another dungeon (an item another dungeon drops) is listed under "Not yet", with where it comes from.

Within each part, the nearest step comes next. Everything at one quest giver is one step ("Hand in Tramping Paws, pick up Fire Taboo"), and whatever that giver, or anyone a few steps away in the same town, has for you is done on the same visit, even a dungeon quest that would otherwise come later. Steps tick themselves off as you pick quests up and hand them in. The Dungeon Journal's arrow leads to the step you're on, whether that's a quest giver or a quest area (where the mobs to kill or the things to collect are), and TomTom adds a map and minimap pin.

In the step's own zone the Journal's arrow points straight at it, not along the roads. Within 1,000 yards it points at the step itself; farther off in the same zone (up to 2,500 yards) it points at a spot a little ahead on the straight line that moves on as you walk, so the yards it shows count only to that spot. From another zone, or farther, it finds the way there: roads, flights and boats. In the three Stranglethorn ruins the Journal knows wall by wall (Zul'Kunda, Bal'lal, the Vile Reef coast) it keeps its own way round the walls.

Once you're in a quest's area (among the mobs to kill or the things to collect), the arrow and the map pin go away, and they come back when you leave it. Click the step if you want the arrow there anyway. Flying over a quest area doesn't count.

While you're dead and TomTom's arrow points at your corpse, the guide's arrow and pin are off until you're alive again. When TomTom sets no corpse arrow (its "Automatically set a waypoint when I die" is off, its arrow is hidden, or you died inside a dungeon), the guide's arrow stays and the Journal turns it into the way back to your corpse.

If there's no arrow on the step, the window says why at the top (right-clicked away, you got there, another arrow in the journal, and so on).

- Click a step to point the arrow at it instead, or to bring back an arrow you hid.
- Right-click a quest to leave it out (or put it back).
- "All dungeons" / "Back to guide" switches between the list and the guide without stopping it.
- **Right-click the minimap button to turn the guide off:** the arrow, the map pin and the window go away, and the icon goes grey. Right-click again to turn it back on with the same dungeon. (The window's "Turn off" button does the same.)
- `/dqg <dungeon>` starts a dungeon directly (short names work too: `/dqg dm`, `/dqg sfk`). `/dqg stop` stops the guide.

## Requirements

All three are required: the guide doesn't load without them.

- **DungeonJournal** (the `ForeverDungeonJournal` folder) by Exehn. The guide reads its dungeons, quests, quest chains and NPC locations, and uses its arrow. You never need to open it.
- **QuestieDB**: quest areas, and quest givers the journal has no location for.
- **TomTom**: map and minimap pins.

## Install

Copy the `DungeonQuestGuide` folder into your WoW `Interface/AddOns` folder, then restart the game.

## Feedback

Anything that guides you wrong: open an issue on GitHub.

## License

MIT
