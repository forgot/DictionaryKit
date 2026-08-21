import Foundation

/// A type-safe enum for referencing dictionaries with convenient short names.
///
/// Use `DictionaryAlias` in your Swift code to get compile-time validation and IDE autocomplete.
///
/// Example:
/// ```swift
/// let entries = try await service.entries(matching: "apple", in: .oxford)
/// ```
public enum DictionaryAlias: String, CaseIterable, Sendable {
    // English dictionaries
    case apple
    case oxford
    case oxfordUK = "oxford-uk"
    case oxfordUS = "oxford-us"
    case american
    case thesaurus
    case thesaurusUK = "thesaurus-uk"
    case thesaurusUS = "thesaurus-us"

    // European languages
    case french
    case german
    case spanish
    case italian
    case portuguese
    case russian
    case dutch
    case polish
    case turkish
    case czech
    case danish
    case swedish
    case norwegian
    case finnish
    case greek
    case hebrew
    case arabic
    case hungarian
    case croatian
    case romanian
    case bulgarian
    case ukrainian
    case kazakh
    case catalan
    case slovak

    // Asian languages
    case japanese
    case korean
    case chinese
    case chineseSimplified = "chinese-simplified"
    case chineseTraditional = "chinese-traditional"
    case thai
    case vietnamese

    // Indian languages
    case hindi
    case bengali
    case tamil
    case telugu
    case marathi
    case gujarati
    case kannada
    case malayalam
    case punjabi
    case urdu
    case sanskrit
    case assamese
    case odia
    case nepali

    // Other languages
    case indonesian
    case malay

    // Reference
    case wikipedia

    /// The full dictionary name corresponding to this alias
    public var dictionaryName: String {
        switch self {
        // English dictionaries
        case .apple: return DCSAppleDictionaryName
        case .oxford, .oxfordUK: return DCSOxfordDictionaryOfEnglish
        case .oxfordUS, .american: return DCSNewOxfordAmericanDictionaryName
        case .thesaurus, .thesaurusUK: return DCSOxfordThesaurusOfEnglish
        case .thesaurusUS: return DCSOxfordAmericanWritersThesaurus

        // European languages
        case .french: return DCSFrenchDictionaryName
        case .german: return DCSGermanDictionaryName
        case .spanish: return DCSSpanishDictionaryName
        case .italian: return DCSItalianDictionaryName
        case .portuguese: return DCSPortugueseDictionaryName
        case .russian: return DCSRussianDictionaryName
        case .dutch: return DCSDutchDictionaryName
        case .polish: return DCSPolishDictionaryName
        case .turkish: return DCSTurkishDictionaryName
        case .czech: return DCSCzechDictionaryName
        case .danish: return DCSDanishDictionaryName
        case .swedish: return DCSSwedishDictionaryName
        case .norwegian: return DCSNorwegianDictionaryName
        case .finnish: return DCSFinnishDictionaryName
        case .greek: return DCSGreekDictionaryName
        case .hebrew: return DCSHebrewDictionaryName
        case .arabic: return DCSArabicDictionaryName
        case .hungarian: return DCSHungarianDictionaryName
        case .croatian: return DCSCroatianDictionaryName
        case .romanian: return DCSRomanianDictionaryName
        case .bulgarian: return DCSBulgarianDictionaryName
        case .ukrainian: return DCSUkrainianDictionaryName
        case .kazakh: return DCSKazakhDictionaryName
        case .catalan: return DCSCatalanDictionaryName
        case .slovak: return DCSSlovakDictionaryName

        // Asian languages
        case .japanese: return DCSJapanese_EnglishDictionaryName
        case .korean: return DCSKorean_EnglishDictionaryName
        case .chinese, .chineseSimplified: return DCSSimplifiedChinese_EnglishDictionaryName
        case .chineseTraditional: return DCSTraditionalChinese_EnglishDictionaryName
        case .thai: return DCSThai_EnglishDictionaryName
        case .vietnamese: return DCSVietnamese_EnglishDictionaryName

        // Indian languages
        case .hindi: return DCSHindiDictionaryName
        case .bengali: return DCSBengaliDictionaryName
        case .tamil: return DCSTamilDictionaryName
        case .telugu: return DCSTeluguDictionaryName
        case .marathi: return DCSMarathiDictionaryName
        case .gujarati: return DCSGujaratiDictionaryName
        case .kannada: return DCSKannadaDictionaryName
        case .malayalam: return DCSMalayalamDictionaryName
        case .punjabi: return DCSPunjabiDictionaryName
        case .urdu: return DCSUrduDictionaryName
        case .sanskrit: return DCSSanskritDictionaryName
        case .assamese: return DCSAssameseDictionaryName
        case .odia: return DCSOdiaDictionaryName
        case .nepali: return DCSNepaliDictionaryName

        // Other languages
        case .indonesian: return DCSIndonesianDictionaryName
        case .malay: return DCSMalayDictionaryName

        // Reference
        case .wikipedia: return DCSWikipediaName
        }
    }

    /// Creates an alias from free-form user input, such as a CLI argument or an MCP tool parameter.
    ///
    /// Matching is case-insensitive and tolerant of surrounding whitespace, so `oxford`,
    /// `Oxford`, and `  OXFORD ` all resolve to ``oxford``. Returns `nil` if the input
    /// isn't an alias — callers should then treat it as a full dictionary name.
    ///
    /// ```swift
    /// let name = DictionaryAlias(userInput: input)?.dictionaryName ?? input
    /// ```
    public init?(userInput: String) {
        let normalized = userInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let alias = DictionaryAlias(rawValue: normalized) else { return nil }
        self = alias
    }

    /// Every alias that maps to the given dictionary name, in declaration order.
    ///
    /// Several dictionaries have more than one alias — `oxford` and `oxford-uk` both refer
    /// to the Oxford Dictionary of English — so callers that display aliases should use this
    /// rather than searching ``allCases`` for the first match.
    public static func aliases(for dictionaryName: String) -> [DictionaryAlias] {
        allCases.filter { $0.dictionaryName == dictionaryName }
    }
}
