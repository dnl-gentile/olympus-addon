local _, ns = ...
local text = {
	enUS = {
		CHAT_ACCESS_IDENTITY = "Waiting for your realm identity. If this continues, restart WoW and send /oly bug.",
		CHAT_ACCESS_ROSTER = "Waiting for a complete, current guild roster. Chat opens automatically when the local leadership check is ready. Your guild does not need to be verified again.",
		CHAT_ACCESS_PENDING = "No current guild approval is available here. If your guild was already approved, ask a verifier to resend that approval.",
		CHAT_ACCESS_REVOKED = "Your guild's approval was revoked. Ask the High Council to review its status.",
		CHAT_ACCESS_LEADERSHIP = "The current guild leadership does not match this client's participation record. Ask the High Council to review the leadership record.",
		CHAT_ACCESS_POLICY = "The current participation policy does not allow this guild to use shared chat.",
		CHAT_ACCESS_SUSPENDED = "Shared tools are suspended for this guild. Ask the High Council to review its status.",
	},
	ptBR = {
		CHAT_ACCESS_IDENTITY = "Aguardando a identificação do seu reino. Se continuar assim, reinicie o WoW e envie /oly bug.",
		CHAT_ACCESS_ROSTER = "Aguardando uma lista completa e atual dos membros da guilda. O chat abre automaticamente quando a confirmação local da liderança estiver pronta. Não é preciso verificar sua guilda novamente.",
		CHAT_ACCESS_PENDING = "Nenhuma aprovação atual da guilda está disponível aqui. Se ela já foi aprovada, peça a um verificador para reenviar essa aprovação.",
		CHAT_ACCESS_REVOKED = "A aprovação da sua guilda foi revogada. Peça ao High Council para revisar a situação.",
		CHAT_ACCESS_LEADERSHIP = "A liderança atual da guilda não corresponde ao registro de participação neste cliente. Peça ao High Council para revisar o registro da liderança.",
		CHAT_ACCESS_POLICY = "A política atual de participação não permite que esta guilda use o chat compartilhado.",
		CHAT_ACCESS_SUSPENDED = "As ferramentas compartilhadas estão suspensas para esta guilda. Peça ao High Council para revisar a situação.",
	},
	deDE = {
		CHAT_ACCESS_IDENTITY = "Die Identität deines Realms wird ermittelt. Falls dies anhält, starte WoW neu und sende /oly bug.",
		CHAT_ACCESS_ROSTER = "Eine vollständige, aktuelle Gildenliste wird erwartet. Der Chat öffnet sich automatisch, sobald die lokale Prüfung der Gildenleitung abgeschlossen ist. Deine Gilde muss nicht erneut verifiziert werden.",
		CHAT_ACCESS_PENDING = "Hier liegt keine aktuelle Gildenbestätigung vor. Wurde deine Gilde bereits bestätigt, bitte einen Prüfer, diese Bestätigung erneut zu senden.",
		CHAT_ACCESS_REVOKED = "Die Bestätigung deiner Gilde wurde widerrufen. Bitte den Hohen Rat, ihren Status zu prüfen.",
		CHAT_ACCESS_LEADERSHIP = "Die aktuelle Gildenleitung stimmt nicht mit dem Teilnahmevermerk dieses Clients überein. Bitte den Hohen Rat, den Leitungseintrag zu prüfen.",
		CHAT_ACCESS_POLICY = "Die aktuelle Teilnahmeregel erlaubt dieser Gilde den gemeinsamen Chat nicht.",
		CHAT_ACCESS_SUSPENDED = "Die gemeinsamen Werkzeuge sind für diese Gilde ausgesetzt. Bitte den Hohen Rat, ihren Status zu prüfen.",
	},
	esES = {
		CHAT_ACCESS_IDENTITY = "Esperando la identificación de tu reino. Si continúa así, reinicia WoW y envía /oly bug.",
		CHAT_ACCESS_ROSTER = "Esperando una lista completa y actual de la hermandad. El chat se abre automáticamente cuando termine la comprobación local del liderazgo. No es necesario verificar tu hermandad otra vez.",
		CHAT_ACCESS_PENDING = "Aquí no hay una aprobación actual de la hermandad. Si ya fue aprobada, pide a un verificador que reenvíe esa aprobación.",
		CHAT_ACCESS_REVOKED = "La aprobación de tu hermandad fue revocada. Pide al Alto Consejo que revise su estado.",
		CHAT_ACCESS_LEADERSHIP = "El liderazgo actual de la hermandad no coincide con el registro de participación de este cliente. Pide al Alto Consejo que revise el registro del liderazgo.",
		CHAT_ACCESS_POLICY = "La política actual de participación no permite que esta hermandad use el chat compartido.",
		CHAT_ACCESS_SUSPENDED = "Las herramientas compartidas están suspendidas para esta hermandad. Pide al Alto Consejo que revise su estado.",
	},
	frFR = {
		CHAT_ACCESS_IDENTITY = "En attente de l'identification de ton royaume. Si cela continue, redémarre WoW et envoie /oly bug.",
		CHAT_ACCESS_ROSTER = "En attente d'une liste de guilde complète et actuelle. Le chat s'ouvre automatiquement dès que la vérification locale de la direction est prête. Ta guilde n'a pas besoin d'être vérifiée de nouveau.",
		CHAT_ACCESS_PENDING = "Aucune approbation actuelle de ta guilde n'est disponible ici. Si elle a déjà été approuvée, demande à un vérificateur de renvoyer cette approbation.",
		CHAT_ACCESS_REVOKED = "L'approbation de ta guilde a été révoquée. Demande au Haut Conseil de revoir son statut.",
		CHAT_ACCESS_LEADERSHIP = "La direction actuelle de la guilde ne correspond pas au registre de participation de ce client. Demande au Haut Conseil de revoir le registre de direction.",
		CHAT_ACCESS_POLICY = "La politique de participation actuelle n'autorise pas cette guilde à utiliser le chat partagé.",
		CHAT_ACCESS_SUSPENDED = "Les outils partagés sont suspendus pour cette guilde. Demande au Haut Conseil de revoir son statut.",
	},
	itIT = {
		CHAT_ACCESS_IDENTITY = "In attesa dell'identificazione del tuo reame. Se continua, riavvia WoW e invia /oly bug.",
		CHAT_ACCESS_ROSTER = "In attesa di un elenco di gilda completo e aggiornato. La chat si apre automaticamente quando il controllo locale dei capi è pronto. Non occorre verificare di nuovo la tua gilda.",
		CHAT_ACCESS_PENDING = "Qui non è disponibile un'approvazione attuale della gilda. Se è già stata approvata, chiedi a un verificatore di reinviare quell'approvazione.",
		CHAT_ACCESS_REVOKED = "L'approvazione della tua gilda è stata revocata. Chiedi all'Alto Consiglio di verificarne lo stato.",
		CHAT_ACCESS_LEADERSHIP = "I capi attuali della gilda non corrispondono al registro di partecipazione di questo client. Chiedi all'Alto Consiglio di controllare il registro dei capi.",
		CHAT_ACCESS_POLICY = "Le regole attuali di partecipazione non consentono a questa gilda di usare la chat condivisa.",
		CHAT_ACCESS_SUSPENDED = "Gli strumenti condivisi sono sospesi per questa gilda. Chiedi all'Alto Consiglio di verificarne lo stato.",
	},
	ruRU = {
		CHAT_ACCESS_IDENTITY = "Ожидание определения игрового мира. Если ожидание продолжается, перезапусти WoW и отправь /oly bug.",
		CHAT_ACCESS_ROSTER = "Ожидание полного актуального состава гильдии. Чат откроется автоматически после локальной проверки руководства. Повторно проверять гильдию не нужно.",
		CHAT_ACCESS_PENDING = "Здесь нет актуального одобрения гильдии. Если она уже была одобрена, попроси проверяющего повторно отправить это одобрение.",
		CHAT_ACCESS_REVOKED = "Одобрение твоей гильдии отозвано. Попроси Высший совет пересмотреть её статус.",
		CHAT_ACCESS_LEADERSHIP = "Нынешнее руководство гильдии не совпадает с записью об участии на этом клиенте. Попроси Высший совет проверить запись о руководстве.",
		CHAT_ACCESS_POLICY = "Текущие правила участия не разрешают этой гильдии использовать общий чат.",
		CHAT_ACCESS_SUSPENDED = "Общие инструменты для этой гильдии приостановлены. Попроси Высший совет пересмотреть её статус.",
	},
}
for key, value in pairs(text.enUS) do ns.L[key] = value end
local code = GetLocale and GetLocale()
local translated = text[code == "esMX" and "esES" or code]
for key, value in pairs(translated or {}) do ns.L[key] = value end
