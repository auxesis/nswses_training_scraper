require "octokit"
require "faraday/follow_redirects"

client = Octokit::Client.new

# Find the latast asset
assets = client.latest_release("auxesis/nswses_training_scraper").assets
latest_scrape = assets.sort_by(&:created_at).last

# Download the asset
connection = Faraday.new do |faraday|
  faraday.response :follow_redirects
  faraday.adapter Faraday.default_adapter
end

response = connection.get(latest_scrape.browser_download_url)
length = File.write("data.sqlite", response.body)

puts "Wrote #{length / 1024}Kb from #{latest_scrape.browser_download_url}"
