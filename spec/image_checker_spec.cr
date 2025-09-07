require "./spec_helper"
require "../src/types"
require "../src/image_checker"
require "../src/docker_client"

describe Mangrullo::ImageChecker do
  describe "#extract_version_from_image" do
    it "extracts version from simple image names" do
      checker = Mangrullo::ImageChecker.new(MockDockerClient.new)

      version = checker.extract_version_from_image("nginx:1.2.3")
      version.should_not be_nil
      version.should be_a(Mangrullo::Version)
      if version.is_a?(Mangrullo::Version)
        version.major.should eq(1)
        version.minor.should eq(2)
        version.patch.should eq(3)
      end
    end

    it "defaults to latest when no tag is specified" do
      checker = Mangrullo::ImageChecker.new(MockDockerClient.new)

      version = checker.extract_version_from_image("nginx")
      version.should be_nil # "latest" is not a semantic version
    end

    it "handles complex image names with registry" do
      checker = Mangrullo::ImageChecker.new(MockDockerClient.new)

      version = checker.extract_version_from_image("docker.io/library/nginx:1.2.3")
      version.should_not be_nil
      if version.is_a?(Mangrullo::Version)
        version.major.should eq(1)
        version.minor.should eq(2)
        version.patch.should eq(3)
      end
    end

    it "returns nil for SHA256 digests" do
      checker = Mangrullo::ImageChecker.new(MockDockerClient.new)

      version = checker.extract_version_from_image("sha256:8124f5e2ddf9a4985ca653c7bd4bb0132eef4316aaf2975181a5f6a9d0f14ced")
      version.should be_nil
    end

    it "returns nil for invalid version tags" do
      checker = Mangrullo::ImageChecker.new(MockDockerClient.new)

      version = checker.extract_version_from_image("nginx:invalid")
      version.should be_nil
    end
  end

  describe "#needs_update?" do
    it "returns false when no update is needed" do
      mock_client = MockDockerClient.new
      checker = MockImageChecker.new(mock_client)
      container = create_container("nginx:1.2.3")
      # Set available versions - only current version available
      checker.set_all_versions("nginx:1.2.3", [
        Mangrullo::Version.new(1, 2, 3)
      ])

      result = checker.needs_update?(container, false)
      result.should be_false
    end

    it "returns true when update is available" do
      mock_client = MockDockerClient.new
      checker = MockImageChecker.new(mock_client)
      container = create_container("nginx:1.2.3")
      # Set available versions including newer patch version
      checker.set_all_versions("nginx:1.2.3", [
        Mangrullo::Version.new(1, 2, 3),
        Mangrullo::Version.new(1, 2, 4)
      ])

      result = checker.needs_update?(container, false)
      result.should be_true
    end

    it "returns false for major upgrades when not allowed" do
      mock_client = MockDockerClient.new
      checker = MockImageChecker.new(mock_client)
      container = create_container("nginx:1.2.3")
      # Set available versions including major upgrade
      checker.set_all_versions("nginx:1.2.3", [
        Mangrullo::Version.new(1, 2, 3),
        Mangrullo::Version.new(2, 0, 0)
      ])

      result = checker.needs_update?(container, false)
      result.should be_false
    end

    it "returns true for major upgrades when allowed" do
      mock_client = MockDockerClient.new
      checker = MockImageChecker.new(mock_client)
      container = create_container("nginx:1.2.3")
      # Set available versions including major upgrade
      checker.set_all_versions("nginx:1.2.3", [
        Mangrullo::Version.new(1, 2, 3),
        Mangrullo::Version.new(2, 0, 0)
      ])

      result = checker.needs_update?(container, true)
      result.should be_true
    end

    it "returns false for SHA256 digest images" do
      mock_client = MockDockerClient.new
      checker = MockImageChecker.new(mock_client)
      container = create_container("sha256:8124f5e2ddf9a4985ca653c7bd4bb0132eef4316aaf2975181a5f6a9d0f14ced")

      result = checker.needs_update?(container, false)
      result.should be_false
    end

    it "returns true when using latest tag" do
      mock_client = MockDockerClient.new
      checker = MockImageChecker.new(mock_client)
      container = create_container("nginx:latest")
      # Set image digest to simulate update available
      checker.set_image_digest("nginx:latest", "some_digest")

      result = checker.needs_update?(container, false)
      result.should be_true
    end

    it "handles missing remote version gracefully" do
      mock_client = MockDockerClient.new
      checker = MockImageChecker.new(mock_client)
      container = create_container("nginx:1.2.3")
      # Set empty versions list to simulate no remote versions available
      checker.set_all_versions("nginx:1.2.3", [] of Mangrullo::Version)

      result = checker.needs_update?(container, false)
      result.should be_false
    end
  end

  describe "#get_image_update_info" do
    it "returns update info when update is available" do
      mock_client = MockDockerClient.new
      checker = MockImageChecker.new(mock_client)
      create_container("nginx:1.2.3")
      # Set available versions including newer patch version
      checker.set_all_versions("nginx:1.2.3", [
        Mangrullo::Version.new(1, 2, 3),
        Mangrullo::Version.new(1, 2, 4)
      ])

      info = checker.get_image_update_info("nginx:1.2.3")
      info[:has_update].should be_true
      local_version = info[:local_version]
      remote_version = info[:remote_version]
      local_version.should_not be_nil
      remote_version.should_not be_nil
      if local_version.is_a?(Mangrullo::Version)
        local_version.major.should eq(1)
        local_version.minor.should eq(2)
        local_version.patch.should eq(3)
      end
      if remote_version.is_a?(Mangrullo::Version)
        remote_version.major.should eq(1)
        remote_version.minor.should eq(2)
        remote_version.patch.should eq(4)
      end
    end

    it "returns no update when versions are the same" do
      mock_client = MockDockerClient.new
      checker = MockImageChecker.new(mock_client)
      create_container("nginx:1.2.3")
      # Set available versions - only current version available
      checker.set_all_versions("nginx:1.2.3", [
        Mangrullo::Version.new(1, 2, 3)
      ])

      info = checker.get_image_update_info("nginx:1.2.3")
      info[:has_update].should be_false
    end

    it "handles SHA256 digests gracefully" do
      mock_client = MockDockerClient.new
      checker = MockImageChecker.new(mock_client)
      info = checker.get_image_update_info("sha256:8124f5e2ddf9a4985ca653c7bd4bb0132eef4316aaf2975181a5f6a9d0f14ced")
      info[:has_update].should be_false
      info[:local_version].should be_nil
      info[:remote_version].should be_nil
    end
  end
