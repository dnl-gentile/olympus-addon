local _, ns = ...
local L = ns.L
L.CONTRIBUTIONS_TITLE = "Charitable Contributions"
L.CONTRIBUTIONS_DETAIL = "Voluntary contributions support guild events, crafting and operations. There is no weekly payment or penalty."
L.CONTRIBUTIONS_HOW = "Ask your guild leadership about its current needs and how to contribute."
L.DUESGRACE_HINT = "Private recorded-week history of your own guild (last four closed weeks). One covered week below the amount preserves the recorded run; the second ends that local run and prompts a private notice to the player, then the current Guild Master. Unknown coverage pauses it. Not recorded does not mean unpaid; this never blocks features or removes members."
L.DUESGRACE_ROW = "Recorded run: %d · covered: %d · unknown: %d"
L.DUESGRACE_TOLERANCE = "one-week tolerance"
L.DUESGRACE_SELF = "%s: another covered week is below the recorded amount (week %s, %s / %s). This means not confirmed in the Treasurer's books, not proof that you did not send it. Please check with the Treasurer if already sent. No feature is blocked."
L.DUESGRACE_OFFICER = "Private Treasurer notice: %s has two or more covered weeks below the recorded amount (week %s, %s / %s). Not confirmed in the books is not proof of nonpayment. Check privately; no action is automatic."
L.DUESGRACE_MORE = "Show more recorded weeks (%d)"
if GetLocale and GetLocale() == "ptBR" then
	L.CONTRIBUTIONS_TITLE = "Contribuições voluntárias"
	L.CONTRIBUTIONS_DETAIL = "As contribuições voluntárias apoiam eventos, produção e atividades da guilda. Não há cobrança semanal nem penalidade."
	L.CONTRIBUTIONS_HOW = "Pergunte à liderança da sua guilda do que ela precisa e como contribuir."
	L.DUESGRACE_HINT = "Histórico privado de semanas registradas da sua própria guilda (últimas quatro encerradas). Uma semana com cobertura abaixo do valor preserva a sequência registrada; a segunda encerra essa sequência local e gera um aviso privado ao jogador, depois ao Guild Master atual. Cobertura desconhecida pausa. Não registrado não significa não pago; isto nunca bloqueia funcionalidades ou expulsa membros."
	L.DUESGRACE_ROW = "Sequência registrada: %d · cobertas: %d · desconhecidas: %d"
	L.DUESGRACE_TOLERANCE = "tolerância de uma semana"
	L.DUESGRACE_SELF = "%s: outra semana com cobertura ficou abaixo do valor registrado (semana %s, %s / %s). Significa não confirmado nos livros do Tesoureiro, não prova que você não enviou. Se já enviou, confira com o Tesoureiro. Nenhuma funcionalidade foi bloqueada."
	L.DUESGRACE_OFFICER = "Aviso privado do Tesoureiro: %s tem duas ou mais semanas com cobertura abaixo do valor registrado (semana %s, %s / %s). Não confirmado nos livros não prova falta de pagamento. Confirme em particular; nenhuma ação é automática."
	L.DUESGRACE_MORE = "Mostrar mais semanas registradas (%d)"
end
