require "http/server"
require "json"

module Mangrullo
  # Server-Sent Events for real-time progress updates
  class SSE
    include HTTP::Handler

    # Event types
    enum EventType
      ImagePullStart
      ImagePullProgress
      ImagePullComplete
      ContainerStop
      ContainerRemove
      ContainerCreate
      ContainerStart
      UpdateComplete
      UpdateError
      StatusUpdate
    end

    # Event data structure
    class Event
      property type : EventType
      property container_id : String
      property container_name : String
      property message : String
      property data : Hash(String, Int32 | Bool | String)

      def initialize(@type : EventType, @container_id : String, @container_name : String, @message : String, @data : Hash(String, Int32 | Bool | String) = {} of String => Int32 | Bool | String)
      end

      # Convert event to JSON string for SSE
      def to_sse_json : String
        {
          "type":           @type.to_s,
          "container_id":   @container_id,
          "container_name": @container_name,
          "message":        @message,
          "data":           @data,
        }.to_json
      end
    end

    # Active SSE connections
    @@clients = Hash(String, IO::Memory).new
    @@client_mutex = Mutex.new

    # Register a new SSE client
    def self.register_client(client_id : String, io : IO::Memory)
      @@client_mutex.synchronize do
        @@clients[client_id] = io
      end
    end

    # Unregister an SSE client
    def self.unregister_client(client_id : String)
      @@client_mutex.synchronize do
        @@clients.delete(client_id)
      end
    end

    # Broadcast an event to all connected clients
    def self.broadcast(event : Event)
      @@client_mutex.synchronize do
        @@clients.each do |client_id, io|
          begin
            send_event(io, event)
          rescue ex : IO::Error
            # Client disconnected, remove them
            @@clients.delete(client_id)
          end
        end
      end
    end

    # Send an event to a specific client
    def self.send_to_client(client_id : String, event : Event)
      @@client_mutex.synchronize do
        if io = @@clients[client_id]?
          begin
            send_event(io, event)
          rescue ex : IO::Error
            @@clients.delete(client_id)
          end
        end
      end
    end

    # Get active client count
    def self.client_count : Int32
      @@client_mutex.synchronize do
        @@clients.size
      end
    end

    # Format and send an SSE event
    private def self.send_event(io : IO, event : Event)
      io << "event: #{event.type.to_s.underscore}\n"
      io << "data: #{event.to_sse_json}\n"
      io << "\n"
      io.flush
    end

    # Call next handler in chain
    def call(context)
      call_next(context)
    end
  end
end
