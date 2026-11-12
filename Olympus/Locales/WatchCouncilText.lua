local ADDON, ns = ...
local L = ns.L
-- 1.2.1: the High Council's own sections in The Watch (Watch.lua: its reports and cases, apart from
-- any guild's), and what a trusted council collector keeps of a report.
L.WATCH_CASES_TITLE_COUNCIL = "Cases of the High Council"
L.WATCH_COUNCIL_TIP = "Reports from members of every Olympus guild, taken and passed on by a trusted council collector (the King's addon or the pinned addon author). It takes a report only from a reporter it already knows in the guild he names, and only with the lines it heard itself in the Olympus channel. The King and the High Council act on them in Olympus's chats, never with a guild's Watch. A report alone proves nothing."
L.WATCH_REPORT_LINES_COUNCIL = "%d of the %d lines it named. Only lines the receiving collector heard itself in the Olympus channel are kept."
L.WATCH_COUNCIL_DETAIL = "The High Council's reports and cases: from members of every Olympus guild, through a trusted council collector. Nothing here is a sanction until the King or a councillor chooses one in Olympus's chats."
if GetLocale and GetLocale() == "ptBR" then
	L.WATCH_CASES_TITLE_COUNCIL = "Casos do High Council"
	L.WATCH_COUNCIL_TIP = "Denúncias de membros de todas as guildas do Olympus, recebidas e repassadas por um coletor confiável do conselho (o cliente do King ou o autor fixado do addon): só de quem ele já conhece na guilda que diz, e só com as linhas que esse coletor ouviu no canal do Olympus. O King e o High Council agem nelas nos chats do Olympus, nunca com a Watch de uma guilda. Uma denúncia sozinha não prova nada."
	L.WATCH_REPORT_LINES_COUNCIL = "%d das %d linhas que ela indicou, cada uma ouvida pelo próprio coletor que a recebeu no canal do Olympus (as outras ficaram de fora)."
	L.WATCH_COUNCIL_DETAIL = "As denúncias e os casos do High Council: de membros de todas as guildas do Olympus, por um coletor confiável do conselho. Nada aqui é uma sanção até o King ou um conselheiro escolher uma nos chats do Olympus."
end
