# Mangrullo Update Detection Algorithm

## Overview

Mangrullo uses a simplified, efficient approach to detect when Docker container images need updates. The algorithm clearly separates handling for "latest" tags versus versioned tags, optimizing for performance and maintainability.

## Update Decision Flow

### 1. Tag Type Detection

The algorithm first determines the type of image tag:

```crystal
def needs_update?(container : ContainerInfo, allow_major_upgrade : Bool = false) : Bool
  # If using 'latest' tag, use simple digest comparison
  if container.image.includes?("latest")
    return image_has_update?(container.image)
  end

  # For versioned tags, find available updates based on version
  current_version = extract_version_from_image(container.image)
  return false unless current_version

  target_version = find_target_update_version(container.image, current_version, allow_major_upgrade)
  target_version != nil
end
```

### 2. Latest Tag Handling

For images using `:latest` tags, the algorithm uses simple digest comparison:

```crystal
def image_has_update?(image_name : String) : Bool
  local_digest = get_local_image_digest(image_name)
  return false unless local_digest

  remote_digest = get_remote_image_digest(image_name)
  return false unless remote_digest

  local_digest != remote_digest
end
```

**Benefits:**
- Single API call to get remote manifest digest
- No need to parse hundreds or thousands of tags
- Fast and efficient

### 3. Versioned Tag Handling

For images with semantic version tags (e.g., `nginx:1.2.3`):

#### 3.1 Version Extraction
```crystal
def extract_version_from_image(image_name : String) : Version?
  # Skip SHA256 digests (they are image IDs, not versioned images)
  return nil if image_name.starts_with?("sha256:")

  # Extract tag from image name (format: name:tag or name)
  parts = image_name.split(":")
  tag = parts.size > 1 ? parts.last : "latest"

  Version.parse(tag)
end
```

#### 3.2 Target Version Discovery
```crystal
def find_target_update_version(image_name : String, current_version : Version, allow_major_upgrade : Bool) : Version?
  # Get all available versions from the registry
  all_versions = get_all_versions(image_name)
  return nil if all_versions.empty?

  # Filter versions that are newer than current version
  newer_versions = all_versions.select { |v| v > current_version }
  
  # Filter by major upgrade preference
  if allow_major_upgrade
    # Allow any newer version
    newer_versions.max?
  else
    # Only allow minor/patch updates within the same major version
    same_major_versions = newer_versions.select { |v| v.major == current_version.major }
    same_major_versions.max?
  end
end
```

#### 3.3 Version Collection
```crystal
def get_all_versions(image_name : String) : Array(Version)
  # Single API call to get all tags
  response = registry_client.get("/v2/#{repository_path}/tags/list")
  
  # Parse and filter semantic versions
  tags = json["tags"].as_a.map(&.as_s)
  versions = tags.compact_map { |tag| Version.parse(tag) }
  versions.sort!
end
```

## Data Sources

### Local Information
- **Docker Daemon** via Docr API
- Container running state and image references
- Local image digests and metadata

### Remote Information  
- **Registry APIs** with authentication support:
  - **Docker Hub**: `registry-1.docker.io`
  - **GitHub Container Registry**: `ghcr.io`
  - **Other registries**: Dynamic detection

**Authentication:**
- JWT token authentication with caching
- Support for both Docker Hub and ghcr.io token endpoints
- Graceful fallback to unauthenticated requests

## Message Generation

The algorithm generates clean, user-friendly messages:

### Latest Tags
```
"Update available for ghcr.io/home-assistant/home-assistant:latest (current: latest)"
```

### Versioned Tags
```
"Version update available: 1.2.0 -> 1.4.5"
```

## Key Methods and Their Roles

### Core Methods

#### `needs_update?(container, allow_major_upgrade)`
Main entry point - routes to appropriate detection strategy based on tag type

#### `image_has_update?(image_name)`
Handles latest tag updates via digest comparison

#### `find_target_update_version(image_name, current_version, allow_major_upgrade)`
Finds the best available update version based on current version and upgrade preferences

#### `get_all_versions(image_name)`
Performs single API call to get all available versions from registry

#### `extract_version_from_image(image_name)`
Parses semantic version from image tag

### Authentication Methods

#### `get_registry_token(registry_host, repository_path)`
Fetches JWT tokens for registry authentication with caching

#### `create_authenticated_client(registry_host, repository_path)`
Creates HTTP client with proper authorization headers

## Registry Support

### Supported Registries
- **Docker Hub** (`registry-1.docker.io`)
- **GitHub Container Registry** (`ghcr.io`)
- **Generic registries** with standard API v2

### Registry Detection
```crystal
# Automatic registry host detection
if base_name.includes?("/")
  parts = base_name.split("/")
  if parts[0].includes?(".") || parts[0].includes?(":")
    registry_host = parts[0]
    repository_path = parts[1..-1].join("/")
  end
end
```

### Special Mappings
- `lscr.io` → redirects to `ghcr.io/linuxserver/`

## Version Parsing Support

### Supported Formats
- Standard semver: `1.2.3`
- Prereleases: `1.2.3-alpha`, `1.2.3-beta.1`
- Build metadata: `1.2.3+build.123` (ignored in comparison)
- 'v' prefix: `v1.2.3`

### Exclusions
- `latest` tags (handled separately)
- SHA256 digests (image IDs)
- Non-semantic version strings

## Major Upgrade Control

The `allow_major_upgrade` parameter controls upgrade behavior:
- **`true`**: Any version increase (1.2.3 → 2.0.0)
- **`false`**: Only minor/patch updates (1.2.3 → 1.3.0, NOT 1.2.3 → 2.0.0)

## Performance Characteristics

### API Efficiency
- **Latest tags**: 2 API calls (local digest + remote manifest)
- **Versioned tags**: 1 API call (tags list) + local version parsing
- **No individual tag checking**: Eliminated the N+1 query problem

### Authentication Caching
- JWT tokens cached with 4-minute expiration
- Reduces authentication overhead for multiple checks

### Network Optimization
- Single HTTP request per image for versioned tags
- Proper error handling and graceful degradation
- Minimal external dependencies

## Error Handling

### Graceful Degradation
- Network failures → return false (no update detected)
- API errors → log debug information and continue
- Authentication failures → fall back to unauthenticated requests
- Parsing failures → skip problematic containers

### Resilience Features
- Rescue blocks around all external API calls
- Container-level error isolation
- Comprehensive debug logging
- Authentication token caching

## Security Considerations

### Authentication
- JWT tokens from official registry endpoints
- Token caching with proper expiration
- No hardcoded credentials

### Registry Communication
- HTTPS-only communication
- Standard Docker Registry API v2
- Support for private registries with authentication

## Future Improvements

### Enhanced Registry Support
- Additional registry types (GitLab, ECR, GCR)
- Registry-specific configuration
- Custom authentication methods

### Performance Optimizations
- Parallel container checking
- Response caching for repeated checks
- Batch operations for multiple images

### User Experience
- More detailed update information
- Change log integration
- Security vulnerability reporting

### Configuration Options
- Per-image update policies
- Custom version filtering rules
- Registry-specific settings