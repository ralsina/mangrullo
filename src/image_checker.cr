require "http"
require "json"
require "./types"
require "./docker_client"

module Mangrullo
  class ImageChecker
    @docker_client : DockerClient
    @registry_client : HTTP::Client

    def initialize(@docker_client : DockerClient)
      @registry_client = HTTP::Client.new("registry-1.docker.io", 443, tls: true)
    end

    def needs_update?(container : ContainerInfo, allow_major_upgrade : Bool = false) : Bool
      # If using 'latest' tag, always check for updates
      return true if container.image.includes?("latest")

      current_version = extract_version_from_image(container.image)
      return false unless current_version

      remote_version = get_latest_version(container.image)
      return false unless remote_version

      # Check if update is needed based on version
      if allow_major_upgrade
        remote_version > current_version
      else
        # Only update if not a major version upgrade
        remote_version > current_version && !current_version.major_upgrade?(remote_version)
      end
    end

    def extract_version_from_image(image_name : String) : Version?
      # Skip SHA256 digests (they are image IDs, not versioned images)
      return nil if image_name.starts_with?("sha256:")

      # Extract tag from image name (format: name:tag or name)
      parts = image_name.split(":")
      tag = parts.size > 1 ? parts.last : "latest"

      Version.parse(tag)
    end

    def get_latest_version(image_name : String) : Version?
      # Skip SHA256 digests (they are image IDs, not versioned images)
      return nil if image_name.starts_with?("sha256:")

      # Remove tag from image name
      base_name = image_name.split(":").first

      # Remove registry prefix if present
      base_name = base_name.split("/").last if base_name.includes?("/")

      # Get image manifest from Docker Hub API
      begin
        response = @registry_client.get("/v2/#{base_name}/tags/list")
        return nil unless response.status_code == 200

        json = JSON.parse(response.body)
        tags = json["tags"].as_a.map(&.as_s)

        # Filter out version tags and find the latest
        versions = tags.compact_map { |tag| Version.parse(tag) }.sort!
        versions.last?
      rescue
        nil
      end
    end

    def get_remote_image_digest(image_name : String) : String?
      # Skip SHA256 digests (they are image IDs, not versioned images)
      return nil if image_name.starts_with?("sha256:")

      # Remove tag from image name
      base_name = image_name.split(":").first
      tag = image_name.includes?(":") ? image_name.split(":").last : "latest"

      # Remove registry prefix if present
      base_name = base_name.split("/").last if base_name.includes?("/")

      begin
        # Get image manifest to get digest
        response = @registry_client.get("/v2/#{base_name}/manifests/#{tag}",
          HTTP::Headers{
            "Accept" => "application/vnd.docker.distribution.manifest.v2+json",
          })

        return nil unless response.status_code == 200

        # The digest is in the Docker-Content-Digest header
        response.headers["Docker-Content-Digest"]?
      rescue
        nil
      end
    end

    def get_local_image_digest(image_name : String) : String?
      image_info = @docker_client.get_image_info(image_name)
      image_info.try(&.id)
    end

    def image_has_update?(image_name : String) : Bool
      local_digest = get_local_image_digest(image_name)
      return false unless local_digest

      remote_digest = get_remote_image_digest(image_name)
      return false unless remote_digest

      local_digest != remote_digest
    end

    def get_image_update_info(image_name : String) : NamedTuple(has_update: Bool, local_version: Version?, remote_version: Version?)
      local_version = extract_version_from_image(image_name)
      remote_version = get_latest_version(image_name)

      has_update = if local_version && remote_version
                     remote_version > local_version
                   else
                     image_has_update?(image_name)
                   end

      {has_update: has_update, local_version: local_version, remote_version: remote_version}
    end
  end
end
