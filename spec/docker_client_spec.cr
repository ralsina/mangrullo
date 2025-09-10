require "./spec_helper"

describe Mangrullo::DockerClient do
end

# Test a wrapper class to expose private methods for testing
class TestableDockerClient < Mangrullo::DockerClient
  def expose_normalize_container_name(container)
    normalize_container_name(container)
  end
end

describe "DockerClient private methods" do
  describe "#normalize_container_name" do
    it "extracts name from container names array" do
      client = TestableDockerClient.new

      # Mock container object with names
      container = MockContainer.new
      container.names = ["/test-container", "/container-alias"]

      result = client.expose_normalize_container_name(container)
      result.should eq("/test-container")
    end

    it "uses container name when names array is empty" do
      client = TestableDockerClient.new

      container = MockContainer.new
      container.names = [] of String
      container.name = "/container-name"

      result = client.expose_normalize_container_name(container)
      result.should eq("/container-name")
    end

    it "truncates long container IDs as fallback" do
      client = TestableDockerClient.new

      container = MockContainer.new
      container.names = [] of String
      container.name = ""
      container.id = "abcd1234567890abcd1234567890abcd12345678"

      result = client.expose_normalize_container_name(container)
      result.should eq("abcd123456789")
    end

    it "returns short container IDs as-is" do
      client = TestableDockerClient.new

      container = MockContainer.new
      container.names = [] of String
      container.name = ""
      container.id = "short123"

      result = client.expose_normalize_container_name(container)
      result.should eq("short123")
    end
  end
end

# Mock container class for testing
class MockContainer
  property id : String
  property names : Array(String)
  property name : String

  def initialize(@id = "test123", @names = [] of String, @name = "")
  end
end
