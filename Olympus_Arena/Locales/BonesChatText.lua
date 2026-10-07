local _, own = ...; local ns = own.host; if not ns then return end
local L = ns.L
L.BONES_CHAT_PLAYERS = "Players"
L.BONES_CHAT_EVERYONE = "Everyone"
L.BONES_CHAT_EXPAND = "Show chat"
L.BONES_CHAT_COLLAPSE = "Hide chat"
if GetLocale() == "ptBR" then
	L.BONES_CHAT_PLAYERS = "Jogadores"
	L.BONES_CHAT_EVERYONE = "Todos"
	L.BONES_CHAT_EXPAND = "Mostrar chat"
	L.BONES_CHAT_COLLAPSE = "Ocultar chat"
end
