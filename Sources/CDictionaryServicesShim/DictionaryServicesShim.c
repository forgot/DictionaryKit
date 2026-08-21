/// \file DictionaryServicesShim.c
/// \brief C shim layer for runtime loading of private Dictionary Services APIs.
///
/// This module provides a thin C abstraction over macOS's private DictionaryServices APIs,
/// using dynamic symbol loading to safely access frameworks without compile-time linking.
///
/// ## Design
///
/// Instead of linking against private frameworks at compile time (which would break on systems
/// where the frameworks have moved or changed), this shim uses dlopen() and dlsym() to load
/// symbols at runtime. This provides:
///
/// - **Compatibility**: Works across different macOS versions with varying framework locations
/// - **Safety**: Graceful degradation if APIs are unavailable
/// - **Privacy**: No compile-time dependency on private frameworks
///
/// ## Symbol Loading Strategy
///
/// 1. The first time any function is called, dkds_load_library() attempts to load the
///    DictionaryServices framework from multiple known paths
/// 2. If loading succeeds, subsequent calls use dlsym() to look up individual symbols
/// 3. If a symbol is missing, the function returns NULL for safe fallback handling
/// 4. Thread safety is ensured through pthread_once() for one-time initialization
///
/// ## Framework Search Paths
///
/// The loader tries these paths in order:
/// - /System/Library/Frameworks/CoreServices.framework/Frameworks/DictionaryServices.framework/DictionaryServices
/// - /System/Library/PrivateFrameworks/DictionaryServices.framework/DictionaryServices
/// - /System/Library/PrivateFrameworks/DictionaryServicesCore.framework/DictionaryServicesCore

#include "DictionaryServicesShim.h"

#include <dlfcn.h>
#include <pthread.h>
#include <CoreFoundation/CoreFoundation.h>

/// Global handle to the loaded DictionaryServices framework, or NULL if not loaded.
static void *dkds_handle = NULL;

/// Ensures dkds_try_load() is called exactly once, even in multi-threaded contexts.
static pthread_once_t dkds_once = PTHREAD_ONCE_INIT;

/// Attempts to load the DictionaryServices framework from known locations.
///
/// This function is called exactly once via pthread_once(). It tries multiple known
/// framework paths and sets dkds_handle on success, leaving it NULL on failure.
static void dkds_try_load(void) {
    const char *paths[] = {
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/DictionaryServices.framework/DictionaryServices",
        "/System/Library/PrivateFrameworks/DictionaryServices.framework/DictionaryServices",
        "/System/Library/PrivateFrameworks/DictionaryServicesCore.framework/DictionaryServicesCore"
    };

    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
        dkds_handle = dlopen(paths[i], RTLD_LAZY | RTLD_LOCAL);
        if (dkds_handle != NULL) {
            break;
        }
    }
}

/// Loads the DictionaryServices framework using pthread_once() for thread safety.
///
/// This function should be called before any other dkds_* function to ensure the framework
/// is loaded. It is safe to call multiple times from different threads.
///
/// \return true if the framework was successfully loaded, false otherwise
bool dkds_load_library(void) {
    pthread_once(&dkds_once, dkds_try_load);
    return dkds_handle != NULL;
}

/// Dynamically looks up a symbol by name in the loaded framework.
///
/// This is the core function for runtime symbol resolution. It returns NULL if the framework
/// is not loaded or if the symbol cannot be found.
///
/// \param symbol The name of the symbol to look up (e.g., "DCSCopyAvailableDictionaries")
/// \return A pointer to the symbol, or NULL if not found
static void *dkds_lookup(const char *symbol) {
    if (!dkds_load_library()) {
        return NULL;
    }

    return dlsym(dkds_handle, symbol);
}

/// Checks if a symbol is available in the loaded framework.
///
/// Useful for runtime capability detection.
///
/// \param symbolName The name of the symbol to check
/// \return true if the symbol is available, false otherwise
bool dkds_has_symbol(const char *symbolName) {
    return dkds_lookup(symbolName) != NULL;
}

/// Retrieves the set of all available dictionaries on the system.
///
/// \return A CFSetRef containing available dictionary references, or NULL if the symbol
///         cannot be loaded or the operation fails
/// \note The returned set is +1 and declared CF_RETURNS_RETAINED in the header, so Swift
///       releases it automatically. The set owns its members: the individual
///       DCSDictionaryRef values are only valid for as long as the set is alive.
CFSetRef dkds_copy_available_dictionaries(void) {
    typedef CFSetRef (*fn_t)(void);
    fn_t fn = (fn_t)dkds_lookup("DCSCopyAvailableDictionaries");
    if (fn == NULL) {
        return NULL;
    }

    return fn();
}

