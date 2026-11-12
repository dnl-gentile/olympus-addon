local ADDON, ns = ...
local L = ns.L

-- 1.2, the Blood Arena: the words of the fights part (fights and honours; the chat marks part's few strings too), English then a ptBR block (the pattern of
-- Locales.lua). Empty until that package fills it; loaded before Core.lua (Olympus.toc).

-- The fighter's nickname (the design): two fixed lists, never free text (the King's screen shows it).
-- ARENA_EPI_ORDER: "an" (adjective, noun) or "na" (noun, adjective); ARENA_EPI_FMT puts the two.
L.ARENA_EPI_A = { "Unbroken", "Crimson", "Silent", "Iron", "Golden", "Swift", "Grim", "Wild", "Stone", "Storm", "Night", "Blood",
	"Ashen", "Frost", "Burning", "Hollow", "Steel", "Thunder", "Shadow", "Radiant", "Savage", "Ancient", "Restless", "Fearless",
	"Grinning", "Howling", "Scarlet", "Bitter", "Dauntless", "Laughing", "Wandering", "Last" }
L.ARENA_EPI_N = { "Wolf", "Hammer", "Storm", "Blade", "Fang", "Shield", "Lion", "Bear", "Serpent", "Hawk", "Raven", "Boar", "Stag",
	"Fist", "Anvil", "Thorn", "Viper", "Tempest", "Warden", "Reaper", "Butcher", "Hound", "Gryphon", "Tiger", "Oak", "Axe", "Spear",
	"Flame", "Ghost", "Dragon", "Kodo", "Murloc" }
L.ARENA_EPI_ORDER = "an"
L.ARENA_EPI_FMT = "the %s %s"

