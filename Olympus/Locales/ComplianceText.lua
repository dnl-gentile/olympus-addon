local ADDON, ns = ...
local L = ns.L

-- The compliance gate (Compliance.lua): games ship without wagers or gold stakes. The dormant
-- implementation is retained locally, not a promise of a future release. English, then pt-BR
-- (the pattern of Locales.lua); Spanish, French and German fall back to English. Each package's
-- refusal words (Kit.Why's prefixes, Bones's, the Lottery's, the matchmaking's, the roles')
-- get the same line for the code "compliance", set at the end from these.

L.COMPLIANCE_WAIT = "These games have no bets or gold stakes. Play for points, not gold."
L.COMPLIANCE_WAIT_SHORT = "No bets or gold stakes."
L.COMPLIANCE_LOTTERY_PRACTICE = "Free practice: tickets cost nothing and no gold moves."

if GetLocale and GetLocale() == "ptBR" then
	L.COMPLIANCE_WAIT = "Estes jogos não têm apostas nem ouro em disputa. Jogue por pontos, não por ouro."
	L.COMPLIANCE_WAIT_SHORT = "Sem apostas nem ouro em disputa."
	L.COMPLIANCE_LOTTERY_PRACTICE = "Treino gratuito: os bilhetes não custam nada e nenhum ouro se move."
end

-- (The refusal "compliance" in each package's words.)
for _, key in ipairs({ "ARENA_REFUSE_COMPLIANCE", "ARENA_WHY_COMPLIANCE", "WALLET_WHY_COMPLIANCE", "MARKETS_WHY_COMPLIANCE",
	"FIGHTS_WHY_COMPLIANCE", "FARKLE_WHY_COMPLIANCE", "MATCH_WHY_COMPLIANCE", "LOTTERY_WHY_COMPLIANCE" }) do
	L[key] = L.COMPLIANCE_WAIT
end
-- (Bones's create panel has one short row for its reason.)
L.FARKLE_B_WHY_COMPLIANCE = L.COMPLIANCE_WAIT_SHORT
