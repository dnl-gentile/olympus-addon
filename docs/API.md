# The Olympus API, for addon authors

Olympus 1.2.4 lets other addons read, with the player's permission, what Olympus already shows
that player on its own pages. An addon can also contribute one page to the Olympus window without
copying its shell. This page is the whole contract of version 1 (`OlympusAPI.VERSION`).

- **Read-only data.** No data function sends a chat line, a decree, a whisper or any addon message
  for the player, and none changes anything in Olympus.
- **Only what the player already sees, at no more detail.** The Wanted list and its bounties, the
  public rankings, the player's own frame and title, and his own Olympus guild, rank and role.
- **One permission per addon's data.** Your addon calls `OlympusAPI.Register`, the player answers
  **Yes** or **No** for it on Olympus's privacy page, and no data comes back before a Yes.
- **One shared client-owned page.** A registered handle may claim the one client-owned slot in
  Olympus's tab rail. Olympus owns the window shell; your addon owns that page's frames and
  callbacks. Hosting the page grants no data access and works while the data answer is pending or
  refused.
- **Copies.** Every table you get is built for that call. Changing it changes only your copy.
- **Pushed, not polled.** Callbacks tell you when something changed.

## Getting started

Add Olympus as an optional dependency in your TOC, so that it loads before your addon when both
are installed:

```
## OptionalDeps: Olympus
```

Then register once, when your addon loads:

```lua
local api
if OlympusAPI and OlympusAPI.VERSION >= 1 then
	api = OlympusAPI.Register("MyAddon") -- your addon's folder name, as in its TOC file's name
end
if not api then return end -- no Olympus, an older one, or the name was refused

api:On("PERMISSION_CHANGED", function(event, status)
	if status == "granted" then
		-- the player said Yes: read what you need now
	end
end)

api:On("WANTED_CHANGED", function(event, rows)
	-- rows is what api:GetWanted() returns now, your own copy
end)

if api:Status() == "granted" then
	local rows = api:GetWanted()
end
```

If your addon has a page of its own, register it through the same handle. This is independent of
the player's data answer:

```lua
if OlympusAPI.Has("ui.surface") then
	local ok, reason = api:RegisterSurface({
		label = "Map tools",
		icon = "Interface\\Icons\\INV_Misc_Map_01",
		build = function(parent, context)
			-- Make this page's frames as children of parent.
			-- context is { style = "hd" or "old", apiVersion = 1 }.
		end,
		refresh = function(parent, context)
			-- Optional: update the already-built page while it is selected.
		end,
	})
end
```

`OlympusAPI` is `nil` when Olympus is not installed, is older than 1.2.4, or was just updated to
1.2.4 and the game has not restarted since: a file an update adds is loaded only when the game
starts, not on a `/reload`. Always check for it.

## Permission

`OlympusAPI.Register("MyAddon")` adds a line for your addon to Olympus's privacy page (the page
`/oly privacy` opens). The line shows your TOC's `## Title` (colour and texture codes removed) and
says, in Olympus's own words, what a Yes lets your addon read. The page opens by itself once for a
new line, outside combat and instances, while the player is in an Olympus guild; the player can
answer there at any time, and change the answer whenever he likes.

- `"pending"`: never answered. Your calls return nothing.
- `"granted"`: the player said Yes. Your calls return data.
- `"refused"`: the player said No. Your calls return nothing.

The page's **Authorize all** button deliberately answers every visible pending line, including an
addon's; **Keep current choices** closes without granting it. Each addon also has its own Yes and
No. The answer is kept for the player's account and stays
across sessions. When a later API version gives more than version 1 does, every addon's line is
asked again. This answer gates only the data methods and their data events. A registered UI surface
works while the answer is pending or refused and receives no data from Olympus by doing so.

## Reference

### `OlympusAPI.VERSION`

A number: `1` for this contract. A change that breaks this contract raises it. New fields may be
added to the tables below without raising it: ignore the fields you do not know.

### `OlympusAPI.SURFACE_LIMIT`

The number of client-owned pages the shared tab rail can host in one session: `1`. This is
separate from the 16 addons that may register data handles.

### `OlympusAPI.Has(feature)`

`true` when this build gives that feature, `false` otherwise:

