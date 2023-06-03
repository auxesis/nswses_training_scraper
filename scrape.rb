require "scraperwiki"
require "mechanize"
require "addressable"
require "reverse_markdown"

def agent
  @agent ||= Mechanize.new
end

def all_course_urls
  urls = []

  field_operations_categories = %w[foundation-level technical-level leadership-field]
  incident_management_categories = %w[foundation-imt technical-imt leadership-imt]
  categories = field_operations_categories + incident_management_categories

  base_url = "https://nswses.axcelerate.com.au"

  categories.each do |category|
    category_url = "#{base_url}/#{category}/"
    response = agent.get(category_url)
    course_urls = response.search("div.ax-course-list div.ax-course-list-record a.ax-course-detail-link").map { |a| base_url + a.attribute("href").value }
    urls += course_urls
    puts "[INFO] Scraped #{course_urls.size} courses in #{category} category"
  end

  urls
end

def extract_course_entry_requirements(response)
  case
  when (benefits = response.search(".ax-cd-program-benefits .ax-course-content-list")).any?
    ReverseMarkdown.convert(benefits.first.to_html)
  else
    puts "[INFO] No course entry requirements on #{response.uri.to_s}"
  end
end

def extract_course_workshops(response)
  zones = response.search(".elementor-tabs .elementor-tabs-wrapper .elementor-tab-title").map(&:text)
  zone_workshop_containers = response.search(".elementor-tabs .elementor-tab-content")

  if zones.size != zone_workshop_containers.size
    puts "[ERROR] zone workshop containers different to total zones (expected #{zones.size}, got #{zone_workshop_containers.size}"
    exit(2)
  end

  workshops = []
  zone_workshop_containers.each_with_index do |containers, index|
    next if zones[index] == "All Locations" # skip the All Locations view, because we can't work out the zone
    next unless containers.search("table tr").any? # no workshops in the current zone
    containers.search("table tr").each_with_index do |row, i|
      next if i == 0 # skip table header, no tbody :-(
      workshop = {
        name: row.search("td.instance_name").text,
        date: row.search("td.instance_date").text,
        time: row.search("td.instance_time").text,
        location: row.search("td.instance_location").text,
        vacancy: row.search("td.instance_vacancy").text,
        zone: zones[index],
        course_id: Addressable::URI.parse(response.uri).query_values["course_id"].to_i,
      }
      workshops << workshop
    end
  end
  workshops
end

def scrape_course(course_url)
  response = agent.get(course_url)
  {
    url: course_url,
    id: Addressable::URI.parse(course_url).query_values["course_id"].to_i,
    name: response.search(".ax-course-name").first.text.strip,
    code: response.search(".ax-course-code").first.text.strip,
    description: response.search(".ax-cd-description").first.text.strip,
    target_audience: response.search(".ax-cd-target .ax-course-introduction").first.text.strip,
    learning_outcomes: ReverseMarkdown.convert(response.search(".ax-cd-learning-outcomes .ax-course-content-list").first.text),
    course_content: ReverseMarkdown.convert(response.search(".ax-cd-learning-methods .ax-course-content-list").first.to_html),
    learning_methods: ReverseMarkdown.convert(response.search(".ax-cd-learning-methods .ax-course-introduction").first.to_html),
    course_entry_requirements: extract_course_entry_requirements(response),
    workshops: extract_course_workshops(response),
    scraped_at: Time.now,
  }
rescue => e
  binding.pry
end

def main
  urls = all_course_urls

  courses = urls.map do |course_url|
    puts "[INFO] Scraping #{course_url}"
    scrape_course(course_url)
  end

  normalised_courses = courses.map { |c| c.except(:workshops) }
  workshops = courses.map { |c| c[:workshops] }.flatten

  ScraperWiki.save_sqlite(%i[id], normalised_courses, "courses")
  ScraperWiki.save_sqlite(%i[course_id location date], workshops, "workshops")
end

main() if $PROGRAM_NAME == $0
