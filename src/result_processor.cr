require "./types"

module Mangrullo
  # Processing and summarizing container update results
  module ResultProcessor
    # Summary information for container operations
    struct Summary
      property total : Int32
      property updated : Int32
      property errors : Int32
      property up_to_date : Int32
      property error_messages : Array(String)

      def initialize(@total : Int32, @updated : Int32, @errors : Int32, @up_to_date : Int32, @error_messages : Array(String) = [] of String)
      end
    end

    # Generate a summary from results
    def self.generate_summary(results : Array(NamedTuple(container: ContainerInfo, updated: Bool, error: String?))) : Summary
      total = results.size
      updated = results.count { |result| result[:updated] }
      errors = results.count { |result| result[:error] }
      up_to_date = total - updated - errors

      error_messages = results
        .select { |result| result[:error] }
        .map { |result| "#{result[:container].name.lchop('/')}: #{result[:error]}" }

      Summary.new(total, updated, errors, up_to_date, error_messages)
    end

    # Generate a summary from unified results (includes dry run info)
    def self.generate_unified_summary(results : Array(NamedTuple(container: ContainerInfo, updated: Bool, error: String?, needs_update: Bool?, reason: String?))) : Summary
      total = results.size
      updated = results.count { |result| result[:updated] }
      errors = results.count { |result| result[:error] }
      up_to_date = total - updated - errors

      error_messages = results
        .select { |result| result[:error] }
        .map { |result| "#{result[:container].name.lchop('/')}: #{result[:error]}" }

      Summary.new(total, updated, errors, up_to_date, error_messages)
    end

    # Log errors from results
    def self.log_errors(results : Array(NamedTuple(container: ContainerInfo, updated: Bool, error: String?))) : Nil
      error_results = results.select { |result| result[:error] }

      if error_results.size > 0
        Log.error { "Some containers failed to update:" }
        error_results.each do |result|
          Log.error { "  #{result[:container].name.lchop('/')}: #{result[:error]}" }
        end
      end
    end

    # Log errors from unified results
    def self.log_unified_errors(results : Array(NamedTuple(container: ContainerInfo, updated: Bool, error: String?, needs_update: Bool?, reason: String?))) : Nil
      error_results = results.select { |result| result[:error] }

      if error_results.size > 0
        Log.error { "Some containers had errors:" }
        error_results.each do |result|
          Log.error { "  #{result[:container].name.lchop('/')}: #{result[:error]}" }
        end
      end
    end

    # Format summary for CLI display
    def self.format_summary_cli(summary : Summary) : String
      lines = [] of String

      lines << "Total containers: #{summary.total}"
      lines << "Updated: #{summary.updated}"
      lines << "Up to date: #{summary.up_to_date}"

      if summary.errors > 0
        lines << "Errors: #{summary.errors}"
      end

      lines.join(", ")
    end

    # Format summary for JSON response
    def self.format_summary_json(summary : Summary) : Hash(String, Int32 | Array(String))
      {
        "total"          => summary.total,
        "updated"        => summary.updated,
        "up_to_date"     => summary.up_to_date,
        "errors"         => summary.errors,
        "error_messages" => summary.error_messages,
      }
    end

    # Filter results by status
    def self.filter_by_status(results : Array(NamedTuple(container: ContainerInfo, updated: Bool, error: String?)), status : Symbol) : Array
      case status
      when :updated
        results.select { |result| result[:updated] }
      when :error
        results.select { |result| result[:error] }
      when :up_to_date
        results.select { |result| !result[:updated] && !result[:error] }
      else
        results
      end
    end

    # Filter unified results by status
    def self.filter_unified_by_status(results : Array(NamedTuple(container: ContainerInfo, updated: Bool, error: String?, needs_update: Bool?, reason: String?)), status : Symbol) : Array
      case status
      when :updated
        results.select { |result| result[:updated] }
      when :error
        results.select { |result| result[:error] }
      when :needs_update
        results.select { |result| result[:needs_update] }
      when :up_to_date
        results.select { |result| !result[:updated] && !result[:error] && !result[:needs_update] }
      else
        results
      end
    end

    # Get containers with specific status
    def self.get_containers_with_status(results : Array(NamedTuple(container: ContainerInfo, updated: Bool, error: String?)), status : Symbol) : Array(ContainerInfo)
      filter_by_status(results, status).map { |result| result[:container] }
    end

    # Get containers with specific status from unified results
    def self.get_containers_with_unified_status(results : Array(NamedTuple(container: ContainerInfo, updated: Bool, error: String?, needs_update: Bool?, reason: String?)), status : Symbol) : Array(ContainerInfo)
      filter_unified_by_status(results, status).map { |result| result[:container] }
    end
  end
end
