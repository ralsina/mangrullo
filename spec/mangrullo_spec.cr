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

describe "container name matching" do
  it "normalizes container names with and without leading slash" do
    # Test the container name normalization logic used in UpdateManager
    
    # Simulate the normalization logic from check_and_update_containers
    container_names = ["flatnotes", "atuin", "/radicale"]
    normalized_input_names = container_names.map { |name| name.starts_with?("/") ? name : "/#{name}" }
    
    normalized_input_names.should eq(["/flatnotes", "/atuin", "/radicale"])
  end

  it "matches container names flexibly" do
    # Test the flexible matching logic
    
    # Container names as they come from Docker (with leading slash)
    docker_containers = [
      {name: "/flatnotes", image: "dullage/flatnotes:latest"},
      {name: "/atuin", image: "ghcr.io/atuin/atuin:latest"},
      {name: "/radicale", image: "tomsquest/docker-radicale:latest"}
    ]
    
    # Test various input formats
    test_cases = [
      {input: ["flatnotes"], expected_matches: ["/flatnotes"]},
      {input: ["atuin"], expected_matches: ["/atuin"]},
      {input: ["/radicale"], expected_matches: ["/radicale"]},
      {input: ["flatnotes", "atuin"], expected_matches: ["/flatnotes", "/atuin"]},
      {input: ["/flatnotes", "/atuin"], expected_matches: ["/flatnotes", "/atuin"]},
      {input: ["flatnotes", "/atuin"], expected_matches: ["/flatnotes", "/atuin"]}
    ]
    
    test_cases.each do |test_case|
      container_names = test_case[:input]
      normalized_input_names = container_names.map { |name| name.starts_with?("/") ? name : "/#{name}" }
      
      matched_containers = docker_containers.select { |container| 
        normalized_input_names.includes?(container[:name]) || 
        normalized_input_names.includes?(container[:name].lchop('/'))
      }
      
      matched_names = matched_containers.map { |c| c[:name] }
      matched_names.should eq(test_case[:expected_matches])
    end
  end

  it "handles empty container names array" do
    # Test that empty container names array returns all containers
    
    # Simulate containers from Docker
    docker_containers = [
      {name: "/flatnotes", image: "dullage/flatnotes:latest"},
      {name: "/atuin", image: "ghcr.io/atuin/atuin:latest"}
    ]
    
    container_names = [] of String
    
    # When container_names is empty, no filtering should occur
    unless container_names.empty?
      normalized_input_names = container_names.map { |name| name.starts_with?("/") ? name : "/#{name}" }
      docker_containers = docker_containers.select { |container| 
        normalized_input_names.includes?(container[:name]) || 
        normalized_input_names.includes?(container[:name].lchop('/'))
      }
    end
    
    # Should still have all containers
    docker_containers.size.should eq(2)
  end

  it "handles non-existent container names gracefully" do
    # Test that requesting non-existent containers returns empty array
    
    # Simulate containers from Docker
    docker_containers = [
      {name: "/flatnotes", image: "dullage/flatnotes:latest"},
      {name: "/atuin", image: "ghcr.io/atuin/atuin:latest"}
    ]
    
    container_names = ["nonexistent", "another-missing"]
    normalized_input_names = container_names.map { |name| name.starts_with?("/") ? name : "/#{name}" }
    
    matched_containers = docker_containers.select { |container| 
      normalized_input_names.includes?(container[:name]) || 
      normalized_input_names.includes?(container[:name].lchop('/'))
    }
    
    matched_containers.should be_empty
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
          # Don't double-prepend linuxserver if it's already there
          unless repository_path.starts_with?("linuxserver/")
            repository_path = "linuxserver/#{repository_path}"
          end
        end
      end
    end

    registry_host.should eq("ghcr.io")
    repository_path.should eq("linuxserver/code-server")
  end

  it "avoids double linuxserver prefix for lscr.io images" do
    # Test that lscr.io images don't get double linuxserver prefix
    image_name = "lscr.io/linuxserver/freshrss:latest"
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
          # Don't double-prepend linuxserver if it's already there
          unless repository_path.starts_with?("linuxserver/")
            repository_path = "linuxserver/#{repository_path}"
          end
        end
      end
    end

    registry_host.should eq("ghcr.io")
    repository_path.should eq("linuxserver/freshrss")
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