end

# Helper methods
private def create_container(image : String) : Mangrullo::ContainerInfo
  Mangrullo::ContainerInfo.new(
    id: "container_id",
    name: "container_name",
    image: image,
    image_id: "image_id",
    labels: {} of String => String,
    status: "running",
    created: Time.utc
  )
end

# Mock ImageChecker for testing
class MockImageChecker < Mangrullo::ImageChecker
  @remote_versions = Hash(String, Mangrullo::Version?).new
  @all_versions = Hash(String, Array(Mangrullo::Version)).new
  @image_digests = Hash(String, String?).new

  def set_remote_version(image_name : String, version : Mangrullo::Version?)
    @remote_versions[image_name] = version
  end

  def set_all_versions(image_name : String, versions : Array(Mangrullo::Version))
    @all_versions[image_name] = versions
  end

  def set_image_digest(image_name : String, digest : String?)
    @image_digests[image_name] = digest
  end

  def get_latest_version(image_name : String) : Mangrullo::Version?
    @remote_versions[image_name]?
  end

  def get_all_versions(image_name : String) : Array(Mangrullo::Version)
    @all_versions[image_name]? || [] of Mangrullo::Version
  end

  def find_target_update_version(image_name : String, current_version : Mangrullo::Version, allow_major_upgrade : Bool) : Mangrullo::Version?
    all_versions = get_all_versions(image_name)
    return nil if all_versions.empty?

    # Filter versions that are newer than current version
    newer_versions = all_versions.select { |v| v > current_version }

    # Filter by major upgrade preference
    if allow_major_upgrade
      # Allow any newer version
      newer_versions.max?
    else
      # Only allow minor/patch updates within the same major version
      same_major_versions = newer_versions.select { |v| v.major == current_version.major }
      same_major_versions.max?
    end
  end

  def image_has_update?(image_name : String) : Bool
    # Simple mock implementation - return false for tests unless specifically set
    @image_digests[image_name]? != nil
  end

  def get_local_image_digest(image_name : String) : String?
    @image_digests[image_name]?
  end

  def get_remote_image_digest(image_name : String) : String?
    @image_digests[image_name]? ? "different_digest" : nil
  end
end

# Mock DockerClient for testing
class MockDockerClient < Mangrullo::DockerClient
  @remote_versions = Hash(String, Mangrullo::Version?).new

  def set_remote_version(image_name : String, version : Mangrullo::Version?)
    @remote_versions[image_name] = version
  end

  def get_remote_version(image_name : String) : Mangrullo::Version?
    @remote_versions[image_name]?
  end

  def get_image_info(image_name : String) : Mangrullo::ImageInfo?
    Mangrullo::ImageInfo.new(
      id: "image_id",
      repo_tags: [image_name],
      created: Time.utc,
      size: 100_u64,
      labels: {} of String => String
    )
  end

  # Override methods to avoid real Docker calls
  def list_containers(all : Bool = false, filters : Hash(String, Array(String)) = {} of String => Array(String)) : Array(Mangrullo::ContainerInfo)
    [] of Mangrullo::ContainerInfo
  end

  def get_container_info(container_id : String) : Mangrullo::ContainerInfo?
    nil
  end

  def pull_image(image_name : String, tag : String = "latest") : Bool
    true
  end

  def restart_container(container_id : String) : Bool
    true
  end

  def get_container_logs(container_id : String, tail : Int32 = 100) : String
    ""
  end

  def inspect_container(container_id : String) : String?
    nil
  end

  def running_containers : Array(Mangrullo::ContainerInfo)
    [] of Mangrullo::ContainerInfo
  end

  def container_exists?(container_id : String) : Bool
    false
  end

  def image_exists?(image_name : String) : Bool
    true
  end
end
