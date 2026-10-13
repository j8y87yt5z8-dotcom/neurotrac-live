import Foundation

/// Language of the interface and reports. French is the source language of the texts in the code;
/// English is provided by the `Translations.en` dictionary (key = French text).
public enum Lang: String {
    case fr, en

    /// Forced by tests or by the user's setting; otherwise the system language.
    public static var override: Lang?

    /// Stored setting: “auto”, “fr” or “en”.
    public static let defaultsKey = "ntl.lang"

    public static var current: Lang {
        if let o = override { return o }
        if let s = UserDefaults.standard.string(forKey: defaultsKey), let l = Lang(rawValue: s) { return l }
        let first = Locale.preferredLanguages.first ?? "fr"
        return first.lowercased().hasPrefix("fr") ? .fr : .en
    }

    /// Translates a complete French text (displayed value coming from data: muscle, side, label…).
    /// An unknown text is returned unchanged.
    public static func translate(_ fr: String) -> String {
        if current == .fr { return fr }
        return Translations.en[fr] ?? fr
    }

    /// Fills the “{}” slots (in order) or “{0}”, “{1}”… of a template.
    static func fill(_ template: String, _ args: [String]) -> String {
        if args.isEmpty { return template }
        var out = ""
        var next = 0
        let chars = Array(template)
        var i = 0
        while i < chars.count {
            if chars[i] == "{" {
                if i + 1 < chars.count, chars[i + 1] == "}" {
                    if next < args.count { out += args[next] }
                    next += 1
                    i += 2
                    continue
                }
                var j = i + 1
                var digits = ""
                while j < chars.count, chars[j].isNumber { digits.append(chars[j]); j += 1 }
                if !digits.isEmpty, j < chars.count, chars[j] == "}", let n = Int(digits), n < args.count {
                    out += args[n]
                    i = j + 1
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }
}

/// French text with its values: “Séance : \(muscle)” becomes the template “Séance : {}” + [muscle].
/// The template is the translation key; text values are translated in turn when known.
public struct L: ExpressibleByStringInterpolation {
    public var template: String
    public var args: [String]

    public init(stringLiteral value: String) {
        template = value
        args = []
    }

    public init(stringInterpolation: Interpolation) {
        template = stringInterpolation.template
        args = stringInterpolation.args
    }

    public struct Interpolation: StringInterpolationProtocol {
        var template = ""
        var args: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {}

        public mutating func appendLiteral(_ literal: String) { template += literal }

        public mutating func appendInterpolation(_ value: String) {
            template += "{}"
            args.append(Lang.translate(value))
        }

        public mutating func appendInterpolation<T>(_ value: T) {
            template += "{}"
            args.append("\(value)")
        }
    }
}

/// Translates a text written in French in the code (with or without inserted values).
public func tr(_ text: L) -> String {
    let t = Lang.current == .fr ? text.template : (Translations.en[text.template] ?? text.template)
    return Lang.fill(t, text.args)
}

/// Translates a text only known at run time (catalog value, label, format template…).
public func trd(_ text: String) -> String {
    return Lang.translate(text)
}
