local _, ns = ...
local L = ns.L
L.FEDERATION_KEY_TITLE = "Federation public key"
L.FEDERATION_KEY_UNAVAILABLE = "Your game identity is not ready. Try again after your guild roster loads."
L.FEDERATION_KEY_HELP = "/oly federation key: copy your public signing-key request. /oly federation certificate: import a reviewed certificate or revocation. /oly federation sync: recover signed decisions. Private keys never leave this client."
L.FEDERATION_CERTIFICATE_ACCEPTED = "Federation key certificate accepted. Guild approval is unchanged."
L.FEDERATION_CERTIFICATE_REFUSED = "Certificate refused: check its signature, scope, current role and expiry."
L.FEDERATION_SYNC_STARTED = "Requesting signed federation decisions."
L.FEDERATION_SYNC_WAIT = "No eligible peer is available yet."
L.FEDERATION_CERTIFICATE_PROMPT = "Paste the signed federation key certificate or revocation. Guild approval is unchanged."
L.FEDERATION_AUTHORITY_WAIT = "Automatic federation decisions need a current reviewed signing certificate. Existing guild approvals are unchanged."
if GetLocale and GetLocale() == "ptBR" then
	L.FEDERATION_KEY_TITLE = "Chave pública da federação"
	L.FEDERATION_KEY_UNAVAILABLE = "Sua identidade no jogo ainda não está pronta. Tente após carregar a lista da guilda."
	L.FEDERATION_KEY_HELP = "/oly federation key: copiar pedido de chave pública. /oly federation certificate: importar certificado revisado ou revogação. /oly federation sync: recuperar decisões assinadas. A chave privada nunca sai deste cliente."
	L.FEDERATION_CERTIFICATE_ACCEPTED = "Certificado de chave aceito. A aprovação da guilda não mudou."
	L.FEDERATION_CERTIFICATE_REFUSED = "Certificado recusado: confira assinatura, escopo, cargo atual e validade."
	L.FEDERATION_SYNC_STARTED = "Solicitando decisões assinadas da federação."
	L.FEDERATION_SYNC_WAIT = "Nenhum participante elegível disponível ainda."
	L.FEDERATION_CERTIFICATE_PROMPT = "Cole o certificado de chave ou a revogação assinada. A aprovação da guilda não muda."
	L.FEDERATION_AUTHORITY_WAIT = "Decisões automáticas da federação precisam de um certificado de assinatura atual e revisado. As aprovações existentes das guildas não mudam."
end
