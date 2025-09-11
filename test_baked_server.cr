#!/usr/bin/env crystal

require "http/client"

# Start the baked server in background
puts "Starting baked server..."
Process.run("./bin/mangrullo-web-baked", output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)

# Give it time to start
sleep 2

begin
  # Test CSS file
  puts "\nTesting /css/dashboard.css..."
  response = HTTP::Client.get("http://localhost:3000/css/dashboard.css")
  puts "Status: #{response.status_code}"
  puts "Content-Type: #{response.headers["Content-Type"]?}"
  puts "Content-Length: #{response.headers["Content-Length"]?}"
  puts "First 100 chars: #{response.body[0..100]}"

  # Test JS file
  puts "\nTesting /js/dashboard.js..."
  response = HTTP::Client.get("http://localhost:3000/js/dashboard.js")
  puts "Status: #{response.status_code}"
  puts "Content-Type: #{response.headers["Content-Type"]?}"
  puts "Content-Length: #{response.headers["Content-Length"]?}"
  puts "First 100 chars: #{response.body[0..100]}"

  # Test auto-refresh JS
  puts "\nTesting /js/auto-refresh.js..."
  response = HTTP::Client.get("http://localhost:3000/js/auto-refresh.js")
  puts "Status: #{response.status_code}"
  puts "Content-Type: #{response.headers["Content-Type"]?}"
  puts "Content-Length: #{response.headers["Content-Length"]?}"
  puts "First 100 chars: #{response.body[0..100]}"

  # Test main page
  puts "\nTesting /..."
  response = HTTP::Client.get("http://localhost:3000/")
  puts "Status: #{response.status_code}"
  puts "Content-Type: #{response.headers["Content-Type"]?}"
  puts "Contains 'Auto-refresh: ON': #{response.body.includes?("Auto-refresh: ON")}"
  puts "Contains '/js/dashboard.js': #{response.body.includes?("/js/dashboard.js")}"
  puts "Contains '/js/auto-refresh.js': #{response.body.includes?("/js/auto-refresh.js")}"

rescue ex
  puts "Error: #{ex.message}"
ensure
  # Kill the server
  `pkill -f mangrullo-web-baked`
  puts "\nServer stopped"
end