| Feature | What |
|---|---|
| `"wanted"` | `handle:GetWanted()` |
| `"rankings"` | `handle:GetRankings()` |
| `"rankings.slayers"`, `"rankings.donors"`, `"rankings.church"`, `"rankings.games"` | that kind of ranking (a build without the games has no `"rankings.games"`) |
| `"profile"` | `handle:GetProfile()` |
| `"callbacks"`, and each event's name | `handle:On(...)` |
| `"ui.surface"` | one page through `handle:RegisterSurface(...)` and its lifecycle methods |

### `OlympusAPI.Register(addonName)`

Returns your addon's **handle**, or `nil` and a reason:

| Reason | Why |
|---|---|
| `"name"` | not a string, empty, longer than 64 characters, or with a vertical bar or a control character |
| `"self"` | Olympus's own name |
| `"unknown"` | no installed addon has that name |
| `"taken"` | that name was already registered this session (a handle is given once per session, to the first caller) |
| `"full"` | 16 addons already registered this session |
| `"consent"` | the privacy page could not take the line (Olympus's privacy file is missing) |

Keep the handle in a local variable: it is your addon's own. `OlympusAPI` and every handle are
read-only tables. Every method works with `handle:Method(...)` and `handle.Method(...)` alike.

### `handle:Status()`

`"granted"`, `"refused"` or `"pending"`. Free: it never counts against the rate limit.

### `handle:Name()`

The name you registered.

### `handle:RegisterSurface(spec)`

Registers this handle's one client-owned page in the Olympus tab rail. The shared rail has one
client-owned slot per session (`OlympusAPI.SURFACE_LIMIT` is `1`); data handles remain available
when that slot is already occupied. Olympus places the page immediately before the built-in
Workshop tab. The caller cannot choose an internal key, replace an Olympus page or reorder the
normal pages. Registration does not select or build the page by itself.

`spec` is a table with these fields:

| Field | Required | Contract |
|---|---|---|
| `label` | yes | non-empty string, at most 96 bytes; used for the tab tooltip or bottom-tab text |
| `icon` | yes | non-empty texture path or positive file ID |
| `build(parent, context)` | yes | creates the page as children of `parent`; runs once for each Olympus window style |
| `portrait` | no | non-empty texture path or positive file ID shown in the shell while this page is selected |
| `visible()` | no | return `false` to hide the page; may run repeatedly and should be idempotent |
| `refresh(parent, context)` | no | updates the built page while selected; may run repeatedly and should be idempotent |
| `help(parent, context)` | no | handles the yellow title-bar help button while selected; without it Olympus opens its normal help |
| `availableWhenLocked` | no | boolean, `false` by default; `true` also offers the page beside the non-member Join screen |

`parent` fills the content area below the title bar. Olympus retains the outer frame, close and
help buttons, tab rails and portrait frame. Treat `context` as read-only. It has exactly the form
`{ style = "old" or "hd", apiVersion = 1 }` and contains no addon name, consent key or internal
owner key. The optional portrait applies only while this page is selected. Olympus's portrait
returns on its own pages.

The surface is independent of the data permission: registering, opening and refreshing it work
while `Status()` is `"pending"` or `"refused"`, and do not change that status or grant a data read.
The page's code still belongs to the calling addon. Olympus contains errors from its `visible`,
`build`, `refresh` and `help` callbacks so one page cannot stop the window or another page.

Returns `true`, or `false` and one of these reasons:

| Reason | Why |
|---|---|
| `"registered"` | this handle already registered its one surface |
| `"surface-full"` | the shared client-owned surface slot is already occupied; the handle remains usable for data and may retry later in another session |
| `"invalid-spec"` | `spec` is not a table |
| `"invalid-label"`, `"invalid-icon"`, `"invalid-portrait"` | that field has the wrong type or range |
| `"invalid-build"`, `"invalid-refresh"`, `"invalid-visible"`, `"invalid-help"` | that callback is missing when required or is not a function |
| `"invalid-locked-availability"` | `availableWhenLocked` is present and is not a boolean |
| `"unavailable"` | this Olympus build cannot host API surfaces |
| `"failed"` | the host rejected the call before it could return a more specific reason |

### `handle:OpenSurface()` and `handle:ToggleSurface()`

`OpenSurface` opens the Olympus window on this handle's registered page. `ToggleSurface` opens it,
or hides the Olympus window when that page is already selected. They return `true`, or `false` and
`"unregistered"`, `"unavailable"`, `"hidden"`, `"build-failed"` or `"failed"`. A `visible`
callback that returns false or raises an error makes the page `"hidden"`; a `build` callback that
raises an error makes it `"build-failed"` for that window style.

### `handle:RefreshSurface()`

Asks Olympus to re-evaluate this handle's registered page. If the page is selected, Olympus calls
its optional `refresh`. It returns `true`, or `false` and `"unregistered"`, `"unavailable"` or
`"failed"`. A refresh callback error is contained; the accepted refresh request still returns
`true` so a broken callback cannot escape through the host.

### `handle:IsSurfaceOpen()`

Returns `true` only when this handle's page is selected in the visible Olympus window, `false` when
it is not, or `false` and `"unregistered"`, `"unavailable"` or `"failed"` when the question could
not be answered.

### `handle:GetWanted()`

The Wanted list as the Wanted tab lists it, its entries in its order: each Horde player with a
bounty open or a kill of ours (one a member killed who killed none of ours, 0 points and 0 kills, is
not on it):

```lua
{
	{ place = 1, name = "Grashk Bloodfen-Emberfall", guid = "Player-4002-00C0FFEE", bounty = 42, kills = 3, cycle = 2 },
	...
}
```

`bounty` is the current bounty in points, `kills` the Olympus members he killed, counted as the
bounty counts them (the same member again within 10 minutes is one), `cycle` the bounty's cycle; `name` can be `nil` when the game has not told a name for that GUID. Never the
victims, the claims, the sightings, who added or took off an entry, nor any time.

### `handle:GetRankings([kind])`

Every public ranking (no argument), or one kind: `"slayers"`, `"donors"`, `"church"` or `"games"`.
A kind this build lacks, or one with nothing public now (the Church's ranking closed, the
Treasury's ranking not shown to the army), is `nil`.

```lua
{
	slayers = {
		month = { { place = 1, name = "Torvin Hale-Emberfall", points = 70, claims = 1 }, ... }, -- this month, at most 50
		all = { ... },     -- all time, at most 50
		signed = { ... },  -- the signed top three this client holds, when it holds one (name nil when unknown)
	},
	donors = { all = { "Name-Realm", ... } }, -- the all-time top three (see below)
	church = { missionaries = { "Name-Realm", ... }, apostles = { "Name-Realm", ... } }, -- its public top three
	games = { -- only the games the King made public
		arena = { { place = 1, name = "Name-Realm", rating = 1520, wins = 9, losses = 2 }, ... },
		bones = { { place = 1, name = "Name-Realm", games = 12, won = 8 }, ... },
	},
}
```

The Slayers boards are this client's own (what it observed), as the Wanted tab says. A game the
King keeps to the staff is not there, whoever the player is. Lottery results are private history
and never appear in rankings, including when an older client published a Lottery ranking word.

`donors` is there only while the King shows every member the Treasury's ranking (it is off until he
does), whoever the player is: the King's and the Treasury keepers' own view never counts. `all` is
the all-time top three, which head that ranking. `donors.month`, the month's top three, comes only
in a build whose honour frames show them (the koi; 1.2.4 shows it): still check for it.

### `handle:GetProfile()`

The player himself. In an Olympus guild:

```lua
{ member = true, name = "Lida Fenn-Emberfall", guild = "Olympus Ember", rank = "Member", rankIndex = 3,
	role = "member", frame = "donor-top-3", title = "Friend of the Treasury" }
```

`rankIndex` is 0 for the guild master. `role` is the highest he holds: `"king"`, `"councillor"`,
`"steward"`, `"treasurer"`, `"guildmaster"`, `"officer"` or `"member"`. `frame` is the frame his
profile shows: an honour's key, `"rank"` (his rank's frame) or `"none"`. `title` is his title's
words, or `nil`.

