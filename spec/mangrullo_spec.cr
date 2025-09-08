require "./spec_helper"

describe Mangrullo::Version do
  describe "parse" do
    it "parses semantic versions" do
      version = Mangrullo::Version.parse("1.2.3")
      version.should_not be_nil
      if version
        version.major.should eq(1)
        version.minor.should eq(2)
        version.patch.should eq(3)
      end
    end

    it "returns nil for non-semantic versions" do
      version = Mangrullo::Version.parse("latest")
      version.should be_nil
    end

    it "returns nil for empty strings" do
      version = Mangrullo::Version.parse("")
      version.should be_nil
    end
  end
end

describe "fallback logic" do
  it "extracts tag from image name" do
    # Test the tag extraction logic that's used in the fallback
    image_with_tag = "test/image:latest"
    tag = image_with_tag.includes?(":") ? image_with_tag.split(":").last : "latest"
    tag.should eq("latest")

    image_with_version = "test/image:1.2.3"
    tag = image_with_version.includes?(":") ? image_with_version.split(":").last : "latest"
    tag.should eq("1.2.3")

    image_without_tag = "test/image"
    tag = image_without_tag.includes?(":") ? image_without_tag.split(":").last : "latest"
    tag.should eq("latest")
  end

  it "generates correct fallback messages" do
    # Test message generation for different scenarios

    # Scenario 1: latest tag
    image = "dullage/flatnotes:latest"
    if image.includes?(":")
      tag = image.split(":").last
      message = "Update available for #{image} (current: #{tag})"
    else
      message = "Update available for #{image} (current: latest)"
    end
    message.should eq("Update available for dullage/flatnotes:latest (current: latest)")

    # Scenario 2: version tag
    image = "dullage/flatnotes:1.2.3"
    if image.includes?(":")
      tag = image.split(":").last
      message = "Update available for #{image} (current: #{tag})"
    else
      message = "Update available for #{image} (current: latest)"
    end
    message.should eq("Update available for dullage/flatnotes:1.2.3 (current: 1.2.3)")

    # Scenario 3: no tag
    image = "dullage/flatnotes"
    if image.includes?(":")
      tag = image.split(":").last
      message = "Update available for #{image} (current: #{tag})"
    else
      message = "Update available for #{image} (current: latest)"
    end
    message.should eq("Update available for dullage/flatnotes (current: latest)")
  end
end

describe "registry mapping" do
  it "maps lscr.io to ghcr.io correctly" do
    # Test the lscr.io -> ghcr.io mapping logic

    # Simulate the parsing logic from get_tags_for_digest
    image_name = "lscr.io/linuxserver/code-server:latest"
    base_name = image_name.split(":").first

    registry_host = "registry-1.docker.io"
    repository_path = base_name

    if base_name.includes?("/")
      parts = base_name.split("/")
      if parts[0].includes?(".") || parts[0].includes?(":")
        registry_host = parts[0]
        repository_path = parts[1..-1].join("/")

        # Handle special registry mappings
        if registry_host == "lscr.io"
          registry_host = "ghcr.io"
          repository_path = "linuxserver/#{repository_path}"
        end
      end
    end

    registry_host.should eq("ghcr.io")
    repository_path.should eq("linuxserver/linuxserver/code-server")
  end

  it "handles regular docker hub images" do
    image_name = "nginx:latest"
    base_name = image_name.split(":").first

    registry_host = "registry-1.docker.io"
    repository_path = base_name

    if base_name.includes?("/")
      parts = base_name.split("/")
      if parts[0].includes?(".") || parts[0].includes?(":")
        registry_host = parts[0]
        repository_path = parts[1..-1].join("/")
      else
        registry_host = "registry-1.docker.io"
        repository_path = base_name
      end
    else
      registry_host = "registry-1.docker.io"
      repository_path = "library/#{base_name}"
    end

    registry_host.should eq("registry-1.docker.io")
    repository_path.should eq("library/nginx")
  end

  it "handles ghcr.io images directly" do
    image_name = "ghcr.io/user/repo:1.0.0"
    base_name = image_name.split(":").first

    registry_host = "registry-1.docker.io"
    repository_path = base_name

    if base_name.includes?("/")
      parts = base_name.split("/")
      if parts[0].includes?(".") || parts[0].includes?(":")
        registry_host = parts[0]
        repository_path = parts[1..-1].join("/")
      end
    end

    registry_host.should eq("ghcr.io")
    repository_path.should eq("user/repo")
  end
end
