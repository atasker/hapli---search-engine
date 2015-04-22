class Crawler < ActiveRecord::Base

include ActionView::Helpers::SanitizeHelper

require 'rest_client'
require 'cgi'
require 'net/http'
require 'json'
require 'set'
require 'csv'

def initialize
  @frontier_next_limit = 0
  @visited_next_limit = 0
  @frontier = Set.new
  @frontier << "http://www.dmoz.org/Kids_and_Teens/"
  @visited = Set.new

  # adding previously collected urls to frontier set
  CSV.foreach("./web_crawler/frontier.csv") do |row|
    @frontier.add?(row[0])
    @frontier_next_limit += 1
  end

  # adding previously visited urls to visited set
  CSV.foreach("./web_crawler/visited.csv") do |row|
    @visited.add?(row[0])
    @visited_next_limit += 1
  end
end

def frontier
  @frontier
end

# this method interacts with elasticsearch and indexes pages
def index_page(url, page, links)
    # stripped = strip_tags(page.text) # further sanitize
    Net::HTTP.start("localhost", 9200) do |http|
      encoded_url = CGI::escape(url).force_encoding('UTF-8')
      request = Net::HTTP::Put.new("/hapli_search/page/#{encoded_url}")
      request.body = {
        "text" => page.text, #force encoding
        "links" => links
      }.to_json

      request.content_type = "application/json"
      http.request(request)
  end
end

def frontier_csv(data)
  File.open("frontier.csv", "wb") do |csv|
      csv.write(data.join("\n"))
  end
end

def visited_csv(data)
  File.open("visited.csv", "wb") do |csv|
    csv.write(data.join("\n"))
  end
end

def check_size
  if @frontier.size > @frontier_next_limit + 1000
    frontier_csv(@frontier.to_a)
    @frontier_next_limit += 1000
  end
  if @visited.size > @visited_next_limit + 1000
    visited_csv(@visited.to_a)
    @visited_next_limit += 1000
  end
end

def crawl(url)
  if already_visited(url)
    crawl(find_next)
  else
    if url.class != Array # to ignore inadvertently passing in arrays
      page = nokogiri(url)
      links = get_links(page)
      link_array = []
      links.each do |link|
        unless link["href"] == nil || link["href"].empty? || link["href"].include?("?") || link["href"].include?("javascript:void") || link["href"].include?("mailto:") || link["href"].scan(/%/).size > 3 || link["href"].include?("news:") || link["href"].include?("|||")
          sanitized = sanitize(url, link["href"])
          @frontier << sanitized
          link_array << sanitized
          delete_empty(@frontier)
        end
      end
      visited_in(url)
      system('clear')
      puts
      puts
      puts "-------------URLS to be crawled #{@frontier.size}-------------"
      puts "-------------URLS already crawled #{@visited.size}-------------"
      check_size
    end
    index_page(url, page, link_array) # unless already indexed
    crawl(find_next) # if not already in bloom
  end
end

def get_links(page)
  # extract all <a> links from page
  page.css("a")
end

def find_next
  # find next url in frontier that is not already in bloom
  first = @frontier.take(1)
  @frontier.subtract(first)
  @frontier.take(1)[0]
end

# need to use this
def already_visited(url)
  # determine if url has already been visited
  canon = canonicalize(url)
  @visited.include?(canon)
end

def visited_in(url)
  # insert canonicalized url into visited set
  canon = canonicalize(url)

  if !canon.nil?
    @visited.add(canon)
  end
end

def nokogiri(url)
  begin
    Nokogiri::HTML(RestClient.get(url){ |response, request, result, &block|
    error_codes = [404, 408, 403]
      if error_codes.include?(response.code)
        puts "error"
      else
        response.return!(request, result, &block)
      end
    })
    rescue URI::InvalidURIError => err
      puts err
  end
end

def delete_empty(array)
  array.reject! { |elem| elem == nil }
  array.reject! { |elem| elem.length < 5 }
end

def sanitize(root, link)
  sanitized = ""
  if link =~ (/^\//)
      sanitized << "#{root}#{link}"
    elsif link !~ (/^#/)
      sanitized << link
  end
  if sanitized.end_with?("/")
    sanitized.chop!
  end
  sanitized
end

def canonicalize(url)
  begin
    canon = Domainatrix.parse(url)
    canon.canonical
  rescue
    nil
  end
end

end
# count in-link counts for every url added to frontier
