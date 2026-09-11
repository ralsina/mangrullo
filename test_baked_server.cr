#!/usr/bin/env crystal

require "http/client"

# Start the baked server in background
puts "Starting baked server..."
server = Process.new("./bin/mangrullo-web-baked", output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)

# Give it time to start
sleep 2

def check_response(response, path)
  puts "Status: #{response.status_code}"
  puts "Content-Type: #{response.headers["Content-Type"]?}"
  puts "Content-Length: #{response.headers["Content-Length"]?}"
  puts "First 100 chars: #{response.body[0..Math.min(100, response.body.size - 1)]}"
end

begin
  # Test Pico CSS
  puts "\nTesting /css/pico.min.css..."
  response = HTTP::Client.get("http://localhost:3000/css/pico.min.css")
  check_response(response, "/css/pico.min.css")

  # Test dashboard CSS
  puts "\nTesting /css/dashboard.css..."
  response = HTTP::Client.get("http://localhost:3000/css/dashboard.css")
  check_response(response, "/css/dashboard.css")

  # Test dashboard JS
  puts "\nTesting /js/dashboard.js..."
  response = HTTP::Client.get("http://localhost:3000/js/dashboard.js")
  check_response(response, "/js/dashboard.js")

  # Test main page
  puts "\nTesting /..."
  response = HTTP::Client.get("http://localhost:3000/")
  puts "Status: #{response.status_code}"
  puts "Content-Type: #{response.headers["Content-Type"]?}"
  puts "Contains 'Auto-refresh: ON': #{response.body.includes?("Auto-refresh: ON")}"
  puts "Contains '/css/dashboard.css': #{response.body.includes?("/css/dashboard.css")}"
  puts "Contains '/css/pico.min.css': #{response.body.includes?("/css/pico.min.css")}"
rescue ex
  puts "Error: #{ex.message}"
ensure
  # Kill the server
  server.kill
  puts "\nServer stopped"
end
