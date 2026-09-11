require "crypto/subtle"
require "base64"

module Mangrullo
  # Optional HTTP Basic authentication for the web UI.
  #
  # Enabled by setting both MANGRULLO_WEB_USER and MANGRULLO_WEB_PASSWORD;
  # with either unset the UI is open, matching previous behavior.
  module WebAuth
    def self.enabled?(user : String?, password : String?) : Bool
      !!user && !!password
    end

    # Constant-time credential check against a Basic "Authorization" header.
    # The password may contain colons: everything after the first colon in
    # the decoded credentials is treated as the password.
    def self.authorized?(auth_header : String?, user : String, password : String) : Bool
      return false unless auth_header

      scheme, _, credentials = auth_header.partition(" ")
      return false unless scheme.downcase == "basic"

      begin
        decoded = Base64.decode_string(credentials)
      rescue Base64::Error
        return false
      end

      supplied_user, _, supplied_password = decoded.partition(":")

      Crypto::Subtle.constant_time_compare(supplied_user, user) &&
        Crypto::Subtle.constant_time_compare(supplied_password, password)
    end
  end
end
