# Olympus

**The whole Olympus army in one window, inside World of Warcraft: Forever.**

Olympus is Asmongold's guild for *World of Warcraft: Forever*: Alliance, PvP ruleset, a
place to find dungeon groups, organize raids, share class knowledge and build the guild
together. It grew past **10,000 members during the beta**. A WoW guild caps at 1,000
members, so Olympus is really a *realm* of many Olympus guilds. In game each player
only ever sees the roster of their own guild. Nobody could tell how many Olympus guilds
exist, who leads them, or where the army is.

This addon answers exactly that. It adds up every Olympus guild live, in a window that
looks like Blizzard's Guild window and docks right next to it.

![The Olympus window next to the Guild window (example data)](https://raw.githubusercontent.com/dnl-gentile/olympus-addon/main/docs/census.png)

> **Status:** built for WoW: Forever and tested on Classic Era (1.15) and Anniversary (2.5).
> The author has no Forever beta access yet, so please report anything that behaves
> differently there (`/oly bug`).

---

## Who can use it

**Only members of a guild with "Olympus" in its name.** The check is fixed in the code and
cannot be switched off with a command. Outside an Olympus guild the addon joins no channel,
sends nothing and receives nothing. The only thing it offers there is the **Join Olympus**
screen described below.

### Not in Olympus yet?
First it asks the obvious question: *"<Your Guild>? Disband immediately. What are you
doing?"* Then it helps you get in. The **Join Olympus** screen uses the game's own `/who` to
find Olympus members online, groups them by guild, and whispers one of them a ready-made
request that you can edit ("Hi! I'd love to join Olympus. Does <Olympus II> have room for
one more?"). No answer? **Try someone else** picks a member you have not asked yet. Replies
are highlighted. It is rate limited, so nobody gets spammed.

## What it does

### Census: the army at a glance
- Every Olympus guild in one list: **Guild · Members · Online · Lord**. Columns sort by
  clicking, like the Guild window.
- **Total soldiers** and **online now** across the whole realm.
- **Where the army stands**: top zones ("Stormwind City 742") and totals per continent
  (Eastern Kingdoms, Kalimdor).
- Hover a guild: members, online, free slots, average level, inactive members, classes online, top zones.

### The Realm: the hierarchy
- The **King**, then every guild's **Lord** (guild master) and **Captains** (the officer rank
  right below the guild master).
  Each shows level, class and online or *offline 3d*. Long absences show in red.
- The **ranks** of each guild with how many members hold them.
- **Inactive members**: offline 7+ and 30+ days, per guild.
- **Level race**: the highest level players of the realm.
- **Recruiting**: the guilds that still have free slots, so new players go where there is room.
- **Layers** of your zone, named after the highest ranked Olympus member on each one
  ("Asmongold's layer"), with how many members are there.

### Person details
Click any Lord, Captain, racer or inspected player. You get the same card the Guild window
shows: level, class, zone, rank and status, with **Whisper**, **Invite** and **Who** buttons.
Any soldier can reach the Lord of another Olympus guild in two clicks.

### Decrees
| Decree | Who | What happens |
|---|---|---|
| **Call to arms!** | Captains | Alarm for every Olympus guild: raid warning, sound, red marker at the caller's position for 5 min |
| **Muster here** | Captains | Rally point: horn marker on the map for 30 min, soft alert |
| **Royal decree** | The Crown | A proclamation with free text, as a raid warning to the whole army |
| **Tabard inspection** | The Crown | Announces an inspection at the caller's position: wear your colors |

*The Crown* means the guild masters of Olympus guilds and the officers of the main
`<Olympus>` guild. Everyone else gets a local preview when they press the buttons.

### Channels
Chat for the whole federation, carried by the addon over its hidden Olympus channel (no
WoW channel number to join). Each channel is exclusive to a rank:

| Channel | Command | Who reads and writes |
|---|---|---|
| **[Olympus]** | `/ol <text>` | every member of every Olympus guild |
| **[Captains]** | `/olc <text>` | the Captains (rank 1) and Lords of every Olympus guild |
| **[Lords]** | `/oll <text>` | the Lords (every guild master, the King included) and the officers of `<Olympus>` |

- Higher ranks also use the channels below theirs: a Lord writes in all three.
- `/oly mute captains` (or `olympus`, `lords`) hides a channel in chat; the same command shows it again.
- Shift-click an item or spell into the line and it stays a link. Long lines are split into
  up to 3 messages.
- The channels show only in the chat of players with the addon.
- Ranks follow the rule of the decrees: whoever founds a guild with "Olympus" in its name is
  its Lord and gets [Lords], and its officers get [Captains].

**Not encrypted, not private:** every client on the hidden Olympus channel receives the text of
all three channels, and the addon only decides what to show. Anyone on that channel can read
[Captains] and [Lords] with a one-line script: without `/oly key` that is anyone who joins
"OlympusNet" by name; with a key, every member of the guilds that have it. The guild tag on an
[Olympus] line is not verified. Seal the channel with `/oly key`, and never share passwords there.

### Tabards: tabard inspection and the Wall of Shame
- **Patrol**: walk through the crowd and the addon inspects nearby Olympus members one by
  one (about 28 yards). It records who wears a tabard, who wears the wrong one and who
  wears none. Players it could not see properly are never accused.
- **Mark** a player (with a note: `/oly mark complained about the rule`) or a whole guild.
- Per guild: *"5 of 20 with problems"*.
- **Wall of Shame**: the Crown publishes the list, and every Olympus member with the addon sees it.
- Hover any player in the world to see their last inspection in the tooltip.

### World map
- Soldiers per zone on zone and continent maps, and per continent on the world map.
- The round **Olympus** button in the bottom right corner of the map switches markers
  (army per zone, decrees) on and off.

### Everywhere
- **Copy**: every tab produces a ready-to-paste text for Discord.
- The window opens from `/oly`, the minimap button, or the round button in your guild window:
  the old Guild tab or the new Guild & Communities window, whichever one you use.
- Next to Forever's Guild & Communities window it takes that window's look: icon tabs down
  the right side, its rows, column headers, buttons and member card.
- English and Portuguese (follows the game language).

## Install

**Easiest:** install **Olympus Guild** from the CurseForge app or WowUp. It installs in the
right place and keeps it updated. For Forever, pick the Forever (beta) installation of the
game in the app, not Classic Era.

**By hand:**
1. Download `Olympus-x.y.z.zip` from the **Files** tab here (or [GitHub Releases](https://github.com/dnl-gentile/olympus-addon/releases)).
2. Open your World of Warcraft folder. On Windows it is usually
   `C:\Program Files (x86)\World of Warcraft\` (on Mac: `/Applications/World of Warcraft/`).
3. Open the folder of the game version you play. For the **Forever beta** it is the one with
   *beta* in its name (for example `_classic_beta_`); Classic Era is `_classic_era_`, TBC
   Anniversary is `_anniversary_`.
4. Go into `Interface\AddOns\` (create `Interface` and `AddOns` if they don't exist) and
   extract the zip there, so you end up with `...\Interface\AddOns\Olympus\Olympus.toc`.
   Careful: Windows' *Extract All* adds a folder named after the zip
   (`AddOns\Olympus-0.7.11\Olympus\...`). If that happens, move the `Olympus` folder up into
   `AddOns`; the game only loads it from `AddOns\Olympus\`.
5. **Restart the game.** If the addon list says *out of date*, tick **Load out of date AddOns**.

The addon only shows **live data**: guilds appear as soon as one of their members with the
addon is online (give it a few minutes). There is no demo mode any more.

**One member per guild is enough** for that guild to appear for everyone. The more guilds
have at least one install, the more complete the census gets.

### For officers: seal the channel (recommended)
Type once, with a secret the Olympus officers agree on:
```
/oly key <secret>
```
Your guildmates with the addon receive it automatically through guild chat. From then on
the Olympus channel has a name and password derived from the secret, and outsiders can't
find or join it. Share the same secret with the officers of the other Olympus guilds
(for example in the officers' Discord), so all guilds meet on the same sealed channel.

## How it works

1. Every guild member can read their own guild's roster: name, level, class, zone, rank,
   online and last seen.
2. Members with the addon find each other through hidden addon messages in guild chat and
   **elect one reporter per guild**. The first name alphabetically wins, and every client
   computes the same answer.
3. The reporter sends a compact summary of its guild about every 3 minutes on the hidden Olympus channel.
4. Every client adds up all the summaries: that is the census.

Nothing leaves the game. There is no server, no website, no account and no tracking.

**Realms vs layers.** A realm (ClassicBetaPvP, ClassicBetaPvP2...) is a separate world
with its own guilds; layers are copies of a zone *inside* one realm. Guilds on the same
realm always see each other, whatever layer they are on. Whether the hidden channel also
reaches another realm is not confirmed yet (the "topology" lines of `/oly bug` say so once
a report from the other realm arrives). Realms whose guilds span each other share one
census and one realm key: PvP and PvP 2 on the beta from the start, and any realm your
guild turns out to be homed on. Alts on any other realm keep their census apart, and the
window shows which realms you are counting.

## Security and trust

The addon is plain Lua running on each player's computer, so anyone can edit their own
copy. No addon can prevent that. What this one does is make an edited copy useless:

- **Guild traffic is verified by Blizzard's servers.** Guild addon messages only reach
  members of that guild, so the realm key and guild elections can't be faked from outside.
- **Sender names cannot be forged.** The server stamps every message with its sender.
  - A decree counts only if the sender really is the Lord or a Captain of that guild,
    according to that guild's own roster report, or our own roster for our own guild.
    The rank written inside the message is ignored.
  - A report never proves its own sender's rank: someone else's report about that guild from
    the last 30 minutes must name them. The runner-up of each guild's election also reports
    every 10 minutes, so a Lord or officer who is the elected reporter is still verified.
    (An officer who is the only one of their guild with the addon is not.)
  - **The Crown** (any guild master, the officers of `<Olympus>`) is taken on the word of two
    different senders only.
  - A sender speaks for one guild only (a player who changed guilds can speak for the new one
    after 15 quiet minutes).
  - A guild whose reports disagree about its leader, its size or its officers is flagged, and
    its ranks are not trusted. So are two spellings of a guild name that differ only in capitals.
    However old the last report is, an added name is a disagreement, and sending the same
    report again settles nothing: the flag stays until someone who reported that guild before
    agrees with one side. Two new names can't confirm each other.
- **Only our channel counts**: addon messages that arrive on any other chat channel are
  ignored, so the sealed channel really keeps outsiders out.
- **Sealed channel** (`/oly key`): outsiders can't find the channel or join it.
- **Validation**: every number is range checked, names are length limited, and malformed
  messages are dropped. Decrees are rate limited per sender and in total.
- **Channels**: [Captains]/[Lords] lines count only if the sender's rank is verified like
  decrees; everyone else can use [Olympus] only. Sent with Blizzard's logged addon-message
  function (lines sent any other way are dropped); rate limited per sender and per channel, and
  no single sender can fill a channel.
- `/oly block <name>` ignores a player completely.

Limits, stated honestly:
- Two cooperating characters can still invent a guild with "Olympus" in its name (both send
  its report and name one of them as its leader) and so reach [Lords] and the Crown's decrees.
  So can anyone who really founds such a guild. Against a real guild they need a client that
  has not heard that guild's own reporters yet.
- **On the Forever beta that is every login**: its client saves addon data but never loads it
  back ([a known beta bug](https://us.forums.blizzard.com/en/wow/t/savedvariables-never-load-in-the-beta-%E2%80%94-all-addon-settings-reset-on-login-69913/2354798)),
  so every session starts without history, settings or realm key. The census still refills in
  seconds: a client that logs in asks the channel, and each guild's reporter answers at once.
- A real Olympus member who edits their copy could still send a wrong report for **their own**
  guild. Their guildmates' reports and the conflict flag make a changed leader, size or officer
  list visible, but it can't be made impossible.

## Built for a crowd of thousands

- One summary per guild about every 3 minutes, not one per player.
- In a full guild only the members who could be elected keep saying hello; the rest go quiet.
- Layers are announced by officers plus a stable 1 in 8 sample, every 10 minutes.
- Messages are spaced 1.2 s apart, below Blizzard's addon message limits, and alert sounds
  play at most once every 15 seconds.
- Chat has its own short lane: a line goes out within about a second, and while reports are
  waiting it never takes more than every other message slot.

## Commands

| Command | |
|---|---|
| `/oly` | open or close the window |
| `/oly realm` · `/oly decrees` · `/oly tabard` | open a tab |
| `/oly patrol` | start or stop the tabard patrol |
| `/oly mark [note]` | mark your target |
| `/oly arms [text]` · `/oly muster [text]` | send a decree (`test` = local preview) |
| `/ol <text>` · `/olc <text>` · `/oll <text>` | write in [Olympus], [Captains] or [Lords] |
| `/oly all <text>` · `/oly captains <text>` · `/oly lords <text>` | the same, as `/oly` commands |
| `/oly mute olympus` · `/oly mute captains` · `/oly mute lords` | hide or show a channel in chat |
| `/oly key <secret>` | officers: seal the Olympus channel |
| `/oly block <name>` | ignore a player |
| `/oly map` | zone markers on the world map |
| `/oly sound` | alert sounds on or off |
| `/oly bug` | copyable bug report |
| `/oly status` | diagnostics in chat |

## Reporting a bug

Type `/oly bug` (or press **Report a bug**), copy the text and open an issue on [GitHub](https://github.com/dnl-gentile/olympus-addon/issues). Errors are
also saved in `WTF/Account/<ACCOUNT>/SavedVariables/Olympus.lua`.

## License

MIT. A fan project, not affiliated with Blizzard Entertainment, Asmongold or the
Olympus leadership. The Olympus emblem belongs to its owners and is used for the community.

*Sources for the Olympus description: the Olympus Discord welcome message,
[Prism on X](https://x.com/fwprism/status/2101809316382847172) (10K+ members in the beta),
[Dexerto](https://www.dexerto.com/world-of-warcraft/asmongold-responds-as-wow-forever-players-want-him-banned-over-massive-olympus-guild-3411199/).*


Source code: https://github.com/dnl-gentile/olympus-addon
