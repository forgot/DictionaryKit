import MCP

/// Text reused across tool schemas so the alias and defaulting rules are described identically
/// everywhere a dictionary can be named.
private let dictionaryParameterDescription = """
    Dictionary to use: either a short alias such as 'oxford', 'french', or 'japanese', \
    or a full dictionary name as returned by list_dictionaries. \
    Optional — when omitted, the session dictionary set by set_dictionary is used, \
    which defaults to the New Oxford American Dictionary.
    """

/// Returns the list of available tool definitions.
public func getToolDefinitions() -> [Tool] {
    [
        Tool(
            name: "list_dictionaries",
            description: "List all dictionaries installed on this system, with their aliases",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        ),

        Tool(
            name: "search_term",
            description: "Look up a term and return its definitions",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "term": .object([
                        "type": .string("string"),
                        "description": .string("The term to look up"),
                    ]),
                    "dictionary": .object([
                        "type": .string("string"),
                        "description": .string(dictionaryParameterDescription),
                    ]),
                    "include_html": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Include HTML-formatted definitions. Defaults to false; HTML is "
                                + "many times larger than the plain text and is rarely needed."),
                    ]),
                ]),
                "required": .array([.string("term")]),
            ]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        ),

        Tool(
            name: "get_dictionary_info",
            description: "Get metadata for a dictionary",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "dictionary": .object([
                        "type": .string("string"),
                        "description": .string(dictionaryParameterDescription),
                    ])
                ]),
                "required": .array([]),
            ]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        ),

        Tool(
            name: "batch_search",
            description: "Look up one term across several dictionaries in a single call",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "term": .object([
                        "type": .string("string"),
                        "description": .string("The term to look up"),
                    ]),
                    "dictionaries": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Dictionaries to search, each an alias or a full name"),
                    ]),
                    "include_html": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Include HTML-formatted definitions. Defaults to false."),
                    ]),
                ]),
                "required": .array([.string("term"), .string("dictionaries")]),
            ]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        ),

        Tool(
            name: "get_current_dictionary",
            description: "Get the dictionary used when a lookup does not name one",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        ),

        Tool(
            name: "set_dictionary",
            description:
                "Set the dictionary used when a lookup does not name one, for the rest of "
                + "this session. Useful when looking up several terms in the same dictionary.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "dictionary": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Dictionary to make current: a short alias such as 'oxford', "
                                + "or a full dictionary name"),
                    ])
                ]),
                "required": .array([.string("dictionary")]),
            ]),
            // The one tool here that mutates anything. Clients use this hint to decide what
            // needs confirmation, so it must not claim to be read-only.
            annotations: .init(
                readOnlyHint: false, destructiveHint: false, idempotentHint: true,
                openWorldHint: false)
        ),
    ]
}
