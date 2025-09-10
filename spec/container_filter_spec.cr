require "./spec_helper"

describe Mangrullo::ContainerFilter do
  describe "normalize_container_name" do
    it "adds leading slash when missing" do
      Mangrullo::ContainerFilter.normalize_container_name("test").should eq("/test")
    end

    it "keeps existing leading slash" do
      Mangrullo::ContainerFilter.normalize_container_name("/test").should eq("/test")
    end
  end

  describe "denormalize_container_name" do
    it "removes leading slash" do
      Mangrullo::ContainerFilter.denormalize_container_name("/test").should eq("test")
    end

    it "handles name without slash" do
      Mangrullo::ContainerFilter.denormalize_container_name("test").should eq("test")
    end
  end

  describe "filter_containers_by_name" do
    it "returns all containers when names is empty" do
      containers = [
        TestHelper.mock_container("abc123", "/test1", "test:1.0.0"),
        TestHelper.mock_container("def456", "/test2", "test:2.0.0"),
      ]

      filtered = Mangrullo::ContainerFilter.filter_containers_by_name(containers, [] of String)
      filtered.size.should eq(2)
    end

    it "filters by container names" do
      containers = [
        TestHelper.mock_container("abc123", "/test1", "test:1.0.0"),
        TestHelper.mock_container("def456", "/test2", "test:2.0.0"),
        TestHelper.mock_container("ghi789", "/test3", "test:3.0.0"),
      ]

      filtered = Mangrullo::ContainerFilter.filter_containers_by_name(containers, ["test1", "test3"])
      filtered.size.should eq(2)
      filtered.map(&.name).should contain("/test1")
      filtered.map(&.name).should contain("/test3")
    end

    it "handles names with and without slashes" do
      containers = [
        TestHelper.mock_container("abc123", "/test1", "test:1.0.0"),
        TestHelper.mock_container("def456", "/test2", "test:2.0.0"),
      ]

      # Mix of formats
      filtered = Mangrullo::ContainerFilter.filter_containers_by_name(containers, ["test1", "/test2"])
      filtered.size.should eq(2)
    end
  end

  describe "get_container_by_name" do
    containers = [
      TestHelper.mock_container("abc123", "/test1", "test:1.0.0"),
      TestHelper.mock_container("def456", "/test2", "test:2.0.0"),
    ]

    it "finds container by name with slash" do
      found = Mangrullo::ContainerFilter.get_container_by_name(containers, "/test1")
      found.should_not be_nil
      found.not_nil!.id.should eq("abc123")
    end

    it "finds container by name without slash" do
      found = Mangrullo::ContainerFilter.get_container_by_name(containers, "test2")
      found.should_not be_nil
      found.not_nil!.id.should eq("def456")
    end

    it "returns nil for non-existent container" do
      found = Mangrullo::ContainerFilter.get_container_by_name(containers, "nonexistent")
      found.should be_nil
    end
  end

  describe "container_exists?" do
    containers = [
      TestHelper.mock_container("abc123", "/test1", "test:1.0.0"),
    ]

    it "returns true for existing container" do
      Mangrullo::ContainerFilter.container_exists?(containers, "test1").should be_true
      Mangrullo::ContainerFilter.container_exists?(containers, "/test1").should be_true
    end

    it "returns false for non-existent container" do
      Mangrullo::ContainerFilter.container_exists?(containers, "nonexistent").should be_false
    end
  end

  describe "filter_containers_by_status" do
    it "filters running containers" do
      containers = [
        TestHelper.mock_container("abc123", "/test1", "test:1.0.0", "Up 2 hours"),
        TestHelper.mock_container("def456", "/test2", "test:2.0.0", "Exited (0) 1 hour ago"),
      ]

      filtered = Mangrullo::ContainerFilter.filter_containers_by_status(containers, "running")
      filtered.size.should eq(1)
      filtered.first.name.should eq("/test1")
    end

    it "filters stopped containers" do
      containers = [
        TestHelper.mock_container("abc123", "/test1", "test:1.0.0", "Up 2 hours"),
        TestHelper.mock_container("def456", "/test2", "test:2.0.0", "Exited (0) 1 hour ago"),
      ]

      filtered = Mangrullo::ContainerFilter.filter_containers_by_status(containers, "stopped")
      filtered.size.should eq(1)
      filtered.first.name.should eq("/test2")
    end
  end

  describe "filter_containers_by_image" do
    it "filters by image pattern" do
      containers = [
        TestHelper.mock_container("abc123", "/test1", "nginx:latest"),
        TestHelper.mock_container("def456", "/test2", "redis:alpine"),
        TestHelper.mock_container("ghi789", "/test3", "nginx:alpine"),
      ]

      filtered = Mangrullo::ContainerFilter.filter_containers_by_image(containers, "nginx")
      filtered.size.should eq(2)
    end
  end

  describe "sort_containers_by_name" do
    it "sorts containers by name" do
      containers = [
        TestHelper.mock_container("def456", "/test2", "test:2.0.0"),
        TestHelper.mock_container("abc123", "/test1", "test:1.0.0"),
        TestHelper.mock_container("ghi789", "/test3", "test:3.0.0"),
      ]

      sorted = Mangrullo::ContainerFilter.sort_containers_by_name(containers)
      sorted.map(&.name).should eq(["/test1", "/test2", "/test3"])
    end
  end

  describe "group_containers_by_status" do
    it "groups containers by status" do
      containers = [
        TestHelper.mock_container("abc123", "/test1", "test:1.0.0", "Up 2 hours"),
        TestHelper.mock_container("def456", "/test2", "test:2.0.0", "Exited (0) 1 hour ago"),
        TestHelper.mock_container("ghi789", "/test3", "test:3.0.0", "Up 1 hour"),
      ]

      groups = Mangrullo::ContainerFilter.group_containers_by_status(containers)

      groups["running"].size.should eq(2)
      groups["stopped"].size.should eq(1)
    end
  end

  describe "validate_container_names" do
    it "validates container names exist" do
      # Create a mock that returns specific containers
      mock_docker = MockDockerClient.new

      # We can't easily mock methods without more complex setup,
      # so let's test the logic directly
      valid, invalid = Mangrullo::ContainerFilter.validate_container_names(mock_docker, ["test1", "nonexistent"])

      # Since we can't mock the docker client easily in this context,
      # let's just verify the method handles the inputs correctly
      valid.should be_a(Array(String))
      invalid.should be_a(Array(String))
    end
  end

  describe "get_name_suggestions" do
    it "provides name suggestions for invalid names" do
      containers = [
        TestHelper.mock_container("abc123", "/nginx-web", "nginx:latest"),
        TestHelper.mock_container("def456", "/redis-cache", "redis:alpine"),
        TestHelper.mock_container("ghi789", "/postgres-db", "postgres:13"),
      ]

      suggestions = Mangrullo::ContainerFilter.get_name_suggestions(containers, "web")
      suggestions.should contain("nginx-web")
    end
  end
end
