require "./spec_helper"

describe Mangrullo::UpdateManager do
end

# Mock Docker client for testing
class MockDockerClient < Mangrullo::DockerClient
  def initialize
    # Initialize with default socket but we won't actually call Docker
    super("/var/run/docker.sock")
  end
end

# Test wrapper class to expose private methods
class TestableUpdateManager < Mangrullo::UpdateManager
  def initialize
    docker_client = MockDockerClient.new
    super(docker_client, "info")
  end

  def expose_truncate_image_name(image : String) : String
    truncate_image_name(image)
  end

  def expose_truncate_string(str : String, max_length : Int) : String
    truncate_string(str, max_length)
  end
end

describe "UpdateManager private methods" do
  describe "#truncate_image_name" do
    it "truncates SHA256 digests" do
      manager = TestableUpdateManager.new

      # Test full SHA256 digest
      image = "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
      result = manager.expose_truncate_image_name(image)
      result.starts_with?("sha256:").should be_true
      result.ends_with?("...").should be_true
      result.size.should be <= 50

      # Test shorter digest
      image = "sha256:1234567890"
      result = manager.expose_truncate_image_name(image)
      result.should eq("sha256:1234567890")
    end

    it "truncates long image names" do
      manager = TestableUpdateManager.new

      # Test long image name
      image = "very.long.registry.example.com/very/long/repository/path:latest"
      result = manager.expose_truncate_image_name(image)
      result.size.should be <= 50
      result.should end_with(":latest")
    end

    it "preserves short image names" do
      manager = TestableUpdateManager.new

      image = "nginx:latest"
      result = manager.expose_truncate_image_name(image)
      result.should eq(image)
    end
  end

  describe "#truncate_string" do
    it "truncates strings longer than max length" do
      manager = TestableUpdateManager.new

      result = manager.expose_truncate_string("This is a very long string", 10)
      result.should eq("This is...")
      result.size.should eq(10)
    end

    it "preserves strings shorter than max length" do
      manager = TestableUpdateManager.new

      original = "Short"
      result = manager.expose_truncate_string(original, 10)
      result.should eq(original)
    end

    it "handles empty strings" do
      manager = TestableUpdateManager.new

      result = manager.expose_truncate_string("", 10)
      result.should eq("")
    end
  end
end
