// Dictionary names as reported by DictionaryServices.
//
// These must match the system's names byte for byte — `DCSCopyAvailableDictionaries`
// is looked up by exact string. Typographic apostrophes (U+2019), trailing spaces,
// and non-Latin scripts are all significant. `DictionaryAliasTests` asserts that
// every constant either matches an installed dictionary exactly or matches nothing
// at all, which catches the near-miss transcriptions that used to live here.

// English Dictionaries
public let DCSAppleDictionaryName = "Apple Dictionary"
public let DCSNewOxfordAmericanDictionaryName = "New Oxford American Dictionary"
public let DCSOxfordAmericanWritersThesaurus =
    "Oxford American Writer\u{2019}s Thesaurus"
public let DCSOxfordDictionaryOfEnglish = "Oxford Dictionary of English"
public let DCSOxfordThesaurusOfEnglish = "Oxford Thesaurus of English"

// European Languages
public let DCSFrenchDictionaryName = "Oxford-Hachette French Dictionary"
public let DCSGermanDictionaryName = "Oxford German Dictionary"
public let DCSSpanishDictionaryName = "Gran Diccionario Oxford - Español-Inglés • Inglés-Español"
public let DCSItalianDictionaryName =
    "Oxford Paravia Il Dizionario inglese - italiano/italiano - inglese"
public let DCSPortugueseDictionaryName =
    "Oxford Portuguese Dictionary - Português-Inglês • Inglês-Português"
public let DCSRussianDictionaryName =
    "Oxford Russian Dictionary - Русско-Английский • Англо-Русский"
public let DCSDutchDictionaryName = "Prisma Handwoordenboek Engels"
public let DCSPolishDictionaryName =
    "Oxford PWN Polish-English Dictionary / Wielki słownik polsko-angielski"
public let DCSTurkishDictionaryName =
    "Oxford Turkish Dictionary - Türkçe-İngilizce • İngilizce-Türkçe"
public let DCSCzechDictionaryName = "Velký anglicko-český a česko-anglický slovník"
public let DCSDanishDictionaryName = "Praktisk Engelsk-Dansk Ordbog"
public let DCSSwedishDictionaryName =
    "NE Nationalencyklopedin AB Professional English-Swedish / Svensk-Engelska"
public let DCSNorwegianDictionaryName = "Norsk Ordbok"
public let DCSFinnishDictionaryName = "MOT sanakirja suomi-englanti, englanti-suomi"
public let DCSGreekDictionaryName = "Stavropoulos Oxford Greek-English Learners Dictionary"
// Note the trailing space: it is part of the name DictionaryServices reports.
public let DCSHebrewDictionaryName = "Oxford Hebrew Dictionary | מילון עברי-אנגלי דו-לשוני\u{20}"
public let DCSArabicDictionaryName = "Oxford Arabic Dictionary - عربي-إنجليزي • إنجليزي-عربي"
public let DCSHungarianDictionaryName = "Magay Tamás szótár - Magyar-Angol • Angol-Magyar"
public let DCSCroatianDictionaryName = "Hrvatski Enciklopedijski Rječnik"
public let DCSRomanianDictionaryName = "Dicţionarul explicativ al limbii române"
public let DCSBulgarianDictionaryName = "Тълковен речник на съвременния български език"
public let DCSUkrainianDictionaryName = "Українсько-Англійський Словник"
public let DCSKazakhDictionaryName = "Оксфорд Қазақ Cөздігі"
public let DCSCatalanDictionaryName = "Diccionari Català-Anglès"
public let DCSSlovakDictionaryName = "Veľký Anglicko-Slovenský Slovník"

// Asian Languages
public let DCSJapaneseSupaDaijirinDictionaryName = "スーパー大辞林"
public let DCSJapaneseDictionaryName = DCSJapaneseSupaDaijirinDictionaryName
public let DCSJapanese_EnglishDictionaryName = "ウィズダム英和辞典 / ウィズダム和英辞典"
public let DCSJapaneseChujiDictionaryName = "超級クラウン中日辞典 / クラウン日中辞典"
public let DCSKoreanDictionaryName = "뉴에이스 국어사전"
public let DCSKorean_EnglishDictionaryName = "뉴에이스 영한사전 / 뉴에이스 한영사전"
public let DCSSimplifiedChineseDictionaryName = "现代汉语规范词典"
public let DCSSimplifiedChinese_EnglishDictionaryName = "牛津英汉汉英词典"
public let DCSTraditionalChinese_EnglishDictionaryName = "譯典通英漢雙向字典"
public let DCSTraditionalChineseActivityDictionaryName = "五南國語活用辭典"
public let DCSCantoneseEnglishDictionaryName = "牛津粵英雙語詞典"
public let DCSThai_EnglishDictionaryName = "พจนานุกรมอังกฤษ-ไทย & ไทย-อังกฤษ ฉบับทันสมัยและสมบูรณ์ที่สุด"
public let DCSVietnamese_EnglishDictionaryName = "Từ điển Lạc Việt"

