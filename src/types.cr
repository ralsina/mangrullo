require "json"

module Mangrullo
  struct ContainerInfo
    include JSON::Serializable

    property id : String
    property name : String
    property image : String
    property image_id : String
    property labels : Hash(String, String)
    property status : String
    property created : Time

    def initialize(@id : String, @name : String, @image : String, @image_id : String, @labels : Hash(String, String), @status : String, @created : Time)
    end
  end

  struct ImageInfo
    include JSON::Serializable

    property id : String
    property repo_tags : Array(String)
    property created : Time
    property size : UInt64
    property labels : Hash(String, String)

    def initialize(@id : String, @repo_tags : Array(String), @created : Time, @size : UInt64, @labels : Hash(String, String))
    end
  end

  struct Version
    include JSON::Serializable
    include Comparable(Version)

    property major : Int32
    property minor : Int32
    property patch : Int32
    property prerelease : String?
    property build : String?

    def initialize(@major : Int32, @minor : Int32, @patch : Int32, @prerelease : String? = nil, @build : String? = nil)
    end

    def self.parse(tag : String) : Version?
      return nil if tag.blank?

      # Remove registry prefix if present
      tag = tag.split("/").last

      # Remove 'v' prefix if present
      tag = tag.lchop('v')

      # Split version from build metadata
      parts = tag.split('+', 2)
      version_part = parts[0]
      build_part = parts.size > 1 ? parts[1] : nil

      # Split version from prerelease
      parts = version_part.split('-', 2)
      version_part = parts[0]
      prerelease_part = parts.size > 1 ? parts[1] : nil

      # Parse semantic version
      parts = version_part.split('.')
      return nil unless parts.size >= 2 && parts.size <= 3

      major = parts[0].to_i?
      minor = parts[1].to_i?
      patch = parts[2]?.try(&.to_i?) || 0

      return nil unless major && minor

      Version.new(major, minor, patch, prerelease_part, build_part)
    end

    def major_upgrade?(other : Version) : Bool
      self.major != other.major
    end

    def <=>(other : Version) : Int32
      if major != other.major
        major <=> other.major
      elsif minor != other.minor
        minor <=> other.minor
      elsif patch != other.patch
        patch <=> other.patch
      elsif prerelease != other.prerelease
        compare_prereleases(prerelease, other.prerelease)
      else
        0 # Versions are exactly equal
      end
    end

    private def compare_prereleases(self_prerelease : String?, other_prerelease : String?) : Int32
      return -1 if self_prerelease && !other_prerelease # prerelease < release
      return 1 if !self_prerelease && other_prerelease  # release > prerelease
      return 0 if !self_prerelease && !other_prerelease # both are releases

      # Both have prereleases, compare them as strings
      if (self_pre = self_prerelease) && (other_pre = other_prerelease)
        self_pre <=> other_pre
      else
        0
      end
    end

    def to_s : String
      result = "#{major}.#{minor}.#{patch}"
      result += "-#{prerelease}" if prerelease
      result += "+#{build}" if build
      result
    end
  end
end
