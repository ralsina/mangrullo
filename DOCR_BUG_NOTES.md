# Docr Bugs: Missing Optional Fields in Docker API Responses

## Summary
The docr library has multiple issues with handling optional fields in Docker API responses. When the Docker API omits certain fields, docr's strict JSON mapping causes `JSON::ParseException` errors.

## Implementation Status

**These workarounds have been implemented in `src/docr_workarounds.cr`.** This file is automatically required by `docker_client.cr` and patches the docr types to handle missing optional fields.

## Known Issues and Workarounds

### Bug 1: Missing Names field in ContainerSummary

#### Issue
The `Docr::Types::ContainerSummary` class fails to parse Docker API responses when the `Names` field is missing or null.

#### Error Details
```
Missing JSON attribute: Names
parsing Docr::Types::ContainerSummary at line 1, column 2
```

#### Workaround (Implemented)
```crystal
# In src/docr_workarounds.cr
module Docr::Types
  class ContainerSummary
    @[JSON::Field(key: "Names")]
    property names : Array(String) = [] of String
  end
end
```

### Bug 2: Missing ParentId field in ImageSummary

#### Issue
The `Docr::Types::ImageSummary` class fails to parse Docker API responses when the `ParentId` field is missing or null.

#### Error Details
```
Missing JSON attribute: ParentId
parsing Docr::Types::ImageSummary at line 1, column 2
```

#### Workaround (Implemented)
```crystal
# In src/docr_workarounds.cr
module Docr::Types
  class ImageSummary
    @[JSON::Field(key: "ParentId")]
    property parent_id : String = ""
  end
end
```

### Bug 3: Missing Bridge field in NetworkSettings

#### Issue
The `Docr::Types::NetworkSettings` class fails to parse Docker API responses when the `Bridge` field (and other network fields) are missing or null.

#### Error Details
```
Missing JSON attribute: Bridge
parsing Docr::Types::NetworkSettings at line 1, column 5210
```

#### Workaround (Implemented)
All NetworkSettings fields have been made nilable with sensible defaults in `src/docr_workarounds.cr`.

### Bug 4: Missing Comment field in Image

#### Issue
The `Docr::Types::Image` class fails to parse Docker API responses when the `Comment` field (and other fields) are missing or null.

#### Error Details
```
Missing JSON attribute: Comment
parsing Docr::Types::Image at line 1, column 1
```

#### Workaround (Implemented)
All problematic Image fields have been made nilable with sensible defaults in `src/docr_workarounds.cr`.

## Root Cause
The Docker API sometimes omits optional fields in its responses, but docr's JSON mappings require these fields to be present. This is a common issue with many Docker API endpoints.

## Pattern Identified
Multiple docr types have the same issue with optional fields:
- ContainerSummary.names, labels, command, state, status
- ImageSummary.parent_id, shared_size, containers
- NetworkSettings.bridge, sandbox_id, and many other network-related fields
- Image.comment, repo_tags, repo_digests, config, metadata

## Files Modified
- `src/docr_workarounds.cr` - Monkey patches for all affected docr types
- `src/docker_client.cr` - Requires the workarounds file before using docr types

## Impact
These bugs cause entire operations to fail when the Docker API omits optional fields, breaking functionality for applications using docr. The workarounds in `src/docr_workarounds.cr` prevent these failures by providing default values for missing fields.

## References
- Docker API documentation for optional fields
- GitHub Issue: https://github.com/ralsina/mangrullo/issues/4