// Indian Languages
public let DCSHindiDictionaryName = "Oxford Hindi Dictionaries - हिन्दी-अंग्रेज़ी • अंग्रेज़ी-हिन्दी"
public let DCSBengaliDictionaryName = "Oxford Bengali Dictionaries - বাংলা-ইংরেজি • ইংরেজি-বাংলা"
public let DCSTamilDictionaryName = "Oxford Tamil Dictionaries - தமிழ்-ஆங்கிலம் • ஆங்கிலம்-தமிழ்"
public let DCSTeluguDictionaryName = "Oxford Telugu Dictionaries - తెలుగు-ఇంగ్లీష్ • ఇంగ్లీష్-తెలుగు"
public let DCSMarathiDictionaryName = "Oxford Marathi Dictionaries - इंग्रजी-मराठी • मराठी-इंग्रजी"
public let DCSGujaratiDictionaryName = "Oxford Gujarati Dictionaries - ગુજરાતી-અંગ્રેજી • અંગ્રેજી-ગુજરાતી"
public let DCSKannadaDictionaryName = "Oxford Kannada Dictionaries - ಇಂಗ್ಲಿಷ್-ಕನ್ನಡ • ಕನ್ನಡ-ಇಂಗ್ಲಿಷ್"
public let DCSMalayalamDictionaryName = "Oxford Malayalam Dictionaries - മലയാളം-ഇംഗ്ലീഷ് • ഇംഗ്ലീഷ്-മലയാളം"
public let DCSPunjabiDictionaryName =
    "Oxford Punjabi Dictionaries - ਪੰਜਾਬੀ ਅੰਗਰੇਜ਼ੀ ਕੋਸ਼ • پنجابی انگریزی لغت"
public let DCSUrduDictionaryName = "Oxford Urdu Dictionaries - اردو۔انگریزی • انگریزی-اردو"
public let DCSSanskritDictionaryName = "Oxford Sanskrit Dictionaries - आङ्ग्ल-संस्कृतम् • संस्कृतम्-आङ्ग्ल"
// Assamese and Odia are written with escapes on purpose. macOS reports these names
// using the precomposed nukta singletons U+09DF and U+0B5C, while the obvious way to
// type them produces the decomposed pairs U+09AF U+09BC and U+0B21 U+0B3C. The two
// forms render identically and Unicode's composition exclusions mean NFC will not
// convert between them, so a decomposed literal here silently matches nothing.
//
// The Assamese name is genuinely inconsistent with itself: Apple spells the same word
// precomposed before the bullet and decomposed after it. Reproduced verbatim below —
// "fixing" the second half to match the first breaks the lookup.
public let DCSAssameseDictionaryName =
    "Oxford Assamese Dictionaries - \u{985}\u{9B8}\u{9AE}\u{9C0}\u{9DF}\u{9BE}-\u{987}\u{982}\u{9F0}\u{9BE}\u{99C}\u{9C0} \u{2022} \u{987}\u{982}\u{9F0}\u{9BE}\u{99C}\u{9C0}-\u{985}\u{9B8}\u{9AE}\u{9C0}\u{9AF}\u{9BC}\u{9BE}"
public let DCSOdiaDictionaryName =
    "Oxford Odia Dictionaries - \u{B07}\u{B02}\u{B30}\u{B3E}\u{B1C}\u{B40}-\u{B13}\u{B5C}\u{B3F}\u{B06} \u{2022} \u{B13}\u{B5C}\u{B3F}\u{B06}-\u{B07}\u{B02}\u{B30}\u{B3E}\u{B1C}\u{B40}"
public let DCSNepaliDictionaryName = "Oxford Nepali Dictionaries - अङ्ग्रेजी-नेपाली • नेपाली-अङ्ग्रेजी"

// Other Languages
public let DCSIndonesianDictionaryName =
    "Oxford Study Indonesian Dictionary - Inggris-Indonesia • Indonesia-Inggris"
public let DCSMalayDictionaryName =
    "Kamus Dwibahasa Melayu/Inggeris - English/Malay Bilingual Dictionary, Oxford Fajar"

// Reference
public let DCSWikipediaName = "Wikipedia"
