local _, ns = ...
local L = ns.L
L.RECRUIT_HANDOFF_OFF = "Accept recruitment handoffs: Off"
L.RECRUIT_HANDOFF_ON = "Accept recruitment handoffs: On"
L.RECRUIT_HANDOFF_PICK = "Offer to another officer"
L.RECRUIT_HANDOFF_EMPTY = "No eligible officers were found."
L.RECRUIT_HANDOFF_OFFER = "Offer to %s <%s>"
L.RECRUIT_HANDOFF_CLAIM = "Claim request from %s <%s>"
L.RECRUIT_HANDOFF_WAITING = "Waiting for request from %s <%s>"
L.RECRUIT_HANDOFF_PENDING = "Waiting for confirmation from %s <%s>"
L.RECRUIT_HANDOFF_DONE = "Handed off to %s <%s>"
L.RECRUIT_HANDOFF_RECEIVED = "Recruitment request handed off by %s."

if GetLocale and GetLocale() == "ptBR" then
	L.RECRUIT_HANDOFF_OFF = "Aceitar repasses de recrutamento: desligado"
	L.RECRUIT_HANDOFF_ON = "Aceitar repasses de recrutamento: ligado"
	L.RECRUIT_HANDOFF_PICK = "Oferecer a outro oficial"
	L.RECRUIT_HANDOFF_EMPTY = "Nenhum oficial disponível na lista."
	L.RECRUIT_HANDOFF_OFFER = "Oferecer a %s <%s>"
	L.RECRUIT_HANDOFF_CLAIM = "Assumir pedido de %s <%s>"
	L.RECRUIT_HANDOFF_WAITING = "Aguardando o pedido de %s <%s>"
	L.RECRUIT_HANDOFF_PENDING = "Aguardando confirmação de %s <%s>"
	L.RECRUIT_HANDOFF_DONE = "Repassado a %s <%s>"
	L.RECRUIT_HANDOFF_RECEIVED = "Pedido de recrutamento repassado por %s."
end