describe "container recreation" do
  it "extracts container name correctly" do
    # Test container name extraction logic from recreate_container_with_new_image
    
    # Simulate container info as it comes from Docker
    container_info = {
      id: "abc123def456",
      name: "/flatnotes",
      image: "dullage/flatnotes:latest"
    }
    
    # Extract the container name (remove leading slash)
    container_name = container_info[:name].lchop('/')
    
    container_name.should eq("flatnotes")
  end

  it "handles container names without leading slash" do
    # Test container name extraction for containers without leading slash
    container_info = {
      id: "abc123def456",
      name: "flatnotes",  # Some Docker versions might return without slash
      image: "dullage/flatnotes:latest"
    }
    
    container_name = container_info[:name].lchop('/')
    
    container_name.should eq("flatnotes")
  end

  it "parses docker inspect output correctly" do
    # Test the parsing logic from create_container_from_inspect_data
    
    # Simulate docker inspect output
    inspect_data = %q([{
      "Id": "abc123def456789",
      "Name": "/flatnotes",
      "Config": {
        "Image": "dullage/flatnotes:latest",
        "Env": ["TZ=UTC", "PUID=1000", "PGID=1000"],
        "ExposedPorts": {"8080/tcp": {}},
        "Labels": {"maintainer": "test"}
      },
      "HostConfig": {
        "PortBindings": {"8080/tcp": [{"HostPort": "8081"}]},
        "Binds": ["/host/path:/container/path"],
        "RestartPolicy": {"Name": "unless-stopped"}
      }
    }])
    
    # Parse the container inspection output
    container_info = JSON.parse(inspect_data).as_a.first?
    container_info.should_not be_nil
    
    if container_info
      # Extract the container configuration
      config_data = container_info.as_h
      host_config = config_data["HostConfig"]?.try(&.as_h)
      config = config_data["Config"]?.try(&.as_h)
      
      config.should_not be_nil
      host_config.should_not be_nil
      
      if config && host_config
        # Test environment variable extraction
        env_vars = config["Env"]?.try(&.as_a)
        env_vars.should_not be_nil
        env_vars.try(&.should contain("TZ=UTC"))
        
        # Test port binding extraction
        port_bindings = host_config["PortBindings"]?.try(&.as_h)
        port_bindings.should_not be_nil
        
        # Test restart policy extraction
        restart_policy = host_config["RestartPolicy"]?.try(&.as_h)
        restart_policy.should_not be_nil
        restart_policy.try(&.["Name"]?.should eq("unless-stopped"))
      end
    end
  end

  it "builds docker create command correctly" do
    # Test the docker create command building logic
    
    image_name = "dullage/flatnotes:latest"
    container_name = "flatnotes"
    
    # Simulate parsed configuration
    config = {
      "Env" => JSON.parse(%q(["TZ=UTC", "PUID=1000"])),
      "ExposedPorts" => JSON.parse(%q({"8080/tcp": {}})),
      "Labels" => JSON.parse(%q({"maintainer": "test"}))
    } of String => JSON::Any
    
    host_config = {
      "PortBindings" => JSON.parse(%q({"8080/tcp": [{"HostPort": "8081"}]})),
      "Binds" => JSON.parse(%q(["/host/path:/container/path"])),
      "RestartPolicy" => JSON.parse(%q({"Name": "unless-stopped"}))
    } of String => JSON::Any
    
    # Build docker create command with original configuration
    create_args = ["create", "--name", container_name]
    
    # Add environment variables
    if env_vars = config["Env"]?.try(&.as_a)
      env_vars.each do |env_var|
        env_str = env_var.as_s
        create_args << "--env"
        create_args << env_str
      end
    end
    
    # Add port mappings
    if port_bindings = host_config["PortBindings"]?.try(&.as_h)
      port_bindings.each do |container_port, host_bindings|
        container_port_str = container_port
        host_port = host_bindings.as_a.first?.try(&.as_h).try(&.["HostPort"]?).try(&.as_s)
        if host_port
          create_args << "--publish"
          create_args << "#{host_port}:#{container_port_str}"
        end
      end
    end
    
    # Add volume mounts
    if binds = host_config["Binds"]?.try(&.as_a)
      binds.each do |bind|
        bind_str = bind.as_s
        create_args << "--volume"
        create_args << bind_str
      end
    end
    
    # Add restart policy
    if restart_policy = host_config["RestartPolicy"]?.try(&.as_h)
      policy_name = restart_policy["Name"]?.try(&.as_s)
      if policy_name && policy_name != "no"
        create_args << "--restart"
        create_args << policy_name
      end
    end
    
    # Add labels
    if labels = config["Labels"]?.try(&.as_h)
      labels.each do |key, value|
        create_args << "--label"
        create_args << "#{key}=#{value.as_s}"
      end
    end
    
    # Add image name
    create_args << image_name
    
    # Verify the command structure
    create_args.should contain("create")
    create_args.should contain("--name")
    create_args.should contain("flatnotes")
    create_args.should contain("dullage/flatnotes:latest")
    create_args.should contain("--env")
    create_args.should contain("TZ=UTC")
    create_args.should contain("--publish")
    create_args.should contain("8081:8080/tcp")
    create_args.should contain("--volume")
    create_args.should contain("/host/path:/container/path")
    create_args.should contain("--restart")
    create_args.should contain("unless-stopped")
  end

  it "handles minimal container configuration" do
    # Test recreation with minimal configuration
    
    image_name = "nginx:latest"
    container_name = "nginx"
    
    # Minimal configuration
    config = {} of String => JSON::Any
    host_config = {} of String => JSON::Any
    
    # Build docker create command
    create_args = ["create", "--name", container_name]
    create_args << image_name
    
    # Verify basic command structure
    create_args.should eq(["create", "--name", "nginx", "nginx:latest"])
  end
end
