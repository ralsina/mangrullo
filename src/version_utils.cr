module Mangrullo
  # Utility methods for version comparison and parsing
  module VersionUtils
    # Parse a version string into numeric parts
    def self.parse_version(version : String?) : Array(Int32)
      return [] of Int32 unless version

      version.split(/[^\d]/)
        .reject(&.empty?)
        .compact_map(&.to_i?)
        .first(Constants::Version::SEMVER_MAX_PARTS)
    end

    # Compare two version strings
    # Returns: 1 if version1 > version2, 0 if equal, -1 if version1 < version2
    def self.compare_versions(version1 : String?, version2 : String?) : Int32
      parts1 = parse_version(version1)
      parts2 = parse_version(version2)

      # Pad with zeros to make equal length
      max_length = {parts1.size, parts2.size}.max
      parts1 += [0] * (max_length - parts1.size)
      parts2 += [0] * (max_length - parts2.size)

      parts1.each_with_index do |part1, i|
        part2 = parts2[i]
        return 1 if part1 > part2
        return -1 if part1 < part2
      end

      0 # Versions are equal
    end

    # Check if version1 is greater than version2
    def self.greater_than?(version1 : String?, version2 : String?) : Bool
      compare_versions(version1, version2) > 0
    end

    # Check if version1 is less than version2
    def self.less_than?(version1 : String?, version2 : String?) : Bool
      compare_versions(version1, version2) < 0
    end

    # Check if versions are equal
    def self.equal?(version1 : String?, version2 : String?) : Bool
      compare_versions(version1, version2) == 0
    end

    # Check if this is a major version update
    def self.major_update?(local_version : String?, remote_version : String?) : Bool
      return false unless local_version && remote_version

      local_parts = parse_version(local_version)
      remote_parts = parse_version(remote_version)

      # Need at least major version to compare
      return false if local_parts.size < 1 || remote_parts.size < 1

      # Compare major versions
      local_major = local_parts[0]
      remote_major = remote_parts[0]

      remote_major > local_major
    end

    # Get the major version number
    def self.major_version(version : String?) : Int32?
      parts = parse_version(version)
      parts[0]?
    end

    # Get the minor version number
    def self.minor_version(version : String?) : Int32?
      parts = parse_version(version)
      parts[1]?
    end

    # Get the patch version number
    def self.patch_version(version : String?) : Int32?
      parts = parse_version(version)
      parts[2]?
    end

    # Format version for display
    def self.display_version(version : String?) : String
      return "unknown" if version.nil? || version.empty?

      # If it looks like a commit hash, truncate it
      if version.matches?(/^[a-f0-9]+$/i)
        version.size > Constants::Version::SHA256_TRUNCATE_LENGTH ? version[0..Constants::Version::SHA256_TRUNCATE_LENGTH - 1] : version
      else
        version
      end
    end

    # Check if version is likely a commit hash
    def self.commit_hash?(version : String?) : Bool
      return false unless version
      version.matches?(/^[a-f0-9]{7,}$/i)
    end
  end
end
