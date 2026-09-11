# Mangrullo Update Detection Algorithm

## Overview

Mangrullo detects when Docker container images need updates and decides which
image reference an update should move to. The algorithm separates **moving
tags** (which are compared by digest) from **versioned tags** (which are
compared by semantic version), and detection is paired with execution: the
same logic that detects an update also computes the target image reference to
pull and recreate the container with.

## Update Decision Flow

### 1. Tag Type Detection

The algorithm first determines whether the tag is a *moving tag*:

```crystal
def needs_update?(container : ContainerInfo, allow_major_upgrade : Bool = false) : Bool
  # Moving tags (latest, single-component like postgres:16, digest pins,
  # or non-version tags) are compared by digest, not by version
  if moving_tag?(container)
    status = get_update_status(container)
    return status[:needs_pull] || status[:needs_restart]
  end

  # For versioned tags, find available updates based on version
  current_version = extract_version_from_image(container.image)
  return false unless current_version

  target_version = find_target_update_version(container.image, current_version, allow_major_upgrade)
  target_version != nil
end

# A tag that tracks a moving ref rather than a fixed version
private def moving_tag?(container : ContainerInfo) : Bool
  return true if container.image.includes?("sha256:")

  tag = ImageNameParser.get_tag(container.image)
  !tag.includes?(".")
end
```

Moving tags are: `latest`, single-component tags (`postgres:16`, `redis:7`),
digest pins (`image@sha256:…`), and non-version tags (`stable`, `alpine`). All
of them are compared by digest.

### 1.1 Enhanced Update Status Detection

For moving tags, the algorithm compares local and remote digests:

```crystal
def get_update_status(container : ContainerInfo) :
    NamedTuple(needs_pull: Bool, needs_restart: Bool,
               local_digest: String?, remote_digest: String?)
  local_digest = get_local_image_digest(container.image)
  remote_digest = get_remote_image_digest(container.image)

  {
    needs_pull:    local_digest != remote_digest,
    needs_restart: local_digest == remote_digest && container.image.includes?("latest")
  }
end
```

### 2. Moving Tag Handling

For moving tags, the update is a re-pull of the same reference:

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
- Rolling tags (`postgres:16`) keep following their major instead of being
  "upgraded" to a different tag

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

Single-component tags parse as major-only versions (`16` → `16.0.0`), but
since they are moving tags they never reach the version path — they are
handled by digest comparison instead.

#### 3.2 Target Tag Discovery

`find_target_update_version` delegates to `find_target_update_tag`, which
returns the **actual registry tag string** for the target (the tag must exist
upstream to be pullable — version objects alone would lose spellings like a
`v` prefix):

```crystal
def find_target_update_tag(image_name : String, current_version : Version,
                           allow_major_upgrade : Bool) : String?
  candidates = registry_version_tags(image_name).select do |pair|
    pair[:version] > current_version &&
      (allow_major_upgrade || pair[:version].major == current_version.major)
  end

  best = candidates.max_by? { |pair| pair[:version] }
  best.try &.[:tag]
end
```

#### 3.3 Version Collection

```crystal
def registry_version_tags(image_name : String) : Array(NamedTuple(tag: String, version: Version))
  # Single API call to get all tags
  response = fetch_registry_tags(registry_host, repository_path)

  json = JSON.parse(response.body)
  tags = json["tags"].as_a.map(&.as_s)
  tags.compact_map { |tag|
    version = Version.parse(tag)
    version ? {tag: tag, version: version} : nil
  }
end
```

## From Detection to Update

Detection alone is not enough — the update must know *which reference to
pull*. `ImageChecker#target_image_for_update` mirrors the detection logic:

```crystal
def target_image_for_update(container : ContainerInfo,
                            allow_major_upgrade : Bool = false) : String?
  return container.image if moving_tag?(container)

  current_version = extract_version_from_image(container.image)
  return container.image unless current_version

  target_tag = find_target_update_tag(container.image, current_version, allow_major_upgrade)
  return container.image unless target_tag

  repository = ImageNameParser.parse(container.image)[:repository]
  ImageNameParser.format_with_tag(repository, target_tag)
end
```

