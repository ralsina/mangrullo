require "docr"
require "./types"
require "./error_handling"

module Mangrullo
  # Custom Docker client that supports configurable socket paths
  class CustomDockerClient < Docr::Client
    def initialize(socket_path : String = "/var/run/docker.sock")
      socket = UNIXSocket.new(socket_path)
      @client = HTTP::Client.new(socket)
    end
  end

  class DockerClient
    @api : Docr::API

    def initialize(socket_path : String = "/var/run/docker.sock")
      client = CustomDockerClient.new(socket_path)
      @api = Docr::API.new(client)
    end

    def list_containers(all : Bool = false, filters : Hash(String, Array(String)) = {} of String => Array(String)) : Array(ContainerInfo)
      containers = @api.containers.list(all: all)

      containers.map do |container|
        # Defensive handling of container names
        container_name = if container.names && !container.names.empty?
                           container.names.first
                         else
                           # Fallback to first 12 chars of container ID, or full ID if shorter
                           container_id = container.id
                           if container_id.size > 12
                             container_id[0..12]
                           else
                             container_id
                           end
                         end

        ContainerInfo.new(
          id: container.id,
          name: container_name,
          image: container.image,
          image_id: container.image_id,
          labels: container.labels || {} of String => String,
          status: container.status || "unknown",
          created: Time.unix(container.created)
        )
      end
    end

    def get_container_info(container_id : String) : ContainerInfo?
      begin
        containers = @api.containers.list(all: true, filters: {"id" => [container_id]})
        return nil if containers.empty?

        container = containers.first

        # Defensive handling of container names
        container_name = if container.names && !container.names.empty?
                           container.names.first
                         else
                           # Fallback to first 12 chars of container ID, or full ID if shorter
                           container_id = container.id
                           if container_id.size > 12
                             container_id[0..12]
                           else
                             container_id
                           end
                         end

        ContainerInfo.new(
          id: container.id,
          name: container_name,
          image: container.image,
          image_id: container.image_id,
          labels: container.labels || {} of String => String,
          status: container.status || "unknown",
          created: Time.unix(container.created)
        )
      rescue ex : Docr::Errors::DockerAPIError
        Log.error { "Docker API error getting container info: #{ex.message}" }
        nil
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error getting container info: #{ex.message}" }
        nil
      rescue ex
        Log.error { "Unexpected error getting container info: #{ex.message}" }
        nil
      end
    end

    def get_image_info(image_name : String) : ImageInfo?
      begin
        images = @api.images.list(filters: {"reference" => [image_name]})
        return nil if images.empty?

        image = images.first
        ImageInfo.new(
          id: image.id,
          repo_tags: image.repo_tags || [] of String,
          created: Time.unix(image.created),
          size: image.size.to_u64,
          labels: image.labels || {} of String => String
        )
      rescue ex : Docr::Errors::DockerAPIError
        Log.error { "Docker API error getting image info: #{ex.message}" }
        nil
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error getting image info: #{ex.message}" }
        nil
      rescue ex
        Log.error { "Unexpected error getting image info: #{ex.message}" }
        nil
      end
    end

    def pull_image(image_name : String, tag : String = "latest") : Bool
      begin
        @api.images.create("#{image_name}:#{tag}")
        true
      rescue ex : Docr::Errors::DockerAPIError
        Log.error { "Docker API error pulling image: #{ex.message}" }
        false
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error pulling image: #{ex.message}" }
        false
      rescue ex
        Log.error { "Unexpected error pulling image: #{ex.message}" }
        false
      end
    end

    def restart_container(container_id : String) : Bool
      begin
        @api.containers.restart(container_id)
        true
      rescue ex : Docr::Errors::DockerAPIError
        Log.error { "Docker API error restarting container: #{ex.message}" }
        false
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error restarting container: #{ex.message}" }
        false
      rescue ex
        Log.error { "Unexpected error restarting container: #{ex.message}" }
        false
      end
    end

    def get_container_logs(container_id : String, tail : Int32 = 100) : String
      begin
        @api.containers.logs(container_id, tail: tail.to_s).gets_to_end
      rescue ex : Docr::Errors::DockerAPIError
        Log.error { "Docker API error getting container logs: #{ex.message}" }
        ""
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error getting container logs: #{ex.message}" }
        ""
      rescue ex
        Log.error { "Unexpected error getting container logs: #{ex.message}" }
        ""
      end
    end

    def inspect_container(container_id : String) : String?
      begin
        @api.containers.inspect(container_id)
      rescue ex : Docr::Errors::DockerAPIError
        Log.error { "Docker API error inspecting container: #{ex.message}" }
        nil
      rescue ex : Socket::Error | IO::Error
        Log.error { "Network error inspecting container: #{ex.message}" }
        nil
      rescue ex
        Log.error { "Unexpected error inspecting container: #{ex.message}" }
        nil
      end
    end

    def running_containers : Array(ContainerInfo)
      list_containers(all: false, filters: {"status" => ["running"]})
    end

    def container_exists?(container_id : String) : Bool
      !get_container_info(container_id).nil?
    end

    def image_exists?(image_name : String) : Bool
      !get_image_info(image_name).nil?
    end
  end
end
