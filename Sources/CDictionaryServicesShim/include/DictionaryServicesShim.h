#ifndef DICTIONARYSERVICESSHIM_H
#define DICTIONARYSERVICESSHIM_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>

// Lightweight typedefs to avoid depending on private headers.
typedef const void * DCSDictionaryRef;
typedef const void * DCSRecordRef;

// Attempts to load the private DictionaryServices library. Returns true on success.
bool dkds_load_library(void);

// Returns true if the named symbol exists in the loaded library.
bool dkds_has_symbol(const char *symbolName);

// The CF_RETURNS_* annotations below are what make this safe to call from Swift: they tell
// the Swift importer the ownership convention of each underlying DictionaryServices function,
// so ARC balances the retains for us. They are load-bearing, not decoration.
//
// `dkds_get_*` wrap DCS…Get… functions, which return +0 (unowned) values.
// `dkds_copy_*` wrap DCS…Copy… functions, which return +1 (owned) values.
// Keep the prefix and the annotation in agreement when adding to this list.
CF_RETURNS_RETAINED CFSetRef dkds_copy_available_dictionaries(void);
CF_RETURNS_NOT_RETAINED CFStringRef dkds_get_dictionary_name(DCSDictionaryRef dictionary);
CF_RETURNS_NOT_RETAINED CFStringRef dkds_get_dictionary_short_name(DCSDictionaryRef dictionary);
CF_RETURNS_RETAINED CFArrayRef dkds_copy_records_for_search_string(DCSDictionaryRef dictionary, CFStringRef string);
CF_RETURNS_RETAINED CFStringRef dkds_record_copy_data(DCSRecordRef record, long version);
CF_RETURNS_NOT_RETAINED CFStringRef dkds_get_record_headword(DCSRecordRef record);
CF_RETURNS_NOT_RETAINED CFStringRef dkds_get_record_title(DCSRecordRef record);
CFRange dkds_get_term_range_in_string(DCSDictionaryRef dictionary, CFStringRef string, CFRange range);

#endif // DICTIONARYSERVICESSHIM_H
