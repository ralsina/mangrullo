module Mangrullo
  # Helper module for standardizing JSON responses in the web server
  module JsonResponseHelper
    # Send a successful JSON response
    def self.send_success(env, data = nil)
      env.response.content_type = Constants::HTTP::JSON_CONTENT_TYPE
      if data
        data.to_json
      else
        {success: true}.to_json
      end
    end

    # Send an error JSON response
    def self.send_error(env, message : String, status_code : Int32 = 500, details = nil)
      env.response.status_code = status_code
      env.response.content_type = Constants::HTTP::JSON_CONTENT_TYPE

      if details
        {error: message, details: details}.to_json
      else
        {error: message}.to_json
      end
    end

    # Send a JSON response with a job ID
    def self.send_job_response(env, job_id : String, container_id : String, status : String, message : String)
      env.response.content_type = Constants::HTTP::JSON_CONTENT_TYPE
      {
        job_id:       job_id,
        container_id: container_id,
        status:       status,
        message:      message,
      }.to_json
    end

    # Send a container update response
    def self.send_container_response(env, container_id : String, success : Bool, message : String? = nil)
      env.response.content_type = Constants::HTTP::JSON_CONTENT_TYPE

      if message
        {container_id: container_id, success: success, message: message}.to_json
      else
        {container_id: container_id, success: success}.to_json
      end
    end

    # Send a paginated response
    def self.send_paginated(env, data : Array, total : Int32, page : Int32, per_page : Int32)
      env.response.content_type = Constants::HTTP::JSON_CONTENT_TYPE
      {
        data:       data,
        pagination: {
          total:       total,
          page:        page,
          per_page:    per_page,
          total_pages: (total.to_f / per_page).ceil.to_i,
        },
      }.to_json
    end

    # Send a status response
    def self.send_status(env, status : String, message : String? = nil)
      env.response.content_type = Constants::HTTP::JSON_CONTENT_TYPE
      if message
        {status: status, message: message}.to_json
      else
        {status: status}.to_json
      end
    end
  end
end
