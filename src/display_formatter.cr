require "./types"
require "./container_status"
require "./result_processor"
require "./constants"
require "./container_name_utils"
require "./image_name_parser"
require "./string_display_utils"

module Mangrullo
  # Display formatting utilities for CLI and web interfaces
  module DisplayFormatter
    # Table formatting options
    struct TableOptions
      property max_name_width : Int32
      property max_image_width : Int32
      property max_status_width : Int32
      property max_reason_width : Int32
      property show_header : Bool
      property color : Bool
      property compact : Bool

      def initialize(
        @max_name_width : Int32 = 25,
        @max_image_width : Int32 = 40,
        @max_status_width : Int32 = 15,
        @max_reason_width : Int32 = 20,
        @show_header : Bool = true,
        @color : Bool = true,
        @compact : Bool = false,
      )
      end
    end

    # HTML table formatting options
    struct HtmlTableOptions
      property css_class : String?
      property include_actions : Bool
      property include_status : Bool
      property striped : Bool
      property hover : Bool

      def initialize(
        @css_class : String? = nil,
        @include_actions : Bool = true,
        @include_status : Bool = true,
        @striped : Bool = true,
        @hover : Bool = true,
      )
      end
    end

    # Truncate image name for display - delegate to ImageNameParser
    def self.truncate_image_name(image : String, max_length : Int32 = Constants::Table::MAX_COLUMN_WIDTH) : String
      ImageNameParser.display_name(image, max_length)
    end

    # Truncate string with ellipsis - delegate to StringDisplayUtils
    def self.truncate_string(str : String, max_length : Int32) : String
      StringDisplayUtils.truncate(str, max_length)
    end

    # Format container status with color
    def self.format_status_with_color(status : String, error : String? = nil) : String
      return "\033[31m#{status}\033[0m" if error # Red for errors

      case status.downcase
      when "updated"
        "\033[32m#{status}\033[0m" # Green
      when "up to date"
        "\033[36m#{status}\033[0m" # Cyan
      when "update available"
        "\033[33m#{status}\033[0m" # Yellow
      when "latest tag"
        "\033[34m#{status}\033[0m" # Blue
      else
        status
      end
    end

    # Format container results as CLI table
    def self.format_results_as_table(
      results : Array(NamedTuple(container: ContainerInfo, updated: Bool, error: String?)),
      options : TableOptions = TableOptions.new,
    ) : String
      return "No containers to display" if results.empty?

      lines = [] of String

      # Calculate column widths
      name_width = [results.max_of { |result| ContainerNameUtils.normalize_name_string(result[:container].name).size } || 0, "Container".size].max.clamp(0, options.max_name_width)
      image_width = [results.max_of { |result| truncate_image_name(result[:container].image).size } || 0, "Image".size].max.clamp(0, options.max_image_width)
      status_width = [results.max_of { |result| (result[:updated] ? "Updated" : ContainerStatus.get_cli_status(result[:container], nil, result[:error])).size } || 0, "Status".size].max.clamp(0, options.max_status_width)

      # Add header
      if options.show_header
        header = sprintf "%-#{name_width}.#{name_width}s  %-#{image_width}.#{image_width}s  %-#{status_width}.#{status_width}s",
          "Container", "Image", "Status"
        lines << header
        lines << "-" * (name_width + image_width + status_width + 4) unless options.compact
      end

      # Add rows
      results.each do |result|
        container = result[:container]
        name = ContainerNameUtils.normalize_name_string(container.name)
        image = truncate_image_name(container.image)
        status = result[:updated] ? "Updated" : ContainerStatus.get_cli_status(container, nil, result[:error])

        if options.color
          formatted_status = format_status_with_color(status, result[:error])
          line = sprintf "%-#{name_width}.#{name_width}s  %-#{image_width}.#{image_width}s  %-#{status_width}.#{status_width}s",
            name, image, formatted_status
        else
          line = sprintf "%-#{name_width}.#{name_width}s  %-#{image_width}.#{image_width}s  %-#{status_width}.#{status_width}s",
            name, image, status
        end

        lines << line
      end

      lines.join("\n")
    end

    # Format unified results (with dry run info) as CLI table
    def self.format_unified_results_as_table(
      results : Array(NamedTuple(container: ContainerInfo, updated: Bool, error: String?, needs_update: Bool?, reason: String?)),
      options : TableOptions = TableOptions.new,
    ) : String
      return "No containers to display" if results.empty?

      lines = [] of String

      # Calculate column widths
      name_width = [results.max_of { |result| ContainerNameUtils.normalize_name_string(result[:container].name).size } || 0, "Container".size].max.clamp(0, options.max_name_width)
      image_width = [results.max_of { |result| truncate_image_name(result[:container].image).size } || 0, "Image".size].max.clamp(0, options.max_image_width)
      status_width = [results.max_of { |result| ContainerStatus.get_cli_status(result[:container], result[:needs_update], result[:error]).size } || 0, "Status".size].max.clamp(0, options.max_status_width)
      reason_width = [results.max_of { |result| (result[:reason] || "").size } || 0, "Action".size].max.clamp(0, options.max_reason_width) unless options.compact

      # Add header
      if options.show_header
        if options.compact
          header = sprintf "%-#{name_width}.#{name_width}s  %-#{image_width}.#{image_width}s  %-#{status_width}.#{status_width}s",
            "Container", "Image", "Status"
        else
          header = sprintf "%-#{name_width}.#{name_width}s  %-#{image_width}.#{image_width}s  %-#{status_width}.#{status_width}s  %-#{reason_width}.#{reason_width}s",
            "Container", "Image", "Status", "Action"
        end
        lines << header
        unless options.compact
          separator_width = name_width + image_width + status_width + reason_width.not_nil! + 6
          lines << "-" * separator_width
        end
      end

      # Add rows
      results.each do |result|
        container = result[:container]
        name = ContainerNameUtils.normalize_name_string(container.name)
        image = truncate_image_name(container.image)
        status = ContainerStatus.get_cli_status(container, result[:needs_update], result[:error])
        reason = result[:reason] || ""

        if options.compact
          if options.color
            formatted_status = format_status_with_color(status, result[:error])
            line = sprintf "%-#{name_width}.#{name_width}s  %-#{image_width}.#{image_width}s  %-#{status_width}.#{status_width}s",
              name, image, formatted_status
          else
            line = sprintf "%-#{name_width}.#{name_width}s  %-#{image_width}.#{image_width}s  %-#{status_width}.#{status_width}s",
              name, image, status
          end
        else
          if options.color
            formatted_status = format_status_with_color(status, result[:error])
            line = sprintf "%-#{name_width}.#{name_width}s  %-#{image_width}.#{image_width}s  %-#{status_width}.#{status_width}s  %-#{reason_width}.#{reason_width}s",
              name, image, formatted_status, truncate_string(reason, reason_width.not_nil!)
          else
            line = sprintf "%-#{name_width}.#{name_width}s  %-#{image_width}.#{image_width}s  %-#{status_width}.#{status_width}s  %-#{reason_width}.#{reason_width}s",
              name, image, status, truncate_string(reason, reason_width.not_nil!)
          end
        end

        lines << line
      end

      lines.join("\n")
    end

    # Format results as HTML table
    def self.format_results_as_html_table(
      results : Array(NamedTuple(container: ContainerInfo, updated: Bool, error: String?)),
      options : HtmlTableOptions = HtmlTableOptions.new,
    ) : String
      return "<p>No containers to display</p>" if results.empty?

      css_classes = [] of String
      css_classes << options.css_class.not_nil! if options.css_class
      css_classes << "table-striped" if options.striped
      css_classes << "table-hover" if options.hover

      html = String.build do |io|
        io << "<table"
        io << " class=\"#{css_classes.join(" ")}\"" unless css_classes.empty?
        io << ">\n"

        # Header
        io << "  <thead>\n"
        io << "    <tr>\n"
        io << "      <th>Container</th>\n"
        io << "      <th>Image</th>\n"
        io << "      <th>Status</th>\n"
        io << "    </tr>\n"
        io << "  </thead>\n"

        # Body
        io << "  <tbody>\n"
        results.each do |result|
          container = result[:container]
          name = ContainerNameUtils.normalize_name_string(container.name)
          image = truncate_image_name(container.image, 50)
          status = result[:updated] ? "Updated" : ContainerStatus.get_cli_status(container, nil, result[:error])
          css_class = ContainerStatus.get_css_class(container, nil, result[:error])

          io << "    <tr"
          io << " class=\"#{css_class}\"" if css_class
          io << ">\n"
          io << "      <td>#{name}</td>\n"
          io << "      <td><code>#{image}</code></td>\n"
          io << "      <td>#{status}</td>\n"

          if options.include_actions
            io << "      <td>\n"
            if result[:error]
              io << "        <span class=\"text-danger\">Error</span>\n"
            elsif result[:updated]
              io << "        <span class=\"text-success\">Updated</span>\n"
            else
              io << "        <span class=\"text-muted\">No action</span>\n"
            end
            io << "      </td>\n"
          end

          io << "    </tr>\n"
        end
        io << "  </tbody>\n"
        io << "</table>\n"
      end

      html
    end

    # Format unified results as HTML table
    def self.format_unified_results_as_html_table(
      results : Array(NamedTuple(container: ContainerInfo, updated: Bool, error: String?, needs_update: Bool?, reason: String?)),
      options : HtmlTableOptions = HtmlTableOptions.new,
    ) : String
      return "<p>No containers to display</p>" if results.empty?

      css_classes = [] of String
      css_classes << options.css_class.not_nil! if options.css_class
      css_classes << "table-striped" if options.striped
      css_classes << "table-hover" if options.hover

      html = String.build do |io|
        io << "<table"
        io << " class=\"#{css_classes.join(" ")}\"" unless css_classes.empty?
        io << ">\n"

        # Header
        io << "  <thead>\n"
        io << "    <tr>\n"
        io << "      <th>Container</th>\n"
        io << "      <th>Image</th>\n"
        io << "      <th>Status</th>\n"
        if options.include_status
          io << "      <th>Needs Update</th>\n"
          io << "      <th>Action</th>\n"
        end
        io << "    </tr>\n"
        io << "  </thead>\n"

        # Body
        io << "  <tbody>\n"
        results.each do |result|
          container = result[:container]
          name = ContainerNameUtils.normalize_name_string(container.name)
          image = truncate_image_name(container.image, 50)
          status = ContainerStatus.get_cli_status(container, result[:needs_update], result[:error])
          css_class = ContainerStatus.get_css_class(container, result[:needs_update], result[:error])

          io << "    <tr"
          io << " class=\"#{css_class}\"" if css_class
          io << ">\n"
          io << "      <td>#{name}</td>\n"
          io << "      <td><code>#{image}</code></td>\n"
          io << "      <td>#{status}</td>\n"

          if options.include_status
            io << "      <td>\n"
            if result[:needs_update]
              io << "        <span class=\"badge bg-warning\">Yes</span>\n"
            else
              io << "        <span class=\"badge bg-success\">No</span>\n"
            end
            io << "      </td>\n"

            io << "      <td>\n"
            if result[:error]
              io << "        <span class=\"text-danger\">Error</span>\n"
            elsif result[:updated]
              io << "        <span class=\"text-success\">Updated</span>\n"
            else
              action = result[:reason] || "No action"
              io << "        <span class=\"text-muted\">#{action}</span>\n"
            end
            io << "      </td>\n"
          end

          io << "    </tr>\n"
        end
        io << "  </tbody>\n"
        io << "</table>\n"
      end

      html
    end

    # Format progress bar
    def self.format_progress_bar(current : Int32, total : Int32, width : Int32 = 40) : String
      return "" unless STDOUT.tty?

      percentage = total > 0 ? (current * 100 / total) : 0
      filled = (width * current / total).to_i.clamp(0, width)
      empty = width - filled

      bar = "[" + "=" * filled + " " * empty + "]"
      "#{bar} #{current}/#{total} (#{percentage}%)"
    end

    # Format container info for logging
    def self.format_container_for_log(container : ContainerInfo) : String
      "#{ContainerNameUtils.normalize_name_string(container.name)} (#{truncate_image_name(container.image, 30)})"
    end

    # Format error message with context
    def self.format_error_with_context(message : String, context : String? = nil) : String
      context ? "#{context}: #{message}" : message
    end
  end
end