Outside an Olympus guild it is `{ member = false }`, and `GetWanted` and `GetRankings` return
`nil, "guild"`.

### `handle:On(event, fn)` and `handle:Off(event[, fn])`

`On` adds a callback and returns `true` (`false` for an unknown event, a non-function, or past 4
callbacks for that event). `Off` removes that callback, or every one of yours for the event
without `fn`.

| Event | `fn(event, ...)` | When |
|---|---|---|
| `WANTED_CHANGED` | `fn(event, rows)`: what `GetWanted()` returns | the Wanted list changed |
| `RANKINGS_CHANGED` | `fn(event, rankings)`: what `GetRankings()` returns | a public ranking changed |
| `PROFILE_CHANGED` | `fn(event, profile)`: what `GetProfile()` returns | the frame, title, guild, rank or role changed, or the player joined or left an Olympus guild |
| `PERMISSION_CHANGED` | `fn(event, status)`: `"granted"` or `"refused"` | the player answered your line |

- The data events come only while the player's answer is Yes (`WANTED_CHANGED` and
  `RANKINGS_CHANGED` only in an Olympus guild), and only when the data you would get differs from
  what you were last told: you may register before the Yes. `On` and the Yes take the data as it is
  then as told, so no event comes for it: read it yourself once (`Status()` is `"granted"`, or
  `PERMISSION_CHANGED` with `"granted"`), as the examples below do.
