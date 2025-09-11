# Docr Bugs: Missing Optional Fields in Docker API Responses

## Summary
The docr library has multiple issues with handling optional fields in Docker API responses. When the Docker API omits certain fields, docr's strict JSON mapping causes `JSON::ParseException` errors.

## Bug 1: Missing Names field in ContainerSummary

### Issue
The `Docr::Types::ContainerSummary` class fails to parse Docker API responses when the `Names` field is missing or null.

### Error Details
```
Missing JSON attribute: Names
parsing Docr::Types::ContainerSummary at line 1, column 2
```

### Workaround
```crystal
# Monkey patch Docr::Types::ContainerSummary to handle missing Names field
module Docr::Types
  class ContainerSummary
    def names : Array(String)
      # If names is nil or empty, return an array with the ID as fallback
      @names || ["/#{id[0..12]}"]
    end
  end
end
```

## Bug 2: Missing ParentId field in ImageSummary

### Issue
The `Docr::Types::ImageSummary` class fails to parse Docker API responses when the `ParentId` field is missing or null.

### Error Details
```
Missing JSON attribute: ParentId
parsing Docr::Types::ImageSummary at line 1, column 2
```

### Workaround
```crystal
# Monkey patch Docr::Types::ImageSummary to handle missing ParentId field
module Docr::Types
  class ImageSummary
    def parent_id : String?
      @parent_id
    end
  end
end
```

## Root Cause
The Docker API sometimes omits optional fields in its responses, but docr's JSON mappings require these fields to be present. This is a common issue with many Docker API endpoints.

## Pattern Identified
Multiple docr types have the same issue with optional fields:
- ContainerSummary.names
- ImageSummary.parent_id
- Potentially other fields in other types

## Expected Fixes
For each affected class in docr:

1. Make optional fields nilable in the JSON mapping
2. Provide sensible defaults when fields are missing
3. Follow Docker's API documentation about which fields are optional

## Files to Check in Docr
- All type definitions in `Docr::Types` module
- JSON mappings for optional fields
- Error handling for missing fields

## Impact
These bugs cause entire operations to fail when the Docker API omits optional fields, breaking functionality for applications using docr.

## References
- Docker API documentation for optional fields
- The pattern suggests a systematic review of all docr type definitions is needed