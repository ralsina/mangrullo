require "json"
require "http/client"
require "./spec_helper"
require "../src/health_server"

describe Mangrullo::HealthState do
  it "starts with no successful check and no errors" do
    state = Mangrullo::HealthState.new

    state.last_successful_check.should be_nil
    state.last_error.should be_nil
  end

  it "is healthy before the grace period elapses" do
    state = Mangrullo::HealthState.new(started_at: Time.utc - 5.seconds)

    state.degraded?(300).should be_false
  end

  it "is degraded when no cycle ever succeeded after the grace period" do
    state = Mangrullo::HealthState.new(started_at: Time.utc - 601.seconds)

    state.degraded?(300).should be_true
  end

  it "is healthy right after a successful cycle" do
    state = Mangrullo::HealthState.new(started_at: Time.utc - 400.seconds)
    state.record_success

    state.degraded?(300).should be_false
    state.last_successful_check.should_not be_nil
  end

  it "is degraded when the last successful cycle is older than twice the interval" do
    state = Mangrullo::HealthState.new(started_at: Time.utc - 1000.seconds)
    state.record_success(at: Time.utc - 700.seconds)

    state.degraded?(300).should be_true
  end

  it "clears the last error after a successful cycle" do
    state = Mangrullo::HealthState.new
    state.record_error("docker socket unreachable")
    state.record_success

    state.last_error.should be_nil
  end

  it "keeps the message of the last error" do
    state = Mangrullo::HealthState.new
    state.record_error("docker socket unreachable")

    if last_error = state.last_error
      last_error[:message].should eq("docker socket unreachable")
    else
      fail("expected last_error to be set")
    end
  end
end

private def start_health_server(state : Mangrullo::HealthState, interval_seconds : Int32) : Socket::IPAddress
  server = Mangrullo::HealthServer.new(state, interval_seconds, 0, host: "127.0.0.1")
  server.start
end

describe Mangrullo::HealthServer do
  it "reports ok while the daemon is current" do
    state = Mangrullo::HealthState.new
    state.record_success
    address = start_health_server(state, 300)

    response = HTTP::Client.get("http://127.0.0.1:#{address.port}/health")

    response.status_code.should eq(200)
    body = JSON.parse(response.body)
    body["status"].as_s.should eq("ok")
    body["interval_seconds"].as_i.should eq(300)
    body["last_successful_check"].as_s.should_not be_empty
    body["seconds_since_successful_check"].as_i.should be >= 0
    body["last_error"].raw.should be_nil
  end

  it "reports degraded with a 503 when no cycle succeeded within twice the interval" do
    state = Mangrullo::HealthState.new(started_at: Time.utc - 30.seconds)
    state.record_success(at: Time.utc - 30.seconds)
    address = start_health_server(state, 1)

    response = HTTP::Client.get("http://127.0.0.1:#{address.port}/health")

    response.status_code.should eq(503)
    body = JSON.parse(response.body)
    body["status"].as_s.should eq("degraded")
  end

  it "reports ok during the startup grace period before the first cycle" do
    state = Mangrullo::HealthState.new(started_at: Time.utc - 1.second)
    address = start_health_server(state, 300)

    response = HTTP::Client.get("http://127.0.0.1:#{address.port}/health")

    response.status_code.should eq(200)
    body = JSON.parse(response.body)
    body["status"].as_s.should eq("ok")
    body["last_successful_check"].raw.should be_nil
    body["last_error"].raw.should be_nil
  end

  it "returns 404 for unknown paths" do
    address = start_health_server(Mangrullo::HealthState.new, 300)

    response = HTTP::Client.get("http://127.0.0.1:#{address.port}/nope")

    response.status_code.should eq(404)
  end
end