- A burst of changes is told once, about 2 seconds after it, never in combat (it waits for the
  combat to end).
- Each callback gets its own copy, and its call never counts against the rate limit.
- A callback that raises an error is caught: Olympus logs it with your addon's name, and Olympus and
  the other callbacks go on. A callback that fails 3 times is removed.

### Failures

Every data method returns `nil` and a reason when it gives nothing:

| Reason | Why |
|---|---|
| `"pending"`, `"refused"` | no Yes from the player |
| `"guild"` | the player is in no Olympus guild |
| `"busy"` | more than 20 data calls from your addon in 10 seconds: wait, or use the callbacks |
| `"kind"` | `GetRankings` was given an unknown kind |

## What it never gives

The census of the guilds, other players' private data, a location (the Wanted page's victims and
sightings stay on the page), the GUID of an Olympus member, the times of anyone's activity, the
staff's views, or any secret: no key, no sealed channel name, no signature, no private list.
Each row is built field by field from the page's own data, so what Olympus adds to its own tables
later never reaches your addon unless this contract adds it.

## What it is not

Every addon runs in the same Lua environment, so this is a courtesy boundary, not a lock: an
addon could read Olympus's saved variables directly. The API is the supported and consented way
in: it asks the player, gives your addon a stable contract, and keeps Olympus from handing out
anything on its own. Please use it, and only for what the player said Yes to.

Olympus's line on the privacy page tells the player that Olympus sends nothing for your addon and
that what your addon does with what it read is up to your addon, so that he says Yes only to addons
he trusts. Keep that trust: what he says Yes to is your addon reading, not it sending what it read
to other players.

## Examples

Marking Wanted Horde players on your nameplates, by GUID:

```lua
local wanted = {}
local function Take(rows)
	wipe(wanted)
	for _, r in ipairs(rows or {}) do if r.guid then wanted[r.guid] = r.bounty end end
end
api:On("WANTED_CHANGED", function(_, rows) Take(rows) end)
api:On("PERMISSION_CHANGED", function(_, status)
	if status == "granted" then Take(api:GetWanted()) else wipe(wanted) end
end)
if api:Status() == "granted" then Take(api:GetWanted()) end

local function Bounty(unit) return wanted[UnitGUID(unit) or ""] end
```

Showing the month's top Slayer:

```lua
local function TopSlayer()
	local slayers = api:GetRankings("slayers")
	local first = slayers and slayers.month[1]
	return first and first.name, first and first.points
end
```

Showing the player's own title in your frame. The data events come only when something changes,
so read it once at the start and on the player's Yes too:

```lua
local function ShowTitle(profile)
	MyFrame.title:SetText(profile and profile.member and profile.title or "")
end
api:On("PROFILE_CHANGED", function(_, profile) ShowTitle(profile) end)
api:On("PERMISSION_CHANGED", function(_, status)
	if status == "granted" then ShowTitle(api:GetProfile()) else ShowTitle(nil) end
end)
if api:Status() == "granted" then ShowTitle(api:GetProfile()) end
```
