module Mangrullo
  # Job queue for managing container update operations
  class UpdateJobQueue
    @@instance : UpdateJobQueue?

    # Job status enum
    enum JobStatus
      Pending
      Running
      Completed
      Failed
    end

    # Job structure
    struct UpdateJob
      property id : String
      property container_id : String
      property container_name : String
      property allow_major : Bool
      property status : JobStatus
      property created_at : Time
      property started_at : Time?
      property completed_at : Time?
      property error : String?
      property result : Hash(String, JSON::Any)?

      def initialize(@container_id : String, @container_name : String, @allow_major : Bool)
        @id = UUID.random.to_s
        @status = JobStatus::Pending
        @created_at = Time.utc
        @started_at = nil
        @completed_at = nil
        @error = nil
        @result = nil
      end

      def to_h
        {
          id:             @id,
          container_id:   @container_id,
          container_name: @container_name,
          allow_major:    @allow_major,
          status:         @status.to_s.downcase,
          created_at:     @created_at.to_rfc3339,
          started_at:     @started_at.try(&.to_rfc3339),
          completed_at:   @completed_at.try(&.to_rfc3339),
          error:          @error,
          result:         @result,
        }
      end
    end

    def self.instance
      @@instance ||= new
    end

    def initialize
      @pending_jobs = Deque(UpdateJob).new
      @active_jobs = Hash(String, UpdateJob).new  # For tracking active jobs by ID
      @mutex = Mutex.new
      @worker_running = false
      start_worker
    end

    # Add a new update job to the queue
    def enqueue_update(container_id : String, container_name : String, allow_major : Bool = false) : String
      job = UpdateJob.new(container_id, container_name, allow_major)

      @mutex.synchronize do
        @pending_jobs.push(job)
        Log.info { "Update job queued for container #{container_name} (ID: #{job.id})" }
      end

      job.id
    end

    # Get job status
    def get_job(job_id : String) : UpdateJob?
      @mutex.synchronize do
        @active_jobs[job_id]? || @pending_jobs.find { |job| job.id == job_id }
      end
    end

    # Get all jobs
    def all_jobs : Array(UpdateJob)
      @mutex.synchronize do
        (@pending_jobs.to_a + @active_jobs.values).to_a
      end
    end

    # Get jobs for a specific container
    def get_container_jobs(container_id : String) : Array(UpdateJob)
      @mutex.synchronize do
        all_jobs.select { |job| job.container_id == container_id }
      end
    end

    # Cancel a pending job
    def cancel_job(job_id : String) : Bool
      @mutex.synchronize do
        if job = @jobs[job_id]?
          if job.status == JobStatus::Pending
            job.status = JobStatus::Failed
            job.error = "Job cancelled"
            job.completed_at = Time.utc
            Log.info { "Update job cancelled for container #{job.container_name} (ID: #{job.id})" }
            return true
          end
        end
        false
      end
    end

    # Clean up completed jobs older than specified seconds
    def cleanup_old_jobs(older_than_seconds : Int = 3600)
      cutoff_time = Time.utc - older_than_seconds.seconds

      @mutex.synchronize do
        # Note: With deque-based implementation, jobs are automatically removed
        # when completed/failed, so this method is now a no-op
        # Kept for API compatibility
      end
    end

    private def start_worker
      return if @worker_running

      @worker_running = true

      spawn do
        Log.debug { "Update job queue worker started" }

        while @worker_running
          process_next_job
          sleep 0.5.seconds # Check for new jobs every 500ms
        end
      end
    end

    private def process_next_job
      job = @mutex.synchronize do
        # Get the next job from the front of the queue
        next_job = @pending_jobs.shift?

        if next_job
          next_job.status = JobStatus::Running
          next_job.started_at = Time.utc
          @active_jobs[next_job.id] = next_job
          Log.info { "Starting update job for container #{next_job.container_name} (ID: #{next_job.id})" }
        end

        next_job
      end

      return unless job

      begin
        # Execute the update
        result = execute_update(job)

        @mutex.synchronize do
          job.status = JobStatus::Completed
          job.completed_at = Time.utc
          job.result = result
          Log.info { "Update job completed for container #{job.container_name} (ID: #{job.id})" }
          # Remove completed job from active tracking
          @active_jobs.delete(job.id)
        end
      rescue ex
        @mutex.synchronize do
          job.status = JobStatus::Failed
          job.completed_at = Time.utc
          job.error = ex.message
          Log.error { "Update job failed for container #{job.container_name} (ID: #{job.id}): #{ex.message}" }
          # Remove failed job from active tracking
          @active_jobs.delete(job.id)
        end
      end
    end

    private def execute_update(job : UpdateJob) : Hash(String, JSON::Any)
      # Get the update manager
      state_manager = StateManager.instance
      docker_client = state_manager.docker_client
      update_manager = UpdateManager.new(docker_client)

      # Get container info
      container_info = docker_client.get_container_info(job.container_id)
      raise "Container not found" unless container_info

      # Execute the update
      result = update_manager.update_container(container_info, job.allow_major)

      # If container was recreated with a new ID, remove the old container from state
      if result[:new_container_id] && result[:new_container_id] != job.container_id
        Mangrullo::ContainerState.instance.remove_container(job.container_id)
        # Add the new container back to the state immediately
        new_id = result[:new_container_id]
        if new_id
          Mangrullo::StateManager.instance.force_update_container(new_id)
        end
      end

      # Convert to JSON-friendly format
      {
        "container_id"     => JSON::Any.new(result[:container].id),
        "new_container_id" => result[:new_container_id] ? JSON::Any.new(result[:new_container_id].not_nil!) : JSON::Any.new(nil),
        "updated"          => JSON::Any.new(result[:updated]),
        "error"            => result[:error] ? JSON::Any.new(result[:error].not_nil!) : JSON::Any.new(nil),
      }
    end

    def stop
      @worker_running = false
    end
  end
end

# Add UUID generation
struct UUID
  def self.random : String
    bytes = Bytes.new(16)
    Random::Secure.random_bytes(bytes)

    # Format as UUID v4
    String.build do |io|
      bytes[0, 4].each { |byte| io.printf "%02x", byte }
      io << '-'
      bytes[4, 2].each { |byte| io.printf "%02x", byte }
      io << '-'
      io.printf "%02x%02x", bytes[6] & 0x0f | 0x40, bytes[7]
      io << '-'
      io.printf "%02x%02x", bytes[8] & 0x3f | 0x80, bytes[9]
      io << '-'
      bytes[10, 6].each { |byte| io.printf "%02x", byte }
    end
  end
end
