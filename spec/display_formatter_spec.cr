require "./spec_helper"

describe Mangrullo::DisplayFormatter do
  describe "truncate_image_name" do
    it "returns short image names as-is" do
      Mangrullo::DisplayFormatter.truncate_image_name("nginx:latest").should eq("nginx:latest")
    end

    it "truncates long simple image names" do
      long_name = "very/long/namespace/image/name:with-long-tag"
      truncated = Mangrullo::DisplayFormatter.truncate_image_name(long_name, 30)
      truncated.size.should eq(30)
      truncated.should end_with(":with-long-tag")
    end

    it "handles registry names smartly" do
      registry_image = "registry.example.com:5000/namespace/project/service:latest"
      truncated = Mangrullo::DisplayFormatter.truncate_image_name(registry_image, 40)
      truncated.size.should eq(40)
      truncated.should contain("registry.example.com")
      truncated.should end_with(":latest")
    end

    it "preserves tags when possible" do
      image_with_tag = "library/redis:alpine-3.14"
      truncated = Mangrullo::DisplayFormatter.truncate_image_name(image_with_tag, 25)
      truncated.should contain(":alpine")
    end
  end

  describe "truncate_string" do
    it "returns short strings as-is" do
      Mangrullo::DisplayFormatter.truncate_string("short", 10).should eq("short")
    end

    it "truncates long strings with ellipsis" do
      Mangrullo::DisplayFormatter.truncate_string("this is a very long string", 10).should eq("this is...")
    end
  end

  describe "format_status_with_color" do
    it "colors error status red" do
      formatted = Mangrullo::DisplayFormatter.format_status_with_color("Error", "Something went wrong")
      formatted.should eq("\033[31mError\033[0m")
    end

    it "colors updated status green" do
      formatted = Mangrullo::DisplayFormatter.format_status_with_color("Updated")
      formatted.should eq("\033[32mUpdated\033[0m")
    end

    it "colors up to date status cyan" do
      formatted = Mangrullo::DisplayFormatter.format_status_with_color("Up to Date")
      formatted.should eq("\033[36mUp to Date\033[0m")
    end
  end

  describe "format_results_as_table" do
    it "formats empty results" do
      table = Mangrullo::DisplayFormatter.format_results_as_table([] of NamedTuple(container: Mangrullo::ContainerInfo, updated: Bool, error: String?))
      table.should eq("No containers to display")
    end

    it "formats results as table" do
      container1 = TestHelper.mock_container("abc123", "/test1", "nginx:latest")
      container2 = TestHelper.mock_container("def456", "/test2", "redis:alpine")

      results = [
        {container: container1, updated: true, error: nil},
        {container: container2, updated: false, error: "Failed to update"},
      ]

      options = Mangrullo::DisplayFormatter::TableOptions.new(color: false, max_status_width: 25)
      table = Mangrullo::DisplayFormatter.format_results_as_table(results, options)

      table.should contain("Container")
      table.should contain("Image")
      table.should contain("Status")
      table.should contain("test1")
      table.should contain("test2")
      table.should contain("Updated")
      table.should contain("Error: Failed to update")
    end
  end

  describe "format_unified_results_as_table" do
    it "formats unified results with action column" do
      container = TestHelper.mock_container("abc123", "/test1", "nginx:latest")

      results = [
        {container: container, updated: false, error: nil, needs_update: true, reason: "Update available"},
      ]

      options = Mangrullo::DisplayFormatter::TableOptions.new(color: false)
      table = Mangrullo::DisplayFormatter.format_unified_results_as_table(results, options)

      table.should contain("Container")
      table.should contain("Image")
      table.should contain("Status")
      table.should contain("Action")
      table.should contain("Update available")
    end

    it "supports compact mode" do
      container = TestHelper.mock_container("abc123", "/test1", "nginx:latest")

      results = [
        {container: container, updated: false, error: nil, needs_update: false, reason: nil},
      ]

      options = Mangrullo::DisplayFormatter::TableOptions.new(compact: true, color: false)
      table = Mangrullo::DisplayFormatter.format_unified_results_as_table(results, options)

      table.should contain("Container")
      table.should contain("Image")
      table.should contain("Status")
      table.should_not contain("Action")
    end
  end

  describe "format_results_as_html_table" do
    it "formats empty results" do
      html = Mangrullo::DisplayFormatter.format_results_as_html_table([] of NamedTuple(container: Mangrullo::ContainerInfo, updated: Bool, error: String?))
      html.should eq("<p>No containers to display</p>")
    end

    it "formats results as HTML table" do
      container = TestHelper.mock_container("abc123", "/test1", "nginx:latest")

      results = [
        {container: container, updated: true, error: nil},
      ]

      options = Mangrullo::DisplayFormatter::HtmlTableOptions.new
      html = Mangrullo::DisplayFormatter.format_results_as_html_table(results, options)

      html.should contain("<table")
      html.should contain("<thead>")
      html.should contain("<th>Container</th>")
      html.should contain("<th>Image</th>")
      html.should contain("<th>Status</th>")
      html.should contain("test1")
      html.should contain("nginx")
      html.should contain("Updated")
    end
  end

  describe "format_container_for_log" do
    it "formats container info for logging" do
      container = TestHelper.mock_container("abc123", "/very-long-container-name-that-should-be-truncated", "very/long/image/name:with-long-tag")

      formatted = Mangrullo::DisplayFormatter.format_container_for_log(container)
      formatted.should contain("very-long-container-name-that-should-be-truncated")
      formatted.should contain("very/long/ima")
      formatted.size.should be <= 85 # Rough estimate of truncated length
    end
  end

  describe "format_error_with_context" do
    it "includes context when provided" do
      formatted = Mangrullo::DisplayFormatter.format_error_with_context("Something failed", "container=test")
      formatted.should eq("container=test: Something failed")
    end

    it "returns message as-is without context" do
      formatted = Mangrullo::DisplayFormatter.format_error_with_context("Something failed")
      formatted.should eq("Something failed")
    end
  end
end
