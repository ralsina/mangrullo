module Mangrullo
  # Utility class for parsing and manipulating Docker image names
  class ImageNameParser
    # Parse image name into repository and tag parts
    def self.parse(image_name : String) : NamedTuple(repository: String, tag: String)
      parts = image_name.split(":")
      if parts.size > 1
        # Handle cases like registry:port/image:tag
        tag = parts.last
        repository = parts[0..-2].join(":")
      else
        repository = image_name
        tag = Constants::Docker::DEFAULT_IMAGE_TAG
      end
      {repository: repository, tag: tag}
    end

    # Extract just the tag from an image name
    def self.get_tag(image_name : String) : String
      parse(image_name)[:tag]
    end

    # Extract just the repository from an image name
    def self.get_repository(image_name : String) : String
      parse(image_name)[:repository]
    end

    # Check if image has a custom tag (not 'latest')
    def self.has_custom_tag?(image_name : String) : Bool
      get_tag(image_name) != Constants::Docker::DEFAULT_IMAGE_TAG
    end

    # Format image name with tag
    def self.format_with_tag(repository : String, tag : String) : String
      if tag == Constants::Docker::DEFAULT_IMAGE_TAG
        repository
      else
        "#{repository}:#{tag}"
      end
    end

    # Truncate image name for display
    def self.display_name(image_name : String, max_length : Int32 = Constants::Table::MAX_COLUMN_WIDTH) : String
      if image_name.size <= max_length
        return image_name
      end

      if image_name.includes?(':')
        parts = image_name.split(':')
        tag = parts.last
        repo = parts[0..-2].join(":")

        # If tag is short enough, preserve it
        if tag.size < max_length - 10          # give at least 10 chars for repo
          repo_len = max_length - tag.size - 1 # for ':'
          if repo.size > repo_len
            repo = StringDisplayUtils.truncate(repo, repo_len)
          end
          return "#{repo}:#{tag}"
        end
      end

      StringDisplayUtils.truncate(image_name, max_length)
    end

    # Get registry host from image name if present
    def self.get_registry(image_name : String) : String?
      if image_name.includes?("/")
        parts = image_name.split("/")
        # Check if first part contains a dot (likely a registry)
        if parts.size > 1 && parts.first.includes?(".")
          parts.first
        end
      end
      nil
    end

    # Check if image is from a specific registry
    def self.from_registry?(image_name : String, registry : String) : Bool
      image_registry = get_registry(image_name)
      image_registry == registry
    end
  end
end
