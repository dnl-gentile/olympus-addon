local _, ns = ...
local L = ns.L

L.FUGITIVES_WHISPER = "You are speaking with a known Olympus fugitive."
L.FUGITIVES_AUDIT = "Known Olympus fugitives on your guild roster: %s."
L.FUGITIVES_REMAINDER = "%d more"
L.FUGITIVES_HELP = "/oly fugitives paste: import a signed Olympus fugitive list."
L.FUGITIVES_PASTE = "Paste a signed Olympus fugitive list for this realm group and faction."
L.FUGITIVES_IMPORTED = "Signed Olympus fugitive list accepted."
L.FUGITIVES_REFUSED = "The Olympus fugitive list could not be accepted. Check its scope, date and revision."

if GetLocale and GetLocale() == "ptBR" then
	L.FUGITIVES_WHISPER = "Você está falando com um fugitivo conhecido do Olympus."
	L.FUGITIVES_AUDIT = "Fugitivos conhecidos do Olympus na sua guilda: %s."
	L.FUGITIVES_REMAINDER = "mais %d"
	L.FUGITIVES_HELP = "/oly fugitives paste: importe uma lista assinada de fugitivos do Olympus."
	L.FUGITIVES_PASTE = "Cole uma lista assinada de fugitivos do Olympus para este grupo de reinos e facção."
	L.FUGITIVES_IMPORTED = "Lista assinada de fugitivos do Olympus aceita."
	L.FUGITIVES_REFUSED = "A lista de fugitivos do Olympus não pôde ser aceita. Confira o reino, a facção, a data e a revisão."
end
