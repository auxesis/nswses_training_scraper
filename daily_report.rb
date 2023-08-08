require "scraperwiki"
require "terminal-table"

course_count = ScraperWiki.select("count(id) AS count FROM courses").first["count"]
workshop_count = ScraperWiki.select("count(id) AS count FROM workshops").first["count"]
imt_workshops = ScraperWiki.select("* FROM workshops WHERE course_id > 105769 AND course_id NOT IN (105788, 105789)")
wicc_workshops = ScraperWiki.select("* FROM workshops WHERE course_id = 105644 ORDER BY start_date")
new_workshops = ScraperWiki.select("* FROM workshops WHERE first_seen_at >= '#{(Date.today - 7).to_s}'")

def format(workshops, title:)
  keys = %w[name location date_freetext zone]
  filtered = workshops.map { |w| w.slice(*keys) }
  {
    title: title,
    headings: keys,
    rows: filtered.map(&:values),
  }
end

puts "Total courses: #{course_count}"
puts "Total workshops: #{workshop_count}"
puts
puts Terminal::Table.new(format(new_workshops, title: "New in last 7 days"))
puts
puts Terminal::Table.new(format(imt_workshops, title: "IMT workshops"))
puts
puts Terminal::Table.new(format(wicc_workshops, title: "WICC workshops"))
