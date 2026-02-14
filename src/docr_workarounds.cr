# Workarounds for docr library bugs related to missing optional fields in Docker API responses
#
# The docr library has multiple issues with handling optional fields in Docker API responses.
# When the Docker API omits certain fields, docr's strict JSON mapping causes JSON::ParseException errors.
#
# This file provides monkey patches to make those fields nilable with sensible defaults.
#
# See DOCR_BUG_NOTES.md for more details on the underlying issues.

require "docr"

# Patch Docr::Types::NetworkSettings to handle missing optional fields
# Error: "Missing JSON attribute: Bridge"
module Docr::Types
  class NetworkSettings
    # Reopen the class and override initialize to handle missing fields
    # We use a custom JSON pull parser to handle missing optional fields

    # Define nilable versions with defaults
    @[JSON::Field(key: "Bridge")]
    property bridge : String?

    @[JSON::Field(key: "SandboxID")]
    property sandbox_id : String?

    @[JSON::Field(key: "HairpinMode")]
    property hairpin_mode : Bool = false

    @[JSON::Field(key: "LinkLocalIPv6Address")]
    property link_local_ipv6_address : String = ""

    @[JSON::Field(key: "LinkLocalIPv6PrefixLen")]
    property link_local_ipv6_prefix_len : Int64 = 0_i64

    @[JSON::Field(key: "Ports")]
    property ports : Hash(String, Array(Docr::Types::PortBinding)?) = {} of String => Array(Docr::Types::PortBinding)?

    @[JSON::Field(key: "SandboxKey")]
    property sandbox_key : String = ""

    @[JSON::Field(key: "SecondaryIPAddresses")]
    property secondary_ip_addresses : Array(Docr::Types::Address)? = nil

    @[JSON::Field(key: "SecondaryIPv6Addresses")]
    property secondary_ipv6_addresses : Array(Docr::Types::Address)? = nil

    @[JSON::Field(key: "EndpointID")]
    property endpoint_id : String = ""

    @[JSON::Field(key: "Gateway")]
    property gateway : String = ""

    @[JSON::Field(key: "GlobalIPv6Address")]
    property global_ipv6_address : String = ""

    @[JSON::Field(key: "GlobalIPv6PrefixLen")]
    property global_ipv6_prefix_len : Int64 = 0_i64

    @[JSON::Field(key: "IPAddress")]
    property ip_address : String = ""

    @[JSON::Field(key: "IPPrefixLen")]
    property ip_prefix_len : Int64 = 0_i64

    @[JSON::Field(key: "IPv6Gateway")]
    property ipv6_gateway : String = ""

    @[JSON::Field(key: "MacAddress")]
    property mac_address : String = ""

    @[JSON::Field(key: "Networks")]
    property networks : Hash(String, Docr::Types::EndpointSettings) = {} of String => Docr::Types::EndpointSettings
  end
end

# Patch Docr::Types::Image to handle missing optional fields
# Error: "Missing JSON attribute: Comment"
module Docr::Types
  class Image
    # Make optional fields nilable with defaults
    @[JSON::Field(key: "RepoTags")]
    property repo_tags : Array(String)? = nil

    @[JSON::Field(key: "RepoDigests")]
    property repo_digests : Array(String)? = nil

    @[JSON::Field(key: "Comment")]
    property comment : String = ""

    @[JSON::Field(key: "Config")]
    property config : Docr::Types::ContainerConfig? = nil

    @[JSON::Field(key: "Metadata")]
    property metadata : Docr::Types::Metadata? = nil
  end

  # Also patch Metadata since it might be missing
  class Metadata
    @[JSON::Field(key: "LastTagTime")]
    property last_tag_time : String = ""
  end
end

# Patch Docr::Types::ContainerSummary to handle missing optional fields
# Error: "Missing JSON attribute: Names"
module Docr::Types
  class ContainerSummary
    # Make optional fields nilable with defaults
    @[JSON::Field(key: "Names")]
    property names : Array(String) = [] of String

    @[JSON::Field(key: "Command")]
    property command : String = ""

    @[JSON::Field(key: "Labels")]
    property labels : Hash(String, String)? = nil

    @[JSON::Field(key: "State")]
    property state : String = ""

    @[JSON::Field(key: "Status")]
    property status : String = ""
  end
end

# Patch Docr::Types::ImageSummary to handle missing optional fields
# Error: "Missing JSON attribute: ParentId"
module Docr::Types
  class ImageSummary
    @[JSON::Field(key: "ParentId")]
    property parent_id : String = ""

    @[JSON::Field(key: "SharedSize")]
    property shared_size : Int64 = 0_i64

    @[JSON::Field(key: "Containers")]
    property containers : Int64 = 0_i64
  end
end
