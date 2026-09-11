require "json"
require "base64"
require "log"

module Mangrullo
  # Reads registry credentials from a docker config.json (usually
  # ~/.docker/config.json), so private images and authenticated Docker Hub
  # pulls work instead of failing with 401 / anonymous rate limits.
  #
  # Only inline "auth" entries (base64 "user:password") are supported;
  # credentials delegated to a credsStore helper binary cannot be read
  # without invoking that helper.
  module DockerConfigAuth
    alias Record = NamedTuple(user: String, password: String)

    # Find credentials for a registry host in a docker config file
    def self.credentials_for(registry_host : String, config_path : String) : Record?
      return unless File.file?(config_path)

      begin
        config = JSON.parse(File.read(config_path))
      rescue ex : JSON::ParseException
        Log.warn { "Docker config #{config_path} is not valid JSON: #{ex.message}" }
        return
      end

      auths = config["auths"]?.try(&.as_h?)
      return unless auths

      target = normalize_host(registry_host)
      auths.each do |key, entry|
        next unless normalize_host(key) == target

        auth = entry.as_h?.try(&.["auth"]?.try(&.as_s))
        next unless auth

        decoded = begin
          Base64.decode_string(auth)
        rescue Base64::Error
          Log.warn { "Skipping malformed auth entry for #{key} in #{config_path}" }
          next
        end

        user, _, password = decoded.partition(":")
        return {user: user, password: password}
      end

      nil
    end

    # Path to the current user's docker config, honoring DOCKER_CONFIG
    def self.default_config_path : String
      base = ENV["DOCKER_CONFIG"]? || File.expand_path("~/.docker")
      File.join(base, "config.json")
    end

    # Normalize the many ways a registry is spelled in config.json
    # ("https://index.docker.io/v1/", "ghcr.io/", …) down to a bare host,
    # mapping docker hub aliases onto one name.
    def self.normalize_host(key : String) : String
      host = key.strip.downcase
      host = host.sub(%r{^https?://}, "")
      host = host.split('/').first
      host = "docker.io" if host == "index.docker.io" || host == "registry-1.docker.io"
      host
    end
  end
end
