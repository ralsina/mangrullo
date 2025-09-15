module Mangrullo
  # Utility methods for string display formatting
  module StringDisplayUtils
    # Truncate string with ellipsis
    def self.truncate(text : String?, max_length : Int32, ellipsis : String = "...") : String
      return "" unless text

      if text.size <= max_length
        text
      else
        text[0, max_length - ellipsis.size] + ellipsis
      end
    end

    # Truncate from the middle (useful for IDs)
    def self.truncate_middle(text : String?, max_length : Int32, ellipsis : String = "...") : String
      return "" unless text

      if text.size <= max_length
        text
      else
        len = max_length - ellipsis.size
        start_len = (len / 2.0).ceil.to_i
        end_len = (len / 2.0).floor.to_i

        text[0, start_len] + ellipsis + text[text.size - end_len, end_len]
      end
    end

    # Truncate the beginning of a string
    def self.truncate_start(text : String?, max_length : Int32, ellipsis : String = "...") : String
      return "" unless text

      if text.size <= max_length
        text
      else
        ellipsis + text[-(max_length - ellipsis.size)..-1]
      end
    end

    # Format a duration in human-readable format
    def self.format_duration(seconds : Int) : String
      if seconds < 60
        "#{seconds}s"
      elsif seconds < 3600
        "#{seconds // 60}m"
      elsif seconds < 86400
        "#{seconds // 3600}h"
      else
        "#{seconds // 86400}d"
      end
    end

    # Format bytes in human-readable format
    def self.format_bytes(bytes : Int) : String
      units = ["B", "KB", "MB", "GB", "TB"]
      size = bytes.to_f
      unit_index = 0

      while size >= 1024 && unit_index < units.size - 1
        size /= 1024
        unit_index += 1
      end

      "#{size.round(1)}#{units[unit_index]}"
    end

    # Format a timestamp relative to now
    def self.time_ago(time : Time) : String
      now = Time.utc
      diff = now - time

      if diff.total_seconds < 60
        "just now"
      elsif diff.total_seconds < 3600
        minutes = diff.total_minutes.to_i
        "#{minutes}m ago"
      elsif diff.total_seconds < 86400
        hours = diff.total_hours.to_i
        "#{hours}h ago"
      elsif diff.total_days < 7
        days = diff.total_days.to_i
        "#{days}d ago"
      else
        time.to_s("%Y-%m-%d")
      end
    end

    # Highlight differences between two strings
    def self.highlight_diff(old_text : String, new_text : String) : String
      return new_text if old_text == new_text

      # Simple implementation - mark changed parts
      if old_text.empty?
        "<ins>#{new_text}</ins>"
      elsif new_text.empty?
        "<del>#{old_text}</del>"
      else
        # For now, just show the new value
        # A more sophisticated implementation would show actual diffs
        new_text
      end
    end

    # Escape HTML entities
    def self.escape_html(text : String) : String
      text.gsub("&", "&amp;")
        .gsub("<", "&lt;")
        .gsub(">", "&gt;")
        .gsub("\"", "&quot;")
        .gsub("'", "&#39;")
    end

    # Convert to title case
    def self.title_case(text : String) : String
      text.split('_')
        .map(&.capitalize)
        .join(" ")
    end

    # Generate a color based on string hash (for consistent coloring)
    def self.string_to_color(text : String, saturation : Int32 = 70, lightness : Int32 = 50) : String
      hash = text.hash.abs
      hue = hash % 360
      "hsl(#{hue}, #{saturation}%, #{lightness}%)"
    end
  end
end
