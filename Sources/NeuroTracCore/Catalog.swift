import Foundation

/// Reference lists: muscles, sides, threshold types, observation sheet items.
public enum Catalog {
    public struct Item: Hashable {
        public let key: String
        public let label: String
        public init(_ key: String, _ label: String) {
            self.key = key
            self.label = label
        }
    }

    public static let muscles: [String] = [
        "Quadriceps", "Ischio-jambiers", "Fessiers", "Tibial antérieur", "Péroniers",
        "Mollet", "Pied", "Abdominaux", "Lombaires / dos", "Sphincter anal (sonde)", "Autre",
    ]

    /// “Side” text for a central area (anal probe): neither right nor left.
    public static let noSide = "Sans côté"

    public static let sides: [String] = ["Droite", "Gauche", "Les deux", noSide]

    /// Muscles on the midline: a single side, “No side”.
    public static let midlineMuscles: [String] = ["Sphincter anal (sonde)"]

    /// Sides to compare in the curves for a given muscle.
    public static func sidesFor(muscle: String) -> [String] {
        return midlineMuscles.contains(muscle) ? [noSide] : ["Droite", "Gauche"]
    }

    public static let thresholdKinds: [String] = [
        "Vibration / picotement", "Contraction palpable", "Premier mouvement",
        "Mouvement net", "Résiste à la main", "Autre",
    ]

    /// Scale used in the observation sheet (inspired by the MRC scale, simplified).
    public static let scaleLabels: [Int: String] = [
        0: "0 — rien",
        1: "1 — contraction ou vibration palpable",
        2: "2 — mouvement partiel, sans la gravité",
        3: "3 — mouvement contre la gravité",
        4: "4 — contre une légère résistance",
        5: "5 — contre une bonne résistance",
    ]

    /// Items scored on the right and on the left (key + “_D” or “_G”).
    public static let sidedScales: [Item] = [
        Item("genou_ext", "Extension volontaire du genou"),
        Item("pied_dorsal", "Relevé du pied (flexion dorsale)"),
        Item("orteils", "Mouvement des orteils"),
        Item("hanche_flex", "Lever de la jambe / genou"),
        Item("fessiers", "Contraction des fessiers"),
    ]

    public static let flags: [Item] = [
        Item("chair_poule", "Chair de poule"),
        Item("vibration_contact", "Pied qui vibre dès le contact de l'électrode"),
        Item("sensation_dite", "Dit sentir l'électrode ou la stimulation"),
        Item("pied_sans_regarder", "Bouge le pied sur consigne sans regarder"),
        Item("pas_reel", "Vrai pas avec le déambulateur"),
        Item("genou_reflexe", "Extension réflexe du genou debout"),
    ]

    public static let numbers: [Item] = [
        Item("debout_min", "Debout avec les AFO (minutes)"),
        Item("pas_nombre", "Pas faits avec le déambulateur (nombre)"),
    ]

    public static func sidedKey(_ key: String, side: String) -> String {
        return key + (side == "Gauche" ? "_G" : "_D")
    }

    public static func label(forScaleKey key: String) -> String {
        var base = key
        var suffix = ""
        if key.hasSuffix("_D") { base = String(key.dropLast(2)); suffix = tr(" (droite)") }
        if key.hasSuffix("_G") { base = String(key.dropLast(2)); suffix = tr(" (gauche)") }
        let name = trd(sidedScales.first { $0.key == base }?.label ?? base)
        return name + suffix
    }
}