-- The honours' titles (the design): one table, so the moderators can edit them. A class's and a
-- race's are patterns with the class's or the race's name (gold, silver, bronze).
L.HONOR_TITLES = {
	["arena-champion"] = "Arena Champion", ["arena-champion-2"] = "Arena Contender", ["arena-champion-3"] = "Arena Challenger",
	["donor-top-1"] = "Patron of Olympus", ["donor-top-2"] = "Benefactor of Olympus", ["donor-top-3"] = "Friend of the Treasury",
	["donor-month-1"] = "Golden Hand", ["donor-month-2"] = "Silver Hand", ["donor-month-3"] = "Bronze Hand",
	-- (1.5.5: the level race is off; its gold comet is the Olympus Speedrunner's alone, bronze and silver retired.)
	["level-race-60"] = "The Olympus Speedrunner",
	["guild-top-leader"] = "Wisest of Olympus",
	["oracle-1"] = "Oracle", ["oracle-2"] = "Seer", ["oracle-3"] = "Soothsayer",
	["missionary-1"] = "Good Shepherd", ["missionary-2"] = "Faithful Shepherd", ["missionary-3"] = "Shepherd",
	-- (1.2.4)
	["apostle-1"] = "Light of Olympus", ["apostle-2"] = "Voice of Olympus", ["apostle-3"] = "Herald of Olympus",
	["bones-1"] = "Master of Bones", ["bones-2"] = "Luck's Favourite", ["bones-3"] = "Steady Hand",
	["wanted-slayer-1"] = "Bane of the Horde", ["wanted-slayer-2"] = "Horde Hunter", ["wanted-slayer-3"] = "Bounty Hunter",
	["the-dev"] = "The Royal Dev",
}
L.HONOR_CLASS_TITLE = { "%s Champion", "%s Contender", "%s Challenger" }
L.HONOR_RACE_TITLE = { "Best %s Fighter", "%s Contender", "%s Challenger" }
L.HONOR_CLASS_NAMES = { warrior = "Warrior", paladin = "Paladin", hunter = "Hunter", rogue = "Rogue", priest = "Priest", shaman = "Shaman",
	mage = "Mage", warlock = "Warlock", druid = "Druid" }
L.HONOR_RACE_NAMES = { human = "Human", dwarf = "Dwarf", nightelf = "Night Elf", gnome = "Gnome", orc = "Orc", undead = "Undead",
	tauren = "Tauren", troll = "Troll" }
L.HONOR_METAL_GOLD, L.HONOR_METAL_SILVER, L.HONOR_METAL_BRONZE = "gold", "silver", "bronze"

-- The King's letter (the design): one per family, in his voice, naming the honour's title (%s);
-- signed by his title alone, never a name. (1.2.4, the author: the King talks the way he talks on
-- stream, plain and blunt, not a herald's speech.)
L.HONOR_LETTER_HEAD = "A letter from the King"
L.HONOR_LETTER_SIGN = "- The King"
L.HONOR_LETTER_WEAR = "Wear it"
-- (1.2.4: Most Wanted's Slayer letter, its first button: the Wanted tab.)
L.HONOR_LETTER_SLAYERS = "Slayers"
L.HONOR_LETTER_LATER = "Later"
-- (1.5.5: the level race's apology, its name in the lists of letters; and a retired comet's letter's, a
-- bronze or silver one kept from the race.)
L.HONOR_APOLOGY_TITLE = "The level race"
L.HONOR_RETIRED_TITLE = "A retired comet"
L.HONOR_LETTER_PREVIEW_HEAD = "Preview: the King's letters"
L.HONOR_LETTER_PREVIEW_ONLY = "Preview only"
L.HONOR_LETTER_PREVIEW_NOTE = "Choose a letter to inspect its existing parchment, frame and text. These are fictional examples: no honour is awarded, worn, saved or sent, and real waiting letters are not consumed."
L.HONOR_LETTER_PREVIEW_BACK = "< Back to the Realm" -- (its page's first row: the Realm again)
L.HONOR_LETTER = {
	arena = "Okay, listen.\n\nYou walked into the arena and beat everybody. Not most people. Everybody. So you're %s now, and the gryphon is yours.\n\nHeads up: every tryhard in Olympus wants it off you now. Don't let them.",
	class = "Hey,\n\nI checked. Of everyone playing your class in Olympus, nobody fights like you. That's huge. You're %s now.\n\nThe rest of them are gonna study every move you make. Let them. They still won't keep up.",
	race = "Hey,\n\nYour whole race just got a new name to brag about, and it's yours. You're %s now.\n\nGo show your people how it's done.",
	["donor-top"] = "Dude,\n\nYou've put more gold into Olympus than almost anyone. That's not a little, that's insane. You're %s, and the cornucopia stays yours as long as you stay in the top three.\n\nI see it, and so does everybody else. Thank you.",
	["donor-month"] = "Hey,\n\nLast month your gold kept the lights on in Olympus. Genuinely, thank you. You're %s, and the koi is yours for the month.\n\nKeep that hand open.",
	-- (1.5.5: the Olympus Speedrunner's letter, the gold comet; and the level race's apology, once, to whoever
	-- was told of a comet, saw one or wore one: no honour named, nothing to wear.)
	level = "Okay, listen.\n\nYou hit 60 before anybody else in Olympus. Fastest of all of us. So now you're %s, and the gold comet is yours.\n\nNobody can take that one from you. Respect.",
	apology = "Hey,\n\nAbout the level race. We had problems in its first days, and not everyone could be witnessed. The comet you saw came from a bug.\n\nSo the race is off. Sorry about that.\n\nNew things are coming.",
	-- (1.5.5: a bronze or silver comet's letter kept from the race, read again: plain, no title to name.)
	["level-retired"] = "Hey,\n\nThis comet came from the level race, and the race is off. It is retired now: nobody wears it anymore.",
	guild ="Listen,\n\nYour guild has the highest levels in all of Olympus. Top of the list. You're %s, and the owl sits on your banner while your guild stays first.\n\nKeep your people climbing, because the others are coming.",
	oracle = "Okay,\n\nLast month you called the arena better than anyone. Fight after fight, you just knew. You're %s, and the raven is yours this month.\n\nEverybody's gonna copy your picks now. Can't blame them.",
	missionary = "Hey,\n\nIn the last thirty days you brought more people into our guilds than almost anyone. That's how Olympus grows. You're %s, and the shepherd's crook is yours while you stay in the top three.\n\nKeep bringing them in.",
	-- (1.2.4)
	apostle = "Hey,\n\nIn the last thirty days barely any Apostle brought as many people to Olympus as you did. You're %s, and the cross is yours while you stay in the top three.\n\nKeep the faith. And keep them coming.",
	bones = "Okay,\n\nThe tavern is still talking about your throws last month. Some of those were actually insane. You're %s, and the lucky charm is yours for the month.\n\nMay the bones keep falling your way.",
	["wanted-slayer"] = "Okay,\n\nThe Horde keeps counting its dead, and your name keeps coming up. That's what I like to see. You're %s now.\n\nRide the skeletal horse right where the Horde can see it. Let them know who did it.",
}

-- 1.2.4, the notices (HonorsNet.Tell): every move on a list after the King's first letter for its
-- place, a strip at the top of the screen and a line in chat. Each list's name, a place's words,
-- and the lines.
L.HONOR_RANKING = { ["donor-top"] = "Top donors", ["donor-month"] = "Donors of the month", guild = "Best guild",
	["wanted-slayer"] = "Slayers", apostle = "Apostles", missionary = "Missionaries", bones = "Bones" }
L.HONOR_PLACE = { "1st", "2nd", "3rd" }
L.HONOR_NOTICE_DOWN = "%s: you dropped to %s place."
L.HONOR_NOTICE_OUT = "%s: you are off the list, and its frame is no longer yours."
L.HONOR_NOTICE_BACK = "%s: you are back on the list, in %s place."
L.HONOR_NOTICE_UP = "%s: you regained %s place."
L.HONOR_NOTICE_GUILD_OUT = "Best guild: your guild is no longer first, and the owl is no longer yours."
L.HONOR_NOTICE_GUILD_BACK = "Best guild: your guild is first again, and the owl is yours again."
L.HONOR_NOTICE_SINCE = "Since your last visit: %s."
L.HONOR_NOTICE_PART_PLACE = "%s, %s place"
L.HONOR_NOTICE_PART_OUT = "%s, off the list"
L.HONOR_NOTICE_MORE = "%d more"

-- The rankings' switches (the owner's one compact view).
L.ARENA_PERIOD_TODAY = "Today"
L.ARENA_PERIOD_WEEK = "This week"
L.ARENA_PERIOD_MONTH = "This month"
L.ARENA_PERIOD_ALL = "All time"
L.ARENA_CAT_GLOBAL = "Global"
L.ARENA_CLASS_NAMES = { WA = "Warrior", PA = "Paladin", HU = "Hunter", RO = "Rogue", PR = "Priest", SH = "Shaman", MA = "Mage", WL = "Warlock", DR = "Druid" }
L.ARENA_RACE_NAMES = { [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "Night Elf", [5] = "Undead", [6] = "Tauren", [7] = "Gnome", [8] = "Troll" }

-- Fight Nights, tournaments, the week's rows.
L.ARENA_CARD_NO = "Fight Night #%d"
L.ARENA_TOURNEY = "Tournament"
L.ARENA_WEEK_CARD_TIP = "The Blood Arena: %d bouts. Open the Arena tab for the card."
L.ARENA_WEEK_FIGHT = "%s vs %s"

-- 1.2.3, the duels: a challenge refused for a reason (Kit.Why), and a confirmed win that earned no
-- qualification points (ArenaFights.QualNote: the opponent, then why).
L.FIGHTS_WHY_BUSY = "You already have a duel open with this player: fight it first, or let it lapse."
L.FIGHTS_WHY_EXPIRED = "That challenge lapsed."
L.ARENA_QUAL_NONE = "Your win over %s earned no qualification points: %s."
L.ARENA_QUAL_WHY_NATIVE = "the game did not end that duel here (no duel finished)"
L.ARENA_QUAL_WHY_REPORT = "the two clients did not report the same result"
L.ARENA_QUAL_WHY_INT = "one of you was killed by something else during the duel"
L.ARENA_QUAL_WHY_UNSEEN = "your game did not see both characters during the duel (target your opponent)"
L.ARENA_QUAL_WHY_GUILD = "one of you is not in an Olympus guild"
L.ARENA_QUAL_WHY_REALM = "one of you is on a realm outside the realm group"
L.ARENA_QUAL_WHY_LEVEL = "a level could not be read"
L.ARENA_QUAL_WHY_SHORT = "it lasted under 15 seconds, or its length was not seen"
L.ARENA_QUAL_WHY_DAY = "your 10 counted duels for today are done"
L.ARENA_QUAL_WHY_PAIR = "3 counted duels against this opponent in 7 days are done"
L.ARENA_QUAL_WHY_LEVELS = "your opponent is 10 or more levels below you (0 points)"

-- The Chronicle's lines (what this client saw done).
L.ARENA_CHRONICLE_CORRECT = "corrected the result of fight %s, round %d"
L.ARENA_CHRONICLE_RULED = "ruled fight %s, round %d, himself (no duel line agreed)"
L.ARENA_CHRONICLE_SEASON = "opened arena season %d"
L.ARENA_CHRONICLE_TAKEOVER = "took over tournament %s"
L.ARENA_CHRONICLE_DRAW = "draw disputed: tournament %s, step %d (the roll seen here differs)"
L.ARENA_CHRONICLE_WORD = "belt word %s for %s"
L.ARENA_CHRONICLE_DISPUTED = "fight %s, round %d: the arbiter's duel line against the reports (disputed)"

-- The person card. (The history's Consent line, ARENA_CONSENT_HISTORY and its _TEXT, is
-- ArenaHomeText.lua's alone: that file loads after this one, so a copy here never showed.)
L.ARENA_PERSON_LINE = "Arena: %d  (%d-%d)"
L.ARENA_PERSON_PROFILE = "Arena profile"
-- (1.1.6, the games' ledger: the privacy page's one line, Consent.Intro)
L.CONSENT_GAMES_RECORDED = "Game results are recorded: each game you play (Bones, the Arena, the Lottery's practice: when, who, the result and the score) shows in your own list and goes to the King, the High Council and the author (and the auditors he signs), nobody else."

-- "My profile" (ProfileEdit.lua, 1.2.4: the player's own page in the Olympus window). Frames,
-- titles and honours are the whole addon's, not the arena's alone: no "arena profile" in these words.
L.PROFILE_FRAME_RANK = "My rank's frame"
L.PROFILE_FRAME_NONE = "No frame"
L.PROFILE_FRAME_RED_CROSS = "Red cross (only you see it)"
L.PROFILE_TITLE_NONE = "No title"
L.PROFILE_LOCK = "Keep my pick"
L.PROFILE_LOCKED = "Pick kept"
L.PROFILE_HONOURS = "Your honours"
L.PROFILE_NO_HONOURS = "None yet: belts, podiums, donations, the Oracle, the best guild."
L.PROFILE_ICON_REFUSED = "That icon can't be used here: pick one of your honours' marks (or, for your emblem, one of the game's icons)."
L.HONOR_LETTER_WAITING = "A letter from the King awaits you: open the Olympus window (or My profile, in it) to read it."
L.MYPROFILE_TITLE = "My profile"
L.MYPROFILE_LINK = "My profile"
L.MYPROFILE_NAV_LOOK = "Look"
L.MYPROFILE_NAV_ICONS = "Icons"
L.MYPROFILE_NAV_PRIVACY = "Who sees what"
L.MYPROFILE_NAV_LETTERS = "Letters (%d)"
L.MYPROFILE_SEEN_TITLE = "As others see you"
L.MYPROFILE_SEEN_TEXT = "Title: %s\nNickname: %s"
L.MYPROFILE_OWN_LOOK = "On your screen only: %s"
L.MYPROFILE_RED_CROSS = "Red cross"
L.MYPROFILE_FRAME_HEAD = "Frame"
L.MYPROFILE_TITLE_HEAD = "Title"
L.MYPROFILE_NICK_HEAD = "Nickname"
L.MYPROFILE_EMBLEM_HEAD = "Emblem"
L.MYPROFILE_ICON_HEAD = "Council icon"
L.MYPROFILE_FRAME_LATER = "comes in a later version"
L.MYPROFILE_EPITHET = "Epithet: %s"
L.MYPROFILE_BEAST = "Beast: %s"
L.MYPROFILE_NONE_WORD = "none"
L.MYPROFILE_NICK_NONE = "No nickname"
L.MYPROFILE_CHOOSE_EMBLEM = "Choose an emblem"
L.MYPROFILE_CHOOSE_ICON = "Choose your council icon"
L.MYPROFILE_LOCK_TIP = "A new honour no longer switches your frame and title automatically."
L.MYPROFILE_EMBLEM_SAMPLE = "Your emblem: %s"
L.MYPROFILE_CHAT_SAMPLE = "In the chat: %s"
L.MYPROFILE_EMBLEM_HINT = "What it is for: your emblem shows in place of your portrait wherever your portrait can't show, as on the Games' cards. Click one, then Use this icon."
L.MYPROFILE_ICON_HINT = "Your mark, the silver dragon, always shows before your name in the game's chat (channels, say, party, whispers, guild chat); an icon after it is optional. Click one, then Use this icon."
L.MYPROFILE_USE = "Use this icon"
L.MYPROFILE_LOOK_PUBLIC = "Your frame, title, nickname and emblem go out on the Olympus channel: every member's addon shows them."
L.MYPROFILE_LOOK_KEPT = "Your frame, title, nickname and emblem don't go out on the Olympus channel from this character now: no member's addon gets them."
L.MYPROFILE_FACTS_HEAD = "What your page shows"
L.MYPROFILE_CHOICES_HEAD = "Your choices"
L.MYPROFILE_PRIVACY_PAGE = "Open the privacy page"
L.MYPROFILE_LETTERS_NONE = "No letters yet."
L.MYPROFILE_GAMES_OFF = "Your frame, title and nickname go out with the Games, which are off on this character."
L.MYPROFILE_GAMES_PROFILE = "Games profile"
-- (1.2.4) A letter held in an instance or Busy: its chat line, and its words on the Decrees tab.
L.HONOR_LETTER_HELD = "A letter from the King awaits you: it opens once you are out of the instance and not Busy (or open the Olympus window to read it now)."
L.HELD_HONOR_LETTER = "a letter from the King"

-- (1.2.6) Watch duel (ArenaSpectate.lua): the menu line, the command and the duel view's words that
-- its data gives (the view's own titles and buttons are the companion's).
L.ARENA_MENU_WATCH_DUEL = "Watch duel"
L.ARENA_MENU_WATCH_DUEL_TIP = "Both fighters side by side: health, power and casts while they are in sight; gear and talents from your own inspection. Shown on your screen only: nothing is sent or saved."
L.ARENA_HELP_WATCH = "/oly arena watch [name|off] - watch a duel: your own, your target and his target, or your target and your focus; off closes it"
L.ARENA_WATCH_NONE = "No duel to watch: target one of the fighters (or target one and focus the other)."
L.ARENA_WATCH_NO_SIGHT = "%s is not in sight with an opponent: target him, focus him or show friendly nameplates."
L.ARENA_WATCH_NOT_OLYMPUS = "Not an Olympus duel"
L.ARENA_WATCH_FIGHT_LINE = "Best of %d · Round %d · %d : %d"
L.ARENA_WATCH_WON_KO = "%s wins by knockout"
L.ARENA_WATCH_WON_FLED = "%s wins: %s fled"
L.ARENA_WATCH_ROUND_KO = "Last round: %s by knockout"
L.ARENA_WATCH_ROUND_FLED = "Last round: %s, %s fled"
L.ARENA_WATCH_WHO = "%s · %s · Level %d"
L.ARENA_WATCH_DASH = "-"
L.ARENA_WATCH_ST_SIGHT = "Not in sight: target, focus or show friendly nameplates"
L.ARENA_WATCH_ST_RANGE = "Waiting for inspection - move within inspect range"
L.ARENA_WATCH_ST_INSPECTING = "Inspecting..."
L.ARENA_WATCH_ST_DONE = "Inspected %d min ago"
L.ARENA_WATCH_ST_NOW = "Inspected just now"
L.ARENA_WATCH_ST_COMBAT = "After combat"
L.ARENA_WATCH_ST_BUSY = "Close the Inspect window to continue"
L.ARENA_WATCH_ST_REFUSED = "This player cannot be inspected here"
L.ARENA_WATCH_ST_OWN = "Your own gear and talents"
L.ARENA_WATCH_STATS = "Stats from gear"
L.ARENA_WATCH_RESISTS = "Resistances"
L.ARENA_WATCH_STATS_NOTE = "Items only, enchants not counted"
L.ARENA_WATCH_STAT_STR = "Strength"
L.ARENA_WATCH_STAT_AGI = "Agility"
L.ARENA_WATCH_STAT_STA = "Stamina"
L.ARENA_WATCH_STAT_INT = "Intellect"
L.ARENA_WATCH_STAT_SPI = "Spirit"
L.ARENA_WATCH_STAT_ARMOR = "Armor"
L.ARENA_WATCH_STAT_AP = "Atk power"
L.ARENA_WATCH_STAT_SP = "Spell power"
L.ARENA_WATCH_STAT_CRIT = "Crit rating"
L.ARENA_WATCH_STAT_HIT = "Hit rating"
L.ARENA_WATCH_STAT_HASTE = "Haste rating"
L.ARENA_WATCH_RES_HOLY = "Holy"
L.ARENA_WATCH_RES_FIRE = "Fire"
L.ARENA_WATCH_RES_NATURE = "Nature"
L.ARENA_WATCH_RES_FROST = "Frost"
L.ARENA_WATCH_RES_SHADOW = "Shadow"
L.ARENA_WATCH_RES_ARCANE = "Arcane"
L.ARENA_WATCH_TALENTS = "Talents"
L.ARENA_WATCH_POINTS = "%d points"
L.ARENA_WATCH_NO_TALENTS = "Talents not shown on this client"
L.ARENA_WATCH_POINTS_ONLY = "This client gives the points per tree only"
L.ARENA_WATCH_PASSIVE = "Passive"
L.ARENA_WATCH_ACTIVE = "Active"
L.ARENA_WATCH_RANK = "Rank %d / %d"

if GetLocale and GetLocale() == "ptBR" then
	L.ARENA_EPI_A = { "Inquebrável", "Carmesim", "Silencioso", "de Ferro", "de Ouro", "Veloz", "Sombrio", "Selvagem", "de Pedra", "da Tempestade",
		"da Noite", "de Sangue", "Cinzento", "Gélido", "Ardente", "Vazio", "de Aço", "do Trovão", "das Sombras", "Radiante", "Feroz", "Ancestral",
		"Inquieto", "Destemido", "Risonho", "Uivante", "Escarlate", "Amargo", "Intrépido", "Gargalhante", "Errante", "Derradeiro" }
	L.ARENA_EPI_N = { "Lobo", "Martelo", "Temporal", "Gume", "Dente", "Escudo", "Leão", "Urso", "Serpente", "Falcão", "Corvo", "Javali", "Cervo",
		"Punho", "Malho", "Espinho", "Víbora", "Furacão", "Guardião", "Ceifador", "Açougueiro", "Cão", "Grifo", "Tigre", "Carvalho", "Machado",
		"Arpão", "Fogo", "Fantasma", "Dragão", "Kodo", "Murloc" }
	L.ARENA_EPI_ORDER = "na"
	L.ARENA_EPI_FMT = "o %s %s"
	L.HONOR_TITLES = {
		["arena-champion"] = "Campeão da Arena", ["arena-champion-2"] = "Desafiante da Arena", ["arena-champion-3"] = "Pretendente da Arena",
		["donor-top-1"] = "Patrono do Olympus", ["donor-top-2"] = "Benfeitor do Olympus", ["donor-top-3"] = "Amigo do Tesouro",
		["donor-month-1"] = "Mão de Ouro", ["donor-month-2"] = "Mão de Prata", ["donor-month-3"] = "Mão de Bronze",
		["level-race-60"] = "O Speedrunner do Olympus",
		["guild-top-leader"] = "O Mais Sábio do Olympus",
		["oracle-1"] = "Oráculo", ["oracle-2"] = "Vidente", ["oracle-3"] = "Adivinho",
		["missionary-1"] = "Bom Pastor", ["missionary-2"] = "Pastor Fiel", ["missionary-3"] = "Pastor",
		["apostle-1"] = "Luz do Olympus", ["apostle-2"] = "Voz do Olympus", ["apostle-3"] = "Arauto do Olympus",
		["bones-1"] = "Mestre dos Ossos", ["bones-2"] = "Favorito da Sorte", ["bones-3"] = "Mão Firme",
		["wanted-slayer-1"] = "Ruína da Horda", ["wanted-slayer-2"] = "Caçador da Horda", ["wanted-slayer-3"] = "Caçador de Recompensas",
		["the-dev"] = "The Royal Dev",
	}
	L.HONOR_CLASS_TITLE = { "Campeão %s", "Desafiante %s", "Pretendente %s" }
	L.HONOR_RACE_TITLE = { "Melhor Lutador %s", "Desafiante %s", "Pretendente %s" }
	L.HONOR_CLASS_NAMES = { warrior = "Guerreiro", paladin = "Paladino", hunter = "Caçador", rogue = "Ladino", priest = "Sacerdote", shaman = "Xamã",
		mage = "Mago", warlock = "Bruxo", druid = "Druida" }
	L.HONOR_RACE_NAMES = { human = "Humano", dwarf = "Anão", nightelf = "Elfo Noturno", gnome = "Gnomo", orc = "Orc", undead = "Morto-vivo",
		tauren = "Tauren", troll = "Troll" }
	L.HONOR_METAL_GOLD, L.HONOR_METAL_SILVER, L.HONOR_METAL_BRONZE = "ouro", "prata", "bronze"
	L.HONOR_LETTER_HEAD = "Uma carta do Rei"
	L.HONOR_LETTER_SIGN = "- O Rei"
	L.HONOR_LETTER_WEAR = "Usar"
	L.HONOR_LETTER_SLAYERS = "Slayers"
	L.HONOR_LETTER_LATER = "Depois"
	L.HONOR_APOLOGY_TITLE = "A corrida de level"
	L.HONOR_RETIRED_TITLE = "Um cometa aposentado"
	L.HONOR_LETTER_PREVIEW_HEAD = "Prévia: cartas do Rei"
	L.HONOR_LETTER_PREVIEW_ONLY = "Só prévia"
	L.HONOR_LETTER_PREVIEW_NOTE = "Escolha uma carta para conferir seu pergaminho, moldura e texto existentes. São exemplos fictícios: nenhuma honraria é concedida, usada, salva ou enviada, e cartas reais pendentes não são consumidas."
	L.HONOR_LETTER_PREVIEW_BACK = "< Voltar ao Reino"
	L.HONOR_LETTER = {
		arena = "Olha só.\n\nVocê entrou na arena e ganhou de todo mundo. Não da maioria. De todo mundo. Agora você é %s, e o grifo é seu.\n\nSó avisando: todo tryhard do Olympus vai querer tirar ele de você. Não deixa.",
		class = "E aí,\n\nEu conferi. De todo mundo da sua classe no Olympus, ninguém luta como você. Isso é enorme. Agora você é %s.\n\nO resto vai estudar cada movimento seu. Deixa. Mesmo assim não vão te acompanhar.",
		race = "E aí,\n\nA sua raça inteira ganhou um nome novo pra se gabar, e é o seu. Agora você é %s.\n\nVai lá mostrar pro seu povo como se faz.",
		["donor-top"] = "Cara,\n\nVocê colocou mais ouro no Olympus do que quase todo mundo. Isso não é pouca coisa, é insano. Você é %s, e a cornucópia fica com você enquanto estiver entre os três primeiros.\n\nEu vejo, e todo mundo vê também. Valeu mesmo.",
		["donor-month"] = "E aí,\n\nNo mês passado o seu ouro manteve as luzes do Olympus acesas. Sério, obrigado. Você é %s, e o koi é seu este mês.\n\nContinua com essa mão aberta.",
		level = "Ok, escuta.\n\nVocê chegou ao 60 antes de qualquer um no Olympus. O mais rápido de todos nós. Então agora você é %s, e o cometa de ouro é seu.\n\nEsse ninguém tira de você. Respeito.",
		apology = "Ei,\n\nSobre a corrida de level. Tivemos problemas nos primeiros dias, e nem todo mundo pôde ser testemunhado. O cometa que você viu veio de um bug.\n\nPor isso a corrida foi cancelada. Desculpa.\n\nCoisas novas vêm aí.",
		["level-retired"] = "Ei,\n\nEste cometa veio da corrida de level, e a corrida foi cancelada. Agora ele está aposentado: ninguém mais usa.",
		guild = "Escuta,\n\nA sua guilda tem os níveis mais altos de todo o Olympus. Topo da lista. Você é %s, e a coruja fica no seu estandarte enquanto a sua guilda for a primeira.\n\nMantém o seu pessoal subindo, porque os outros estão vindo.",
		oracle = "Olha,\n\nNo mês passado você leu a arena melhor que qualquer um. Luta após luta, você simplesmente sabia. Você é %s, e o corvo é seu este mês.\n\nAgora todo mundo vai copiar os seus palpites. Não dá pra culpar.",
		missionary = "E aí,\n\nNos últimos trinta dias você trouxe mais gente pras nossas guildas do que quase todo mundo. É assim que o Olympus cresce. Você é %s, e o cajado é seu enquanto estiver entre os três primeiros.\n\nContinua trazendo.",
		apostle = "E aí,\n\nNos últimos trinta dias quase nenhum Apóstolo trouxe tanta gente pro Olympus quanto você. Você é %s, e a cruz é sua enquanto estiver entre os três primeiros.\n\nMantém a fé. E continua trazendo.",
		bones = "Olha,\n\nA taverna ainda fala dos seus lances do mês passado. Alguns foram insanos de verdade. Você é %s, e o amuleto da sorte é seu este mês.\n\nQue os ossos continuem caindo a seu favor.",
		["wanted-slayer"] = "Olha só,\n\nA Horda continua contando os mortos, e o seu nome não para de aparecer. É isso que eu gosto de ver. Agora você é %s.\n\nMonta o cavalo esqueleto bem onde a Horda possa ver. Deixa eles saberem quem foi.",
	}
	L.HONOR_RANKING = { ["donor-top"] = "Maiores doadores", ["donor-month"] = "Doadores do mês", guild = "Melhor guilda",
		["wanted-slayer"] = "Slayers", apostle = "Apóstolos", missionary = "Missionários", bones = "Bones" }
	L.HONOR_PLACE = { "1º", "2º", "3º" }
	L.HONOR_NOTICE_DOWN = "%s: você caiu para o %s lugar."
	L.HONOR_NOTICE_OUT = "%s: você saiu da lista, e a moldura não é mais sua."
	L.HONOR_NOTICE_BACK = "%s: você voltou à lista, em %s lugar."
	L.HONOR_NOTICE_UP = "%s: você recuperou o %s lugar."
	L.HONOR_NOTICE_GUILD_OUT = "Melhor guilda: a sua guilda não é mais a primeira, e a coruja não é mais sua."
	L.HONOR_NOTICE_GUILD_BACK = "Melhor guilda: a sua guilda é a primeira de novo, e a coruja é sua outra vez."
	L.HONOR_NOTICE_SINCE = "Desde a sua última visita: %s."
	L.HONOR_NOTICE_PART_PLACE = "%s, %s lugar"
	L.HONOR_NOTICE_PART_OUT = "%s, fora da lista"
	L.HONOR_NOTICE_MORE = "mais %d"
	L.ARENA_PERIOD_TODAY = "Hoje"
	L.ARENA_PERIOD_WEEK = "Esta semana"
	L.ARENA_PERIOD_MONTH = "Este mês"
	L.ARENA_PERIOD_ALL = "Desde sempre"
	L.ARENA_CAT_GLOBAL = "Geral"
	L.ARENA_CLASS_NAMES = { WA = "Guerreiro", PA = "Paladino", HU = "Caçador", RO = "Ladino", PR = "Sacerdote", SH = "Xamã", MA = "Mago", WL = "Bruxo", DR = "Druida" }
	L.ARENA_RACE_NAMES = { [1] = "Humano", [2] = "Orc", [3] = "Anão", [4] = "Elfo Noturno", [5] = "Morto-vivo", [6] = "Tauren", [7] = "Gnomo", [8] = "Troll" }
	L.ARENA_CARD_NO = "Noite da Luta #%d"
	L.ARENA_TOURNEY = "Torneio"
	L.ARENA_WEEK_CARD_TIP = "A Arena de Sangue: %d lutas. Abra a aba Arena para ver o card."
	L.ARENA_WEEK_FIGHT = "%s contra %s"
	L.FIGHTS_WHY_BUSY = "Você já tem um duelo aberto com esse jogador: lutem esse primeiro, ou deixem expirar."
	L.FIGHTS_WHY_EXPIRED = "Esse desafio expirou."
	L.ARENA_QUAL_NONE = "Sua vitória sobre %s não deu pontos de qualificação: %s."
	L.ARENA_QUAL_WHY_NATIVE = "o jogo não encerrou esse duelo aqui (nenhum duelo terminado)"
	L.ARENA_QUAL_WHY_REPORT = "os dois clientes não relataram o mesmo resultado"
	L.ARENA_QUAL_WHY_INT = "um de vocês foi morto por outra coisa durante o duelo"
	L.ARENA_QUAL_WHY_UNSEEN = "este cliente não viu os dois personagens durante o duelo (mire no adversário)"
	L.ARENA_QUAL_WHY_GUILD = "um de vocês não está numa guilda Olympus"
	L.ARENA_QUAL_WHY_REALM = "um de vocês está num reino fora do grupo de reinos"
	L.ARENA_QUAL_WHY_LEVEL = "não deu para ler um nível"
	L.ARENA_QUAL_WHY_SHORT = "durou menos de 15 segundos, ou a duração não foi vista"
	L.ARENA_QUAL_WHY_DAY = "seus 10 duelos que contam hoje já foram"
	L.ARENA_QUAL_WHY_PAIR = "3 duelos que contam contra esse adversário em 7 dias já foram"
	L.ARENA_QUAL_WHY_LEVELS = "seu adversário está 10 ou mais níveis abaixo de você (0 pontos)"
	L.ARENA_CHRONICLE_CORRECT = "corrigiu o resultado da luta %s, round %d"
	L.ARENA_CHRONICLE_RULED = "decidiu a luta %s, round %d, ele mesmo (nenhuma linha de duelo concordou)"
	L.ARENA_CHRONICLE_SEASON = "abriu a temporada %d da arena"
	L.ARENA_CHRONICLE_TAKEOVER = "assumiu o torneio %s"
	L.ARENA_CHRONICLE_DRAW = "sorteio contestado: torneio %s, passo %d (a rolagem vista aqui é outra)"
	L.ARENA_CHRONICLE_WORD = "palavra de cinturão %s para %s"
	L.ARENA_CHRONICLE_DISPUTED = "luta %s, round %d: a linha de duelo do árbitro contra os relatos (contestada)"
	L.ARENA_PERSON_LINE = "Arena: %d  (%d-%d)"
	L.ARENA_PERSON_PROFILE = "Perfil da arena"
	L.CONSENT_GAMES_RECORDED = "Os resultados dos jogos ficam registrados: cada jogo que você joga (Bones, a Arena, o treino da Loteria: quando, quem, o resultado e o placar) aparece na sua própria lista e vai para o Rei, o Alto Conselho e o autor (e os auditores que ele assina), mais ninguém."
	L.PROFILE_ICON_REFUSED = "Esse ícone não serve aqui: escolha a marca de uma das suas honras (ou, para o emblema, um ícone do jogo)."
	L.HONOR_LETTER_WAITING = "Uma carta do Rei espera por você: abra a janela do Olympus (ou o Meu perfil, nela) para lê-la."
	L.HONOR_LETTER_HELD = "Uma carta do Rei espera por você: ela abre quando você sair da instância e não estiver Ocupado (ou abra a janela do Olympus para lê-la agora)."
	L.HELD_HONOR_LETTER = "uma carta do Rei"
	L.PROFILE_FRAME_RANK = "A moldura do meu posto"
	L.PROFILE_FRAME_NONE = "Sem moldura"
	L.PROFILE_FRAME_RED_CROSS = "Cruz vermelha (só você a vê)"
	L.PROFILE_TITLE_NONE = "Sem título"
	L.PROFILE_LOCK = "Manter a escolha"
	L.PROFILE_LOCKED = "Escolha mantida"
	L.PROFILE_HONOURS = "As suas honrarias"
	L.PROFILE_NO_HONOURS = "Nenhuma ainda: cinturões, pódios, doações, o Oráculo, a melhor guilda."
	L.MYPROFILE_TITLE = "Meu perfil"
	L.MYPROFILE_LINK = "Meu perfil"
	L.MYPROFILE_NAV_LOOK = "Visual"
	L.MYPROFILE_NAV_ICONS = "Ícones"
	L.MYPROFILE_NAV_PRIVACY = "Quem vê o quê"
	L.MYPROFILE_NAV_LETTERS = "Cartas (%d)"
	L.MYPROFILE_SEEN_TITLE = "Como os outros o veem"
	L.MYPROFILE_SEEN_TEXT = "Título: %s\nApelido: %s"
	L.MYPROFILE_OWN_LOOK = "Só na sua tela: %s"
	L.MYPROFILE_RED_CROSS = "Cruz vermelha"
	L.MYPROFILE_FRAME_HEAD = "Moldura"
	L.MYPROFILE_TITLE_HEAD = "Título"
	L.MYPROFILE_NICK_HEAD = "Apelido"
	L.MYPROFILE_EMBLEM_HEAD = "Emblema"
	L.MYPROFILE_ICON_HEAD = "Ícone do Conselho"
	L.MYPROFILE_FRAME_LATER = "chega numa versão futura"
	L.MYPROFILE_EPITHET = "Epíteto: %s"
	L.MYPROFILE_BEAST = "Fera: %s"
	L.MYPROFILE_NONE_WORD = "nenhum"
	L.MYPROFILE_NICK_NONE = "Sem apelido"
	L.MYPROFILE_CHOOSE_EMBLEM = "Escolher um emblema"
	L.MYPROFILE_CHOOSE_ICON = "Escolher o seu ícone do Conselho"
	L.MYPROFILE_LOCK_TIP = "Uma honraria nova não troca mais a sua moldura e o seu título sozinha."
	L.MYPROFILE_EMBLEM_SAMPLE = "Seu emblema: %s"
	L.MYPROFILE_CHAT_SAMPLE = "No chat: %s"
	L.MYPROFILE_EMBLEM_HINT = "Para que serve: o seu emblema aparece no lugar do seu retrato onde o retrato não pode aparecer, como nos cards dos Jogos. Clique em um e em Usar este ícone."
	L.MYPROFILE_ICON_HINT = "Sua marca, o dragão prateado, sempre aparece antes do seu nome no chat do jogo (canais, dizer, grupo, sussurros, chat da guilda); um ícone depois dela é opcional. Clique em um e em Usar este ícone."
	L.MYPROFILE_USE = "Usar este ícone"
	L.MYPROFILE_LOOK_PUBLIC = "A sua moldura, título, apelido e emblema saem no canal do Olympus: o addon de todo membro os mostra."
	L.MYPROFILE_LOOK_KEPT = "A sua moldura, título, apelido e emblema não saem agora no canal do Olympus deste personagem: nenhum addon de membro os recebe."
	L.MYPROFILE_FACTS_HEAD = "O que a sua página mostra"
	L.MYPROFILE_CHOICES_HEAD = "As suas escolhas"
	L.MYPROFILE_PRIVACY_PAGE = "Abrir a página de privacidade"
	L.MYPROFILE_LETTERS_NONE = "Nenhuma carta ainda."
	L.MYPROFILE_GAMES_OFF = "A sua moldura, título e apelido saem com os Jogos, que estão desligados neste personagem."
	L.MYPROFILE_GAMES_PROFILE = "Perfil nos Jogos"
	-- (1.2.6) Assistir ao duelo
	L.ARENA_MENU_WATCH_DUEL = "Assistir ao duelo"
	L.ARENA_MENU_WATCH_DUEL_TIP = "Os dois lutadores lado a lado: vida, poder e conjurações enquanto estão à vista; equipamento e talentos da sua própria inspeção. Só na sua tela: nada é enviado nem guardado."
	L.ARENA_HELP_WATCH = "/oly arena watch [nome|off] - assistir a um duelo: o seu, o do seu alvo com o alvo dele, ou o seu alvo e o seu foco; off fecha"
	L.ARENA_WATCH_NONE = "Nenhum duelo para assistir: mire um dos lutadores (ou mire um e foque o outro)."
	L.ARENA_WATCH_NO_SIGHT = "%s não está à vista com um oponente: mire-o, foque-o ou mostre as placas de nome aliadas."
	L.ARENA_WATCH_NOT_OLYMPUS = "Não é um duelo do Olympus"
	L.ARENA_WATCH_FIGHT_LINE = "Melhor de %d · Rodada %d · %d : %d"
	L.ARENA_WATCH_WON_KO = "%s vence por nocaute"
	L.ARENA_WATCH_WON_FLED = "%s vence: %s fugiu"
	L.ARENA_WATCH_ROUND_KO = "Última rodada: %s por nocaute"
	L.ARENA_WATCH_ROUND_FLED = "Última rodada: %s, %s fugiu"
	L.ARENA_WATCH_WHO = "%s · %s · Nível %d"
	L.ARENA_WATCH_DASH = "-"
	L.ARENA_WATCH_ST_SIGHT = "Fora de vista: mire, foque ou mostre as placas de nome aliadas"
	L.ARENA_WATCH_ST_RANGE = "Aguardando inspeção - chegue ao alcance de inspeção"
	L.ARENA_WATCH_ST_INSPECTING = "Inspecionando..."
	L.ARENA_WATCH_ST_DONE = "Inspecionado há %d min"
	L.ARENA_WATCH_ST_NOW = "Inspecionado agora"
	L.ARENA_WATCH_ST_COMBAT = "Depois do combate"
	L.ARENA_WATCH_ST_BUSY = "Feche a janela de Inspeção para continuar"
	L.ARENA_WATCH_ST_REFUSED = "Este jogador não pode ser inspecionado aqui"
	L.ARENA_WATCH_ST_OWN = "O seu próprio equipamento e talentos"
	L.ARENA_WATCH_STATS = "Atributos do equipamento"
	L.ARENA_WATCH_RESISTS = "Resistências"
	L.ARENA_WATCH_STATS_NOTE = "Só os itens, encantamentos não contam"
	L.ARENA_WATCH_STAT_STR = "Força"
	L.ARENA_WATCH_STAT_AGI = "Agilidade"
	L.ARENA_WATCH_STAT_STA = "Vigor"
	L.ARENA_WATCH_STAT_INT = "Intelecto"
	L.ARENA_WATCH_STAT_SPI = "Espírito"
	L.ARENA_WATCH_STAT_ARMOR = "Armadura"
	L.ARENA_WATCH_STAT_AP = "Poder de ataque"
	L.ARENA_WATCH_STAT_SP = "Poder mágico"
	L.ARENA_WATCH_STAT_CRIT = "Índice de crítico"
	L.ARENA_WATCH_STAT_HIT = "Índice de acerto"
	L.ARENA_WATCH_STAT_HASTE = "Índice de aceleração"
	L.ARENA_WATCH_RES_HOLY = "Sagrado"
	L.ARENA_WATCH_RES_FIRE = "Fogo"
	L.ARENA_WATCH_RES_NATURE = "Natureza"
	L.ARENA_WATCH_RES_FROST = "Gelo"
	L.ARENA_WATCH_RES_SHADOW = "Sombra"
	L.ARENA_WATCH_RES_ARCANE = "Arcano"
	L.ARENA_WATCH_TALENTS = "Talentos"
	L.ARENA_WATCH_POINTS = "%d pontos"
	L.ARENA_WATCH_NO_TALENTS = "Talentos não aparecem neste cliente"
	L.ARENA_WATCH_POINTS_ONLY = "Este cliente dá só os pontos por árvore"
	L.ARENA_WATCH_PASSIVE = "Passivo"
	L.ARENA_WATCH_ACTIVE = "Ativo"
	L.ARENA_WATCH_RANK = "Grau %d / %d"
end
