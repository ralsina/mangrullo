require "./spec_helper"
require "../src/types"

describe Mangrullo::Version do
  describe ".parse" do
    it "parses simple versions" do
      version = Mangrullo::Version.parse("1.2.3")
      version.should_not be_nil
      version.should be_a(Mangrullo::Version)
      version = version.as(Mangrullo::Version)
      version.major.should eq(1)
      version.minor.should eq(2)
      version.patch.should eq(3)
    end

    it "parses versions with two components" do
      version = Mangrullo::Version.parse("1.2")
      version.should_not be_nil
      version.should be_a(Mangrullo::Version)
      version = version.as(Mangrullo::Version)
      version.major.should eq(1)
      version.minor.should eq(2)
      version.patch.should eq(0)
    end

    it "parses versions with prerelease" do
      version = Mangrullo::Version.parse("1.2.3-alpha")
      version.should_not be_nil
      version.should be_a(Mangrullo::Version)
      version = version.as(Mangrullo::Version)
      version.major.should eq(1)
      version.minor.should eq(2)
      version.patch.should eq(3)
      version.prerelease.should eq("alpha")
    end

    it "parses versions with build metadata" do
      version = Mangrullo::Version.parse("1.2.3+build.123")
      version.should_not be_nil
      version.should be_a(Mangrullo::Version)
      version = version.as(Mangrullo::Version)
      version.major.should eq(1)
      version.minor.should eq(2)
      version.patch.should eq(3)
      version.build.should eq("build.123")
    end

    it "parses versions with prerelease and build metadata" do
      version = Mangrullo::Version.parse("1.2.3-alpha+build.123")
      version.should_not be_nil
      version.should be_a(Mangrullo::Version)
      version = version.as(Mangrullo::Version)
      version.major.should eq(1)
      version.minor.should eq(2)
      version.patch.should eq(3)
      version.prerelease.should eq("alpha")
      version.build.should eq("build.123")
    end

    it "parses versions with v prefix" do
      version = Mangrullo::Version.parse("v1.2.3")
      version.should_not be_nil
      version.should be_a(Mangrullo::Version)
      version = version.as(Mangrullo::Version)
      version.major.should eq(1)
      version.minor.should eq(2)
      version.patch.should eq(3)
    end

    it "handles registry prefixes" do
      version = Mangrullo::Version.parse("1.2.3")
      version.should_not be_nil
      version.should be_a(Mangrullo::Version)
      version = version.as(Mangrullo::Version)
      version.major.should eq(1)
      version.minor.should eq(2)
      version.patch.should eq(3)
    end

    it "returns nil for invalid versions" do
      Mangrullo::Version.parse("invalid").should be_nil
      Mangrullo::Version.parse("").should be_nil
      Mangrullo::Version.parse("1").should be_nil
      Mangrullo::Version.parse("1.2.3.4").should be_nil
    end

    it "returns nil for blank input" do
      Mangrullo::Version.parse("").should be_nil
    end
  end

  describe "comparison operators" do
    it "compares major versions" do
      v1_0_0 = Mangrullo::Version.new(1, 0, 0)
      v2_0_0 = Mangrullo::Version.new(2, 0, 0)

      (v1_0_0 < v2_0_0).should be_true
      (v2_0_0 > v1_0_0).should be_true
      (v1_0_0 == v1_0_0).should be_true
    end

    it "compares minor versions" do
      v1_0_0 = Mangrullo::Version.new(1, 0, 0)
      v1_1_0 = Mangrullo::Version.new(1, 1, 0)

      (v1_0_0 < v1_1_0).should be_true
      (v1_1_0 > v1_0_0).should be_true
    end

    it "compares patch versions" do
      v1_0_0 = Mangrullo::Version.new(1, 0, 0)
      v1_0_1 = Mangrullo::Version.new(1, 0, 1)

      (v1_0_0 < v1_0_1).should be_true
      (v1_0_1 > v1_0_0).should be_true
    end

    it "compares prerelease versions" do
      v1_0_0 = Mangrullo::Version.new(1, 0, 0)
      v1_0_0_alpha = Mangrullo::Version.new(1, 0, 0, "alpha")

      (v1_0_0_alpha < v1_0_0).should be_true
      (v1_0_0 > v1_0_0_alpha).should be_true
    end

    it "compares prerelease versions with different identifiers" do
      v_alpha = Mangrullo::Version.new(1, 0, 0, "alpha")
      v_beta = Mangrullo::Version.new(1, 0, 0, "beta")
      v_rc = Mangrullo::Version.new(1, 0, 0, "rc")

      (v_alpha < v_beta).should be_true
      (v_beta < v_rc).should be_true
      (v_rc > v_beta).should be_true
    end

    it "handles equal versions" do
      v1 = Mangrullo::Version.new(1, 2, 3, "alpha", "build.123")
      v2 = Mangrullo::Version.new(1, 2, 3, "alpha", "build.456")

      (v1 == v2).should be_true
      (v1 <= v2).should be_true
      (v1 >= v2).should be_true
    end

    it "sorts versions correctly" do
      versions = [
        Mangrullo::Version.new(1, 0, 0),
        Mangrullo::Version.new(1, 0, 1),
        Mangrullo::Version.new(1, 1, 0),
        Mangrullo::Version.new(2, 0, 0),
        Mangrullo::Version.new(1, 0, 0, "alpha"),
        Mangrullo::Version.new(1, 0, 0, "beta"),
      ]

      sorted = versions.sort
      sorted.map(&.to_s).should eq([
        "1.0.0-alpha",
        "1.0.0-beta",
        "1.0.0",
        "1.0.1",
        "1.1.0",
        "2.0.0",
      ])
    end
  end

  describe "#major_upgrade?" do
    it "returns true for major version differences" do
      v1 = Mangrullo::Version.new(1, 2, 3)
      v2 = Mangrullo::Version.new(2, 0, 0)

      v1.major_upgrade?(v2).should be_true
      v2.major_upgrade?(v1).should be_true
    end

    it "returns false for same major version" do
      v1 = Mangrullo::Version.new(1, 2, 3)
      v2 = Mangrullo::Version.new(1, 5, 0)

      v1.major_upgrade?(v2).should be_false
      v2.major_upgrade?(v1).should be_false
    end

    it "returns false for minor/patch differences" do
      v1 = Mangrullo::Version.new(1, 2, 3)
      v2 = Mangrullo::Version.new(1, 3, 0)
      v3 = Mangrullo::Version.new(1, 2, 4)

      v1.major_upgrade?(v2).should be_false
      v1.major_upgrade?(v3).should be_false
    end
  end

  describe "#to_s" do
    it "formats simple versions" do
      version = Mangrullo::Version.new(1, 2, 3)
      version.to_s.should eq("1.2.3")
    end

    it "formats versions with prerelease" do
      version = Mangrullo::Version.new(1, 2, 3, "alpha")
      version.to_s.should eq("1.2.3-alpha")
    end

    it "formats versions with build metadata" do
      version = Mangrullo::Version.new(1, 2, 3, nil, "build.123")
      version.to_s.should eq("1.2.3+build.123")
    end

    it "formats versions with both prerelease and build metadata" do
      version = Mangrullo::Version.new(1, 2, 3, "alpha", "build.123")
      version.to_s.should eq("1.2.3-alpha+build.123")
    end
  end
end
