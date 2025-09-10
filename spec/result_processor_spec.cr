require "./spec_helper"

describe Mangrullo::ResultProcessor do
  describe "generate_summary" do
    it "generates summary from results" do
      container1 = TestHelper.mock_container("abc123", "/test1", "test:1.0.0")
      container2 = TestHelper.mock_container("def456", "/test2", "test:2.0.0")
      container3 = TestHelper.mock_container("ghi789", "/test3", "test:3.0.0")

      results = [
        {container: container1, updated: true, error: nil},
        {container: container2, updated: false, error: "Failed to update"},
        {container: container3, updated: false, error: nil},
      ]

      summary = Mangrullo::ResultProcessor.generate_summary(results)

      summary.total.should eq(3)
      summary.updated.should eq(1)
      summary.errors.should eq(1)
      summary.up_to_date.should eq(1)
      summary.error_messages.should contain("test2: Failed to update")
    end

    it "handles empty results" do
      results = [] of NamedTuple(container: Mangrullo::ContainerInfo, updated: Bool, error: String?)
      summary = Mangrullo::ResultProcessor.generate_summary(results)

      summary.total.should eq(0)
      summary.updated.should eq(0)
      summary.errors.should eq(0)
      summary.up_to_date.should eq(0)
      summary.error_messages.should be_empty
    end
  end

  describe "generate_unified_summary" do
    it "generates summary from unified results" do
      container1 = TestHelper.mock_container("abc123", "/test1", "test:1.0.0")
      container2 = TestHelper.mock_container("def456", "/test2", "test:2.0.0")
      container3 = TestHelper.mock_container("ghi789", "/test3", "test:3.0.0")

      results = [
        {container: container1, updated: true, error: nil, needs_update: false, reason: "Updated"},
        {container: container2, updated: false, error: "Failed", needs_update: true, reason: nil},
        {container: container3, updated: false, error: nil, needs_update: true, reason: "Update available"},
      ]

      summary = Mangrullo::ResultProcessor.generate_unified_summary(results)

      summary.total.should eq(3)
      summary.updated.should eq(1)
      summary.errors.should eq(1)
      summary.up_to_date.should eq(1)
      summary.error_messages.should contain("test2: Failed")
    end
  end

  describe "log_errors" do
    it "logs errors from results" do
      container1 = TestHelper.mock_container("abc123", "/test1", "test:1.0.0")
      container2 = TestHelper.mock_container("def456", "/test2", "test:2.0.0")

      results = [
        {container: container1, updated: true, error: nil},
        {container: container2, updated: false, error: "Test error"},
      ]

      # Just verify the method doesn't crash
      # Actual logging is hard to test without complex setup
      Mangrullo::ResultProcessor.log_errors(results)

      # If we get here without exception, the test passes
      true.should be_true
    end
  end

  describe "format_summary_cli" do
    it "formats summary for CLI display" do
      summary = Mangrullo::ResultProcessor::Summary.new(10, 3, 2, 5, ["error1", "error2"])
      formatted = Mangrullo::ResultProcessor.format_summary_cli(summary)

      formatted.should contain("Total containers: 10")
      formatted.should contain("Updated: 3")
      formatted.should contain("Up to date: 5")
      formatted.should contain("Errors: 2")
    end
  end

  describe "format_summary_json" do
    it "formats summary as JSON hash" do
      summary = Mangrullo::ResultProcessor::Summary.new(10, 3, 2, 5, ["error1", "error2"])
      json = Mangrullo::ResultProcessor.format_summary_json(summary)

      json["total"].should eq(10)
      json["updated"].should eq(3)
      json["up_to_date"].should eq(5)
      json["errors"].should eq(2)
      json["error_messages"].as(Array).should eq(["error1", "error2"])
    end
  end

  describe "filter_by_status" do
    container1 = TestHelper.mock_container("abc123", "/test1", "test:1.0.0")
    container2 = TestHelper.mock_container("def456", "/test2", "test:2.0.0")
    container3 = TestHelper.mock_container("ghi789", "/test3", "test:3.0.0")

    results = [
      {container: container1, updated: true, error: nil},
      {container: container2, updated: false, error: "Failed"},
      {container: container3, updated: false, error: nil},
    ]

    it "filters updated containers" do
      filtered = Mangrullo::ResultProcessor.filter_by_status(results, :updated)
      filtered.size.should eq(1)
      filtered.first[:container].name.should eq("/test1")
    end

    it "filters error containers" do
      filtered = Mangrullo::ResultProcessor.filter_by_status(results, :error)
      filtered.size.should eq(1)
      filtered.first[:container].name.should eq("/test2")
    end

    it "filters up to date containers" do
      filtered = Mangrullo::ResultProcessor.filter_by_status(results, :up_to_date)
      filtered.size.should eq(1)
      filtered.first[:container].name.should eq("/test3")
    end
  end
end
