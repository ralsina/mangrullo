require "./spec_helper"

describe Mangrullo::ErrorHandling do
  describe ".log_and_return_error" do
    it "returns error result with exception message" do
      result = Mangrullo::ErrorHandling.log_and_return_error(
        "test operation",
        Exception.new("test error")
      )

      result.success?.should be_false
      result.error.should_not be_nil
      result.error.not_nil!.should eq("test operation failed: test error")
    end

    it "includes context in error message when provided" do
      result = Mangrullo::ErrorHandling.log_and_return_error(
        "test operation",
        Exception.new("test error"),
        Log::Severity::Error,
        "context=123"
      )

      result.error.should_not be_nil
      result.error.not_nil!.should contain("context=123")
    end
  end

  describe ".log_debug_and_return_error" do
    it "returns error result for debug operations" do
      result = Mangrullo::ErrorHandling.log_debug_and_return_error(
        "debug operation",
        Exception.new("debug error")
      )

      result.success?.should be_false
      result.error.should_not be_nil
      result.error.not_nil!.should contain("debug error")
    end
  end

  describe ".docker_api_operation" do
    it "returns success result for successful operations" do
      result = Mangrullo::ErrorHandling.docker_api_operation("test op") do
        true
      end

      result.success?.should be_true
      result.value.should be_true
    end

    it "handles Docker API errors" do
      result = Mangrullo::ErrorHandling.docker_api_operation("test op") do
        raise Docr::Errors::DockerAPIError.new("Docker error", 500)
      end

      result.success?.should be_false
      result.error.should_not be_nil
      result.error.not_nil!.should contain("Docker error")
    end

    it "includes context in error message" do
      result = Mangrullo::ErrorHandling.docker_api_operation("test op", "container=test") do
        raise Docr::Errors::DockerAPIError.new("Failed", 404)
      end

      result.error.should_not be_nil
      result.error.not_nil!.should contain("container=test")
    end
  end

  describe ".docker_api_operation_with_nil" do
    it "handles operations that return nil" do
      result = Mangrullo::ErrorHandling.docker_api_operation_with_nil("test op") do
        nil
      end

      result.success?.should be_true
      result.value.should be_nil
    end
  end

  describe ".docker_api_operation_typed" do
    it "returns typed results" do
      result = Mangrullo::ErrorHandling.docker_api_operation_typed("test op") do
        "test string"
      end

      result.success?.should be_true
      result.value.should eq("test string")
    end
  end

  describe ".http_operation" do
    it "handles HTTP operations" do
      response = HTTP::Client::Response.new(200, "OK")
      result = Mangrullo::ErrorHandling.http_operation("HTTP request") do
        response
      end

      result.success?.should be_true
      result.value.should eq(response)
    end

    it "handles HTTP errors" do
      result = Mangrullo::ErrorHandling.http_operation("HTTP request") do
        raise Socket::Error.new("Connection failed")
      end

      result.success?.should be_false
      result.error.should_not be_nil
      result.error.not_nil!.should contain("Connection failed")
    end
  end

  describe ".success" do
    it "creates success result" do
      result = Mangrullo::ErrorHandling.success("test value")

      result.success?.should be_true
      result.value.should eq("test value")
    end

    it "creates success result with nil value" do
      result = Mangrullo::ErrorHandling.success

      result.success?.should be_true
      result.value.should be_nil
    end
  end

  describe ".error" do
    it "creates error result" do
      result = Mangrullo::ErrorHandling.error("Something went wrong")

      result.success?.should be_false
      result.error.should eq("Something went wrong")
    end

    it "creates error result with value" do
      result = Mangrullo::ErrorHandling.error("Error", "default value")

      result.success?.should be_false
      result.error.should eq("Error")
      result.value.should eq("default value")
    end
  end

  describe ".successful?" do
    it "returns true for successful results" do
      result = Mangrullo::ErrorHandling.success
      Mangrullo::ErrorHandling.successful?(result).should be_true
    end

    it "returns false for error results" do
      result = Mangrullo::ErrorHandling.error("failed")
      Mangrullo::ErrorHandling.successful?(result).should be_false
    end
  end

  describe ".failed?" do
    it "returns true for error results" do
      result = Mangrullo::ErrorHandling.error("failed")
      Mangrullo::ErrorHandling.failed?(result).should be_true
    end

    it "returns false for successful results" do
      result = Mangrullo::ErrorHandling.success
      Mangrullo::ErrorHandling.failed?(result).should be_false
    end
  end

  describe ".error_message" do
    it "extracts error message from result" do
      result = Mangrullo::ErrorHandling.error("test error")
      Mangrullo::ErrorHandling.error_message(result).should eq("test error")
    end

    it "returns nil for successful results" do
      result = Mangrullo::ErrorHandling.success
      Mangrullo::ErrorHandling.error_message(result).should be_nil
    end
  end

  describe ".value" do
    it "extracts value from result" do
      result = Mangrullo::ErrorHandling.success("test value")
      Mangrullo::ErrorHandling.value(result).should eq("test value")
    end

    it "returns nil for error results" do
      result = Mangrullo::ErrorHandling.error("failed")
      Mangrullo::ErrorHandling.value(result).should be_nil
    end
  end
end
