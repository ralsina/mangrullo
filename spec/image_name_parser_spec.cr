require "./spec_helper"
require "../src/constants"
require "../src/image_name_parser"

describe Mangrullo::ImageNameParser do
  describe ".parse" do
    it "parses simple names without a tag" do
      parsed = Mangrullo::ImageNameParser.parse("nginx")
      parsed[:repository].should eq("nginx")
      parsed[:tag].should eq("latest")
    end

    it "parses names with a version tag" do
      parsed = Mangrullo::ImageNameParser.parse("nginx:1.25.3")
      parsed[:repository].should eq("nginx")
      parsed[:tag].should eq("1.25.3")
    end

    it "parses registry images without a tag" do
      parsed = Mangrullo::ImageNameParser.parse("ghcr.io/ralsina/mangrullo")
      parsed[:repository].should eq("ghcr.io/ralsina/mangrullo")
      parsed[:tag].should eq("latest")
    end

    it "parses registry images with a tag" do
      parsed = Mangrullo::ImageNameParser.parse("ghcr.io/ralsina/mangrullo:latest")
      parsed[:repository].should eq("ghcr.io/ralsina/mangrullo")
      parsed[:tag].should eq("latest")
    end

    it "does not mistake a registry port for a tag" do
      parsed = Mangrullo::ImageNameParser.parse("localhost:5000/my-app")
      parsed[:repository].should eq("localhost:5000/my-app")
      parsed[:tag].should eq("latest")
    end

    it "handles tags on registry images with ports" do
      parsed = Mangrullo::ImageNameParser.parse("localhost:5000/my-app:1.0")
      parsed[:repository].should eq("localhost:5000/my-app")
      parsed[:tag].should eq("1.0")
    end

    it "handles nested paths with ports and tags" do
      parsed = Mangrullo::ImageNameParser.parse("registry.example.com:443/sub/dir/image:v2")
      parsed[:repository].should eq("registry.example.com:443/sub/dir/image")
      parsed[:tag].should eq("v2")
    end

    it "handles single-number tags" do
      parsed = Mangrullo::ImageNameParser.parse("postgres:16")
      parsed[:repository].should eq("postgres")
      parsed[:tag].should eq("16")
    end
  end

  describe ".get_tag and .get_repository" do
    it "extracts the tag" do
      Mangrullo::ImageNameParser.get_tag("redis:7.2.4").should eq("7.2.4")
      Mangrullo::ImageNameParser.get_tag("localhost:5000/app").should eq("latest")
    end

    it "extracts the repository" do
      Mangrullo::ImageNameParser.get_repository("redis:7.2.4").should eq("redis")
      Mangrullo::ImageNameParser.get_repository("localhost:5000/app:2.0").should eq("localhost:5000/app")
    end
  end

  describe ".format_with_tag" do
    it "omits the latest tag" do
      Mangrullo::ImageNameParser.format_with_tag("nginx", "latest").should eq("nginx")
    end

    it "appends version tags" do
      Mangrullo::ImageNameParser.format_with_tag("localhost:5000/app", "1.0").should eq("localhost:5000/app:1.0")
    end
  end
end
