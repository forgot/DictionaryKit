import MCP

/// Returns the list of available resource definitions
func getResourceDefinitions() -> [Resource] {
    [
        Resource(
            name: "Available Dictionaries",
            uri: "dictionary://list",
            description: "The current list of all installed dictionaries",
            mimeType: "application/json"
        ),

        Resource(
            name: "Dictionary Aliases",
            uri: "dictionary://aliases",
            description: "Mapping of type-safe dictionary aliases to full dictionary names",
            mimeType: "application/json"
        ),
    ]
}
