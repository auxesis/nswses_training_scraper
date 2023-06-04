require "scraperwiki"
require "mechanize"
require "addressable"
require "reverse_markdown"
require "active_support/core_ext/hash"

def agent
  @agent ||= Mechanize.new
end

def base_url
  "https://nswses.axcelerate.com.au"
end

def all_zones
  return @zones if @zones
  @zones = []

  course_zones_url = "#{base_url}/course-by-zones/"
  response = agent.get(course_zones_url)

  zone_buttons = response.search("div.elementor-widget-wrap a.elementor-button-link")
  if zone_buttons.empty?
    puts "[ERROR] No zone buttons. Courses by Zone page format has changed?"
    exit(2)
  end

  zone_buttons.each do |button|
    @zones << {
      id: button.attribute("href").value[1..-2],
      name: button.text.strip,
    }
  end

  @zones.uniq!
  @zones
end

def all_course_urls
  return @urls if @urls
  @urls = []

  field_operations_categories = %w[foundation-level technical-level leadership-field]
  incident_management_categories = %w[foundation-imt technical-imt leadership-imt]
  categories = field_operations_categories + incident_management_categories

  categories.each do |category|
    category_url = "#{base_url}/#{category}/"
    response = agent.get(category_url)
    course_urls = response.search("div.ax-course-list div.ax-course-list-record a.ax-course-detail-link").map { |a| base_url + a.attribute("href").value }
    @urls += course_urls
    puts "[INFO] Scraped #{course_urls.size} courses in #{category} category"
  end

  @urls.uniq!
  @urls
end

def extract_course_entry_requirements(response)
  case
  when (benefits = response.search(".ax-cd-program-benefits .ax-course-content-list")).any?
    ReverseMarkdown.convert(benefits.first.to_html)
  else
    puts "[INFO] No course entry requirements on #{response.uri.to_s}"
  end
end

def extract_course_workshops_from_tables(containers, zone, course_id)
  containers.search("table tr").each_with_index.map do |row, i|
    next if i == 0 # skip table header, no tbody :-(
    workshop = {
      id: Addressable::URI.parse(row.search(".ax-course-button a").first.attribute("href").value).query_values["instance_id"].to_i,
      name: row.search("td.instance_name").text,
      date_freetext: row.search("td.instance_date").text,
      time_freetext: row.search("td.instance_time").text,
      location: row.search("td.instance_location").text,
      vacancy: row.search("td.instance_vacancy").text.to_i,
      zone: zone,
      course_id: course_id,
    }
  end
end

def extract_course_workshops(response)
  zones = response.search(".elementor-tabs .elementor-tabs-wrapper .elementor-tab-title").map(&:text)
  zone_workshop_containers = response.search(".elementor-tabs .elementor-tab-content")

  if zones.size != zone_workshop_containers.size
    puts "[ERROR] zone workshop containers different to total zones (expected #{zones.size}, got #{zone_workshop_containers.size}"
    exit(2)
  end

  course_id = Addressable::URI.parse(response.uri).query_values["course_id"].to_i
  all_workshops_count = 0
  workshops = []
  zone_workshop_containers.each_with_index do |containers, index|
    if zones[index] == "All Locations" # skip the All Locations view, because we can't work out the zone
      if containers.search("table tr").any?
        all_workshops_count = containers.search("table tr").size - 1
      end
      next
    end
    next unless containers.search("table tr").any? # no workshops in the current zone
    workshops += extract_course_workshops_from_tables(containers, zones[index], course_id).compact
  end

  if all_workshops_count != workshops.size
    puts "[INFO] All workshops count (#{all_workshops_count}) different to zone total (#{workshops.size}) for course #{course_id}"
    all_locations_container_index = zones.index("All Locations")
    containers = zone_workshop_containers[all_locations_container_index]
    all_locations_workshops = extract_course_workshops_from_tables(containers, "All Locations", course_id).compact
    workshops_without_zones = all_locations_workshops.map { |w| w.except(:zone) } - workshops.map { |w| w.except(:zone) }
    workshops += workshops_without_zones
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

def scrape_workshop_dates(zones)
  workshop_dates = []
  zones.each do |zone|
    zone_courses_url = "#{base_url}/#{zone[:id]}/"
    response = agent.get(zone_courses_url)
    puts "[INFO] Scraping precise workshop dates for: #{zone[:name]}"

    container = response.search("div.ax-course-instance-list.ax-table").first # first should be All <zone> Courses
    container.search("tr").each_with_index.map do |row, i|
      next if i == 0 # skip table header, no tbody :-(
      workshop_query_parameters = Addressable::URI.parse(row.search(".ax-course-button a").first.attribute("href").value).query_values
      instance_id = workshop_query_parameters["instance_id"].to_i
      course_id = workshop_query_parameters["course_id"].to_i
      start_date = row.search("td.instance_start").text.strip
      start_date = start_date.empty? ? nil : Date.parse(start_date)
      finish_date = row.search("td.instance_finish").text.strip
      finish_date = finish_date.empty? ? nil : Date.parse(finish_date)
      workshop = {
        id: instance_id,
        start_date: start_date,
        finish_date: finish_date,
        zone: zone[:id],
        course_id: course_id,
      }
      workshop_dates << workshop
    end
  end
  workshop_dates
end

def enrich_workshop_dates(workshops, workshop_dates)
  enriched_workshops = []
  workshops.map!(&:symbolize_keys!) # FIXME:remove once no longer developing
  workshops.each do |workshop|
    precise_date = workshop_dates.find { |d| d[:id] == workshop[:id] }
    if not precise_date
      puts "[INFO] No precise date for workshop #{workshop[:id]} (#{workshop[:name]})"
      next
    end
    enriched_workshops << workshop.merge(precise_date)
  end
  enriched_workshops
end

def main
  zones = all_zones
  puts "[INFO] Scraped #{zones.size} zones"
  ScraperWiki.save_sqlite(%i[id], zones, "zones")

  urls = all_course_urls
  puts "[INFO] Scraping #{urls.size} courses"

  courses = urls.map do |course_url|
    puts "[INFO] Scraping #{course_url}"
    scrape_course(course_url)
  end

  workshop_dates = scrape_workshop_dates(zones)

  normalised_courses = courses.map { |c| c.except(:workshops) }
  workshops = courses.map { |c| c[:workshops] }.flatten
  workshops = enrich_workshop_dates(workshops, workshop_dates)

  ScraperWiki.save_sqlite(%i[id], normalised_courses, "courses")
  ScraperWiki.save_sqlite(%i[id], workshops, "workshops")

  puts "[INFO] Courses saved: #{normalised_courses.size}"
  puts "[INFO] Workshops saved: #{workshops.size}"
end

main() if $PROGRAM_NAME == $0
