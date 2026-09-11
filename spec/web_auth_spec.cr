require "./spec_helper"
require "../src/web_auth"
require "base64"

describe Mangrullo::WebAuth do
  describe ".enabled?" do
    it "is enabled only when both credentials are set" do
      Mangrullo::WebAuth.enabled?("user", "pass").should be_true
      Mangrullo::WebAuth.enabled?(nil, "pass").should be_false
      Mangrullo::WebAuth.enabled?("user", nil).should be_false
      Mangrullo::WebAuth.enabled?(nil, nil).should be_false
    end
  end

  describe ".authorized?" do
    user = "admin"
    password = "s3cret:with:colons"
    valid_header = "Basic #{Base64.strict_encode("admin:s3cret:with:colons")}"

    it "accepts valid credentials" do
      Mangrullo::WebAuth.authorized?(valid_header, user, password).should be_true
    end

    it "rejects wrong passwords" do
      header = "Basic #{Base64.strict_encode("admin:wrong")}"
      Mangrullo::WebAuth.authorized?(header, user, password).should be_false
    end

    it "rejects wrong usernames" do
      header = "Basic #{Base64.strict_encode("root:s3cret:with:colons")}"
      Mangrullo::WebAuth.authorized?(header, user, password).should be_false
    end

    it "treats everything after the first colon as the password" do
      header = "Basic #{Base64.strict_encode("admin:s3cret")}"
      Mangrullo::WebAuth.authorized?(header, user, password).should be_false

      pw = "secret"
      header = "Basic #{Base64.strict_encode("admin:pa:ss:word")}"
      Mangrullo::WebAuth.authorized?(header, "admin", pw).should be_false
      header = "Basic #{Base64.strict_encode("admin:secret")}"
      Mangrullo::WebAuth.authorized?(header, "admin", pw).should be_true
    end

    it "rejects missing or malformed headers" do
      Mangrullo::WebAuth.authorized?(nil, user, password).should be_false
      Mangrullo::WebAuth.authorized?("", user, password).should be_false
      Mangrullo::WebAuth.authorized?("Bearer abc123", user, password).should be_false
      Mangrullo::WebAuth.authorized?("Basic !!!not-base64!!!", user, password).should be_false
      Mangrullo::WebAuth.authorized?("Basic", user, password).should be_false
    end

    it "is case-insensitive about the scheme" do
      header = "basic #{Base64.strict_encode("admin:s3cret:with:colons")}"
      Mangrullo::WebAuth.authorized?(header, user, password).should be_true
    end
  end
end