`UpdateManager#update_container` then:

1. Pulls `repository:target_tag` (name and tag passed **separately** to the
   Docker API so the registry port cannot be mistaken for a tag)
2. Recreates the container with the pulled image — digest-pinned
   (`repo@sha256:…`) when the local digest matches the remote, otherwise the
   target reference
3. Rolls back safely if recreation fails: the old container is renamed to a
   backup and restored if the replacement cannot be created or started

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

```text
"Update available for ghcr.io/home-assistant/home-assistant:latest (current: latest)"
```

### Versioned Tags

```text
"Version update available: 1.2.0 -> 1.4.5"
```

## Key Methods and Their Roles

### Core Methods

#### `needs_update?(container, allow_major_upgrade)`

Main entry point - routes to appropriate detection strategy based on tag type

#### `moving_tag?(container)`

Decides whether a tag tracks a moving ref (digest comparison) or a fixed version (semver comparison)

#### `target_image_for_update(container, allow_major_upgrade)`

Computes the image reference an update should pull and recreate with: the newer tag for versioned images, the same reference for moving tags

#### `find_target_update_tag(image_name, current_version, allow_major_upgrade)`

Returns the actual registry tag string of the best available update

#### `find_target_update_version(image_name, current_version, allow_major_upgrade)`

Parses the target tag into a `Version` (a thin wrapper over `find_target_update_tag`)

#### `registry_version_tags(image_name)`

Performs a single API call to get all registry tags paired with their parsed versions

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
# Automatic registry host detection: a first path segment containing "." or
# ":" marks a custom registry host (e.g. ghcr.io/user/image, localhost:5000/app)
first_slash = base_name.index('/')
prefix = first_slash ? base_name[0...first_slash] : nil

if prefix && (prefix.includes?(".") || prefix.includes?(":"))
  registry_host = prefix
  repository_path = base_name[(prefix.size + 1)..]
elsif prefix
  # Docker Hub namespace/image (e.g. user/nginx)
  registry_host = "registry-1.docker.io"
  repository_path = base_name
else
  # Simple image name, assume Docker Hub library
  registry_host = "registry-1.docker.io"
  repository_path = "library/#{base_name}"
end
```

### Special Mappings

- `lscr.io` → redirects to `ghcr.io/linuxserver/` (with double-prefix prevention)

The algorithm handles the lscr.io to ghcr.io mapping with special logic to avoid double "linuxserver" prefixes:

```crystal
# Handle special registry mappings
if registry_host == "lscr.io"
  # lscr.io is a vanity URL that redirects to ghcr.io
  # Images are actually hosted at ghcr.io/linuxserver
  registry_host = "ghcr.io"
  # Don't double-prepend linuxserver if it's already there
  unless repository_path.starts_with?("linuxserver/")
    repository_path = "linuxserver/#{repository_path}"
  end
end
```

## Version Parsing Support

### Supported Formats

- Standard semver: `1.2.3`
- Two-component versions: `1.2` (patch defaults to 0)
- Single-component tags: `16` (parsed as `16.0.0`, but treated as a moving tag)
- Prereleases: `1.2.3-alpha`, `1.2.3-beta.1`
- Build metadata: `1.2.3+build.123` (ignored in comparison)
- 'v' prefix: `v1.2.3`

### Digest-Based Handling

- `latest` tags (handled by digest comparison)
- SHA256 digest pins (handled by digest comparison)
- Non-semantic version tags like `stable` (handled by digest comparison)
- Rolling single-number tags like `postgres:16` (handled by digest comparison)

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
- Credentials from the user's `~/.docker/config.json` are used when an entry
  matches the registry (including the legacy `https://index.docker.io/v1/`
  spelling), enabling private images and avoiding Docker Hub anonymous rate
  limits; `credsStore`-delegated entries are skipped
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