/// Retrieves the full name of a dictionary.
///
/// \param dictionary The dictionary reference to query
/// \return A CFStringRef containing the dictionary's full name, or NULL on error
/// \note Returns NOT_RETAINED - caller should not release the string
CFStringRef dkds_get_dictionary_name(DCSDictionaryRef dictionary) {
    typedef CFStringRef (*fn_t)(DCSDictionaryRef);
    fn_t fn = (fn_t)dkds_lookup("DCSDictionaryGetName");
    if (fn == NULL) {
        return NULL;
    }

    return fn(dictionary);
}

/// Retrieves the short name of a dictionary, if available.
///
/// \param dictionary The dictionary reference to query
/// \return A CFStringRef containing the dictionary's short name, or NULL if unavailable or on error
/// \note Returns NOT_RETAINED - caller should not release the string
CFStringRef dkds_get_dictionary_short_name(DCSDictionaryRef dictionary) {
    typedef CFStringRef (*fn_t)(DCSDictionaryRef);
    fn_t fn = (fn_t)dkds_lookup("DCSDictionaryGetShortName");
    if (fn == NULL) {
        return NULL;
    }

    return fn(dictionary);
}

/// Searches a dictionary for records matching a search string.
///
/// Performs the core dictionary search operation, returning all matching records
/// for the given search term.
///
/// \param dictionary The dictionary to search in
/// \param string The search term as a CFString
/// \return A CFArrayRef containing matching DCSRecord references, or NULL on error
/// \note The last two parameters passed to the underlying API are NULL (reserved)
CFArrayRef dkds_copy_records_for_search_string(DCSDictionaryRef dictionary, CFStringRef string) {
    typedef CFArrayRef (*fn_t)(DCSDictionaryRef, CFStringRef, void *, void *);
    fn_t fn = (fn_t)dkds_lookup("DCSCopyRecordsForSearchString");
    if (fn == NULL) {
        return NULL;
    }

    return fn(dictionary, string, NULL, NULL);
}

/// Retrieves the formatted data for a dictionary record in a specific format.
///
/// \param record The record to retrieve data from
/// \param version The format version (0=HTML, 1=HTML with App CSS, 2=HTML with Popover CSS, 3=Plain Text)
/// \return A CFStringRef containing the formatted data, or NULL if unavailable or on error
/// \note Returns RETAINED - caller is responsible for releasing the string
CFStringRef dkds_record_copy_data(DCSRecordRef record, long version) {
    typedef CFStringRef (*fn_t)(DCSRecordRef, long);
    fn_t fn = (fn_t)dkds_lookup("DCSRecordCopyData");
    if (fn == NULL) {
        return NULL;
    }

    return fn(record, version);
}

/// Retrieves the headword (entry term) for a dictionary record.
///
/// \param record The record to retrieve the headword from
/// \return A CFStringRef containing the headword, or NULL if unavailable or on error
/// \note Returns NOT_RETAINED - caller should not release the string
CFStringRef dkds_get_record_headword(DCSRecordRef record) {
    typedef CFStringRef (*fn_t)(DCSRecordRef);
    fn_t fn = (fn_t)dkds_lookup("DCSRecordGetHeadword");
    if (fn == NULL) {
        return NULL;
    }

    return fn(record);
}

/// Retrieves the title for a dictionary record.
///
/// \param record The record to retrieve the title from
/// \return A CFStringRef containing the title, or NULL if unavailable or on error
/// \note Returns NOT_RETAINED - caller should not release the string
/// \note DCSRecordGetTitle is treated as optional. It is absent from the required-symbol
///       list in DictionaryService, so a macOS release that does not export it degrades
///       to entries without titles rather than disabling the library.
CFStringRef dkds_get_record_title(DCSRecordRef record) {
    typedef CFStringRef (*fn_t)(DCSRecordRef);
    fn_t fn = (fn_t)dkds_lookup("DCSRecordGetTitle");
    if (fn == NULL) {
        return NULL;
    }

    return fn(record);
}

/// Identifies the range of the search term within a candidate string.
///
/// Used during search preprocessing to identify where the actual search term appears
/// within a longer text string.
///
/// \param dictionary The dictionary being searched (provides language/normalization context)
/// \param string The string to search within
/// \param range The range within the string to consider
/// \return A CFRange indicating where the term was found, or {kCFNotFound, 0} if not found
CFRange dkds_get_term_range_in_string(DCSDictionaryRef dictionary, CFStringRef string, CFRange range) {
    typedef CFRange (*fn_t)(DCSDictionaryRef, CFStringRef, CFRange);
    fn_t fn = (fn_t)dkds_lookup("DCSGetTermRangeInString");
    if (fn == NULL) {
        CFRange notFound = {kCFNotFound, 0};
        return notFound;
    }

    return fn(dictionary, string, range);
}
