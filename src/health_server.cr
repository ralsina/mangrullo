require "http/server"
require "json"
require "./constants"

module Mangrullo
  # Liveness signals gathered by the daemon and exposed by HealthServer.
  #
  # The update loop records every completed cycle here, so the health
  # endpoint can report whether the daemon is making progress and not
  # merely that the process is alive.
  class HealthState
    getter started_at : Time
    getter last_successful_check : Time?
    getter last_error : NamedTuple(at: Time, message: String)?

    def initialize(@started_at : Time = Time.utc)
    end

    def record_success(at : Time = Time.utc) : Nil
      @last_successful_check = at
      @last_error = nil
    end

    def record_error(message : String, at : Time = Time.utc) : Nil
      @last_error = {at: at, message: message}
    end

    # The daemon counts as degraded when no update cycle has succeeded
    # within twice the check interval, or when no cycle ever succeeded
    # and that same grace period has elapsed since startup.
    def degraded?(interval_seconds : Int32, now : Time = Time.utc) : Bool
      threshold = (2 * interval_seconds).seconds

      if success = last_successful_check
        now - success > threshold
      else
        now - started_at > threshold
      end
    end
  end

  # Minimal HTTP endpoint exposing daemon liveness for Docker health
  # checks. Uses the standard library server so the daemon binary does
  # not need the web stack.
  class HealthServer
    def initialize(@state : HealthState, @interval_seconds : Int32, @port : Int32,
                   @host : String = Mangrullo::Constants::Web::DEFAULT_HOST)
      @server = HTTP::Server.new do |context|
        handle_request(context)
      end
    end

    # Binds synchronously so callers (and tests) learn the actual port,
    # then accepts connections in a background fiber.
    def start : Socket::IPAddress
      address = @server.bind_tcp(@host, @port)
      Log.info { "Health endpoint listening on http://#{address.address}:#{address.port}" }

      spawn do
        @server.listen
      rescue ex
        Log.error { "Health endpoint stopped: #{ex.message}" }
      end

      address
    end

    private def handle_request(context : HTTP::Server::Context) : Nil
      if context.request.method == "GET" && context.request.path == "/health"
        respond_with_health(context)
      else
        context.response.status_code = Mangrullo::Constants::HTTP::STATUS_NOT_FOUND
        context.response.content_type = Mangrullo::Constants::HTTP::TEXT_CONTENT_TYPE
        context.response.print("Not Found")
      end
    end

    private def respond_with_health(context : HTTP::Server::Context) : Nil
      status = @state.degraded?(@interval_seconds) ? "degraded" : "ok"
      context.response.status_code = status == "ok" ? 200 : 503
      context.response.content_type = Mangrullo::Constants::HTTP::JSON_CONTENT_TYPE
      context.response.print(health_json(status))
    end

    private def health_json(status : String) : String
      JSON.build do |json|
        json.object do
          json.field("status", status)
          json.field("uptime_seconds", (Time.utc - @state.started_at).total_seconds.to_i)
          json.field("interval_seconds", @interval_seconds)
          write_check_fields(json)
          write_error_fields(json)
        end
      end
    end

    private def write_check_fields(json : JSON::Builder) : Nil
      if success = @state.last_successful_check
        json.field("last_successful_check", success.to_rfc3339)
        json.field("seconds_since_successful_check", (Time.utc - success).total_seconds.to_i)
      else
        json.field("last_successful_check", nil)
        json.field("seconds_since_successful_check", nil)
      end
    end

    private def write_error_fields(json : JSON::Builder) : Nil
      if error = @state.last_error
        json.field("last_error", "#{error[:at].to_rfc3339}: #{error[:message]}")
      else
        json.field("last_error", nil)
      end
    end
  end
end
