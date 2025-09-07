# Mangrullo Update Detection Algorithm

## Overview

Mangrullo uses a hierarchical approach to detect when Docker container images need updates. The algorithm prioritizes semantic version comparison for clear user messaging and falls back to digest comparison for complex or non-standard image naming schemes.

## Update Decision Flow

### 1. Primary Check: Special Tags
```crystal
return true if container.image.includes?("latest")
```
- **Always considers `:latest` tags as outdated**
- This is a safety measure since `:latest` by definition should be the most recent

### 2. Version-Based Detection (Preferred)

#### 2.1 Enhanced Local Version Detection
The algorithm first tries to determine the actual semantic version of the running container:

```crystal
# Step 1: Try digest-based version lookup (most accurate)
local_version = get_current_version_from_digest(image_name)

# Step 2: Fall back to tag parsing if digest fails
local_version ||= extract_version_from_image(image_name)
```

**Digest-based Version Lookup:**
1. Get local image digest from Docker daemon
2. Query Docker Hub API for all tags pointing to that digest
3. Extract semantic versions from those tags
4. Return the highest semantic version found

**Tag-based Version Extraction:**
- Parses version from image tag (e.g., `nginx:1.21.0` → `1.21.0`)
- Supports semantic versioning with prereleases and build metadata
- Handles `v` prefixes (e.g., `v1.2.3`)

#### 2.2 Remote Version Detection
```crystal
remote_version = get_latest_version(image_name)
```
- Queries Docker Hub API at `/v2/{image}/tags/list`
- Parses all available tags to find the highest semantic version
- Returns `nil` if no semantic versions can be found

#### 2.3 Version Comparison
```crystal
if allow_major_upgrade
  remote_version > local_version  # Any version increase
else
  remote_version > local_version && !current_version.major_upgrade?(remote_version)
end
```

### 3. Fallback: Digest Comparison

When version-based detection fails:
```crystal
def image_has_update?(image_name : String) : Bool
  local_digest = get_local_image_digest(image_name)
  remote_digest = get_remote_image_digest(image_name)
  local_digest != remote_digest
end
```

## Data Sources

### Local Information
- **Docker Daemon** via Docr API
- Container running state and image references
- Local image digests and metadata

### Remote Information  
- **Docker Hub Registry API** (`registry-1.docker.io`)
- **Endpoints:**
  - `/v2/{image}/tags/list` - for version discovery
  - `/v2/{image}/manifests/{tag}` - for digest retrieval
  - Individual manifest checks for digest-to-tag mapping

## Message Generation Hierarchy

The algorithm generates user-friendly messages based on what information is available:

### 1. Full Version Information (Best)
```
"Version update available: 1.2.3 -> 1.2.4"
```

### 2. Current Version Known
```
"Update available for nginx:latest (current: 1.21.6)"
```

### 3. Digest Difference with Version Info
```
"Update available for redis (digest differs)"
```
*Note: Tries digest-based version lookup first*

### 4. Image ID Available
```
"Update available for app (image ID: sha256:1a2b3c...)"
```

### 5. Generic Fallback
```
"Update available for app"
```

## Key Methods and Their Roles

### ImageChecker Methods

#### `needs_update?(container, allow_major_upgrade)`
Main entry point - determines if an update is needed

#### `get_current_version_from_digest(image_name)`
**NEW:** Gets actual semantic version of running container by:
1. Getting local image digest
2. Finding all tags pointing to that digest
3. Extracting and returning highest semantic version

#### `extract_version_from_image(image_name)`
Original method - parses version from image tag name

#### `get_latest_version(image_name)`
Gets highest semantic version available remotely

#### `get_tags_for_digest(image_name, digest)`
**NEW:** Returns all tags that point to a specific digest

#### `get_local_image_digest(image_name)`
Gets SHA256 digest of local image

#### `get_remote_image_digest(image_name)`
Gets SHA256 digest of remote image manifest

#### `image_has_update?(image_name)`
Fallback method using digest comparison

### Version Comparison
- Uses standard semantic versioning rules
- Supports prerelease versions (alpha, beta, etc.)
- Ignores build metadata in comparisons
- Major upgrade control via `allow_major_upgrade` flag

## Registry Limitations

### Current Limitations
1. **Docker Hub Only:** Hardcoded to `registry-1.docker.io`
2. **No Authentication:** Doesn't support private registries
3. **Image Name Parsing:** Strips registry prefixes, so `gcr.io/app` becomes `app`

### What Breaks with Non-Docker Hub Images
- Google Container Registry (`gcr.io`)
- GitLab Registry (`registry.gitlab.com`)
- Amazon ECR, Azure Container Registry
- Private registries

### Current Behavior for Non-Docker Hub
- Version detection typically fails
- Falls back to digest comparison
- Shows generic "update available" messages
- May miss updates entirely

## Version Parsing Support

### Supported Formats
- Standard semver: `1.2.3`
- Prereleases: `1.2.3-alpha`, `1.2.3-beta.1`
- Build metadata: `1.2.3+build.123` (ignored in comparison)
- 'v' prefix: `v1.2.3`

### Unsupported Scenarios
- Custom version schemes (dates, commit hashes)
- Floating tags without semantic versions (`:stable`, `:alpine`)
- Images from non-Docker Hub registries

## Major Upgrade Control

The `allow_major_upgrade` parameter controls upgrade behavior:
- **`true`**: Any version increase (1.2.3 → 2.0.0)
- **`false`**: Only minor/patch updates (1.2.3 → 1.3.0, NOT 1.2.3 → 2.0.0)

This is implemented via the `major_upgrade?` method:
```crystal
def major_upgrade?(other : Version) : Bool
  self.major != other.major
end
```

## Error Handling

### Graceful Degradation
The algorithm is designed to fail gracefully:
- Network failures → fall back to digest comparison
- API rate limits → show generic messages
- Parsing failures → use alternative methods
- Registry issues → skip problematic containers

### Resilience Features
- Rescue blocks around all external API calls
- Multiple fallback strategies
- Container-level error isolation (one failure doesn't stop all checks)

## Performance Considerations

### API Calls
- Each image may require multiple Docker Hub API calls
- Digest-based lookup requires N+1 calls (one for tag list, one per tag)
- No caching of remote data (fresh check each time)

### Network Dependency
- Requires internet access to Docker Hub API
- No offline mode capability
- Rate limiting could impact large deployments

## Future Improvements

### Registry Support
- Dynamic registry detection from image names
- Support for multiple registry APIs
- Authentication for private registries

### Performance
- API response caching
- Batch operations for multiple images
- Parallel version checking

### Enhanced Messaging
- Change logs and release notes
- Security vulnerability information
- Download size estimates

### Configuration
- Per-image registry configuration
- Custom version parsing rules
- Whitelisting/blacklisting of updates