require "./spec_helper"

describe Mangrullo::ContainerStatus do
  describe "get_status" do
    it "returns error status when error is present" do
      container = TestHelper.mock_container("abc123", "/test", "test:latest")
      status = Mangrullo::ContainerStatus.get_status(container, false, "Test error")

      status.type.should eq(Mangrullo::ContainerStatus::StatusType::ERROR)
      status.text.should eq("Error: Test error")
      status.css_class.should eq("status-error")
      status.reason.should eq("Test error")
    end

    it "returns latest tag status for latest images" do
      container = TestHelper.mock_container("abc123", "/test", "test:latest")
      status = Mangrullo::ContainerStatus.get_status(container, false)

      status.type.should eq(Mangrullo::ContainerStatus::StatusType::LATEST_TAG)
      status.text.should eq("Latest Tag")
      status.css_class.should eq("status-latest")
      status.reason.should eq("Using latest tag")
    end

    it "returns update available status when needed" do
      container = TestHelper.mock_container("abc123", "/test", "test:1.0.0")
      status = Mangrullo::ContainerStatus.get_status(container, true)

      status.type.should eq(Mangrullo::ContainerStatus::StatusType::UPDATE_AVAILABLE)
      status.text.should eq("Update Available")
      status.css_class.should eq("status-update-available")
      status.reason.should eq("New version available")
    end

    it "returns up to date status" do
      container = TestHelper.mock_container("abc123", "/test", "test:1.0.0")
      status = Mangrullo::ContainerStatus.get_status(container, false)

      status.type.should eq(Mangrullo::ContainerStatus::StatusType::UP_TO_DATE)
      status.text.should eq("Up to Date")
      status.css_class.should eq("status-up-to-date")
      status.reason.should be_nil
    end
  end

  describe "status helper methods" do
    container = TestHelper.mock_container("abc123", "/test", "test:1.0.0")

    it "gets CLI status text" do
      Mangrullo::ContainerStatus.get_cli_status(container, false).should eq("Up to Date")
      Mangrullo::ContainerStatus.get_cli_status(container, true).should eq("Update Available")
    end

    it "gets CSS class" do
      Mangrullo::ContainerStatus.get_css_class(container, false).should eq("status-up-to-date")
      Mangrullo::ContainerStatus.get_css_class(container, true).should eq("status-update-available")
    end

    it "checks if container is up to date" do
      Mangrullo::ContainerStatus.up_to_date?(container, false).should be_true
      Mangrullo::ContainerStatus.up_to_date?(container, true).should be_false
    end

    it "checks if container has error" do
      Mangrullo::ContainerStatus.has_error?(container, false).should be_false
      Mangrullo::ContainerStatus.has_error?(container, false, "Test error").should be_true
    end

    it "checks if container needs update" do
      Mangrullo::ContainerStatus.needs_update?(container, false).should be_false
      Mangrullo::ContainerStatus.needs_update?(container, true).should be_true
    end
  end
end
