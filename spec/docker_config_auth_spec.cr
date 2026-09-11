require "./spec_helper"
require "../src/docker_config_auth"
require "base64"
require "file_utils"

describe Mangrullo::DockerConfigAuth do
  describe ".normalize_host" do
    it "normalizes registry spellings to bare hosts" do
      Mangrullo::DockerConfigAuth.normalize_host("ghcr.io").should eq("ghcr.io")
      Mangrullo::DockerConfigAuth.normalize_host("https://ghcr.io/").should eq("ghcr.io")
      Mangrullo::DockerConfigAuth.normalize_host("https://index.docker.io/v1/").should eq("docker.io")
      Mangrullo::DockerConfigAuth.normalize_host("registry-1.docker.io").should eq("docker.io")
      Mangrullo::DockerConfigAuth.normalize_host(" Registry.Example.com:5000 ").should eq("registry.example.com:5000")
    end
  end

  describe ".credentials_for" do
    config_dir = File.tempname("mangrullo-test-docker-config")
    config_path = File.join(config_dir, "config.json")

    around_each do |example|
      Dir.mkdir_p(config_dir)
      example.run
      FileUtils.rm_rf(config_dir)
    end

    it "returns credentials for a matching ghcr.io entry" do
      File.write(config_path, {
        "auths" => {
          "ghcr.io" => {"auth" => Base64.strict_encode("user:token123")},
        },
      }.to_json)

      credentials = Mangrullo::DockerConfigAuth.credentials_for("ghcr.io", config_path)
      credentials.should eq({user: "user", password: "token123"})
    end

    it "matches docker hub entries stored with the legacy index URL" do
      File.write(config_path, {
        "auths" => {
          "https://index.docker.io/v1/" => {"auth" => Base64.strict_encode("hubuser:hubpass")},
        },
      }.to_json)

      credentials = Mangrullo::DockerConfigAuth.credentials_for("registry-1.docker.io", config_path)
      credentials.should eq({user: "hubuser", password: "hubpass"})
    end

    it "handles passwords containing colons" do
      File.write(config_path, {
        "auths" => {
          "ghcr.io" => {"auth" => Base64.strict_encode("user:pa:ss:word")},
        },
      }.to_json)

      credentials = Mangrullo::DockerConfigAuth.credentials_for("ghcr.io", config_path)
      credentials.should eq({user: "user", password: "pa:ss:word"})
    end

    it "returns nil when no entry matches the registry" do
      File.write(config_path, {
        "auths" => {
          "ghcr.io" => {"auth" => Base64.strict_encode("user:token123")},
        },
      }.to_json)

      Mangrullo::DockerConfigAuth.credentials_for("registry.example.com", config_path).should be_nil
    end

    it "returns nil for entries delegated to a credsStore" do
      File.write(config_path, {
        "auths"      => {"ghcr.io" => {} of String => String},
        "credsStore" => "secretservice",
      }.to_json)

      Mangrullo::DockerConfigAuth.credentials_for("ghcr.io", config_path).should be_nil
    end

    it "returns nil when the config file does not exist" do
      Mangrullo::DockerConfigAuth.credentials_for("ghcr.io", File.join(config_dir, "missing.json")).should be_nil
    end

    it "returns nil for invalid JSON" do
      File.write(config_path, "{not json")
      Mangrullo::DockerConfigAuth.credentials_for("ghcr.io", config_path).should be_nil
    end

    it "returns nil for malformed base64 auth entries" do
      File.write(config_path, {"auths" => {"ghcr.io" => {"auth" => "!!!not-base64!!!"}}}.to_json)
      Mangrullo::DockerConfigAuth.credentials_for("ghcr.io", config_path).should be_nil
    end
  end
end
