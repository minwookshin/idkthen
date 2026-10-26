import Foundation

/// Small, authored coverage supplement for common words omitted by macOS guesses.
/// These are spelling candidates, never evidence of the writer's intended meaning.
enum AccentHints {
    static let words: [LanguagePair: String] = [
        .spanish: "mañana reunión después también español información comunicación conversación canción café menú número teléfono dirección atención página rápido fácil difícil útil último próximo aquí allí así todavía además quizás sí tú él mí té más qué quién cómo dónde cuándo cuánto papá mamá año años acción situación opinión revisión presentación gracias última música ojalá",
        .french: "réunion déjà arrivé arrivés arrivée arrivées près prés résumé résume café thé à où prêt très français française bientôt après être même équipe réponse côté plutôt voilà merci intéressé qualité création présentation réunion numéro téléphone éducation nécessaire dernière fenêtre problème système accès pièce grâce garçon façon ça reçu désolé désolée",
        .german: "für schön über würde könnte müsste möchte später möglich nötig natürlich persönlich nächste grün Grüße Straße größer weiß heißen heißen süß früh zurück Büro Schlüssel Prüfung Universität ähnlich jährlich öffentlich täglich überhaupt verfügbar Änderung plötzlich gültig früher",
        .portuguese: "amanhã reunião português também informação comunicação coração não são ação ações opção opções opinião opiniões café você vocês está estão é à às já até após só três mês fácil difícil possível próximo último rápido música número página atenção questão questões situação criação revisão apresentação obrigado avó avô pôr pôde nós têm ótimo ótima última",
        .italian: "perché città caffè così più già giù però lunedì martedì mercoledì giovedì venerdì università qualità possibilità necessità velocità difficoltà libertà verità felicità sarà cioè finché poiché benché né sé sì è lì là dà"
    ]
    private static let indexed = words.mapValues { passage in
        Dictionary(grouping: passage.split(separator: " ").map(String.init), by: ReviewEngine.folded)
    }
    static func candidates(for original: String, pair: LanguagePair) -> [String] {
        indexed[pair]?[ReviewEngine.folded(original)] ?? []
    }
}
