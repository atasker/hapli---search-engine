require 'nokogiri'
require 'rest_client'
require 'domainatrix'
require 'cgi'
require 'net/http'
require 'json'
require 'set'
require 'csv'
require 'pry'

@frontier_next_limit = 0
@visited_next_limit = 0
@frontier = Set.new
@frontier << "http://www.dmoz.org"
@visited = Set.new

# adding previously collected urls to frontier set
CSV.foreach("frontier.csv") do |row|
  @frontier.add?(row)
  @frontier_next_limit += 1
end

# adding previously visited urls to visited set
CSV.foreach("visited.csv") do |row|
  @visited.add?(row)
  @visited_next_limit += 1
end

# this method interacts with elasticsearch and indexes pages
def index_page(url, page, links)
  Net::HTTP.start("localhost", 9200) do |http|
    encoded_url = CGI.escape(url)
    request = Net::HTTP::Put.new("/my_crawl/page/#{encoded_url}")
    request.body = {
      "text" => page.text,
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
  if url.class != Array # to ignore inadvertently passing in arrays
    page = nokogiri(url)
    links = get_links(page)

    # index_page(url, page, links) # unless already indexed
    # figure out what the &%^* do to with this ^^

    links.each do |link|
      unless link["href"] == nil || link["href"].empty? || link["href"].include?("?") || link["href"].include?("javascript:void") || link["href"].include?("mailto:") || link["href"].scan(/%/).size > 3 || link["href"].include?("news:")
        sanitized = sanitize(url, link["href"])
        @frontier << sanitized
        delete_empty(@frontier)
      end
    end
    visited_in(url)
    system('clear')
    puts
    puts
    puts "-------------URLS to be crawled #{@frontier.size}-------------"
    puts "-------------URLS already crawled #{@visited.size}-------------"
    puts "-------------Selection from frontier:-------------"
    puts "#{@frontier.to_a.sample}"
    puts "#{@frontier.to_a.sample}"
    puts "#{@frontier.to_a.sample}"
    puts "#{@frontier.to_a.sample}"
    check_size
  end
  crawl(find_next) # if not already in bloom
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
  # insert canonicalized url into bloom filter
  canon = canonicalize(url)

  if !canon.nil?
    @visited.add(canon)
  end
end

def nokogiri(url)
  Nokogiri::HTML(RestClient.get(url){ |response, request, result, &block|
  case response.code
  when 404
    puts "404 not found error"
    response
  when 408
    puts "408 timeout"
    response
  when 403
    puts "403 forbidden"
    response
  else
    response.return!(request, result, &block)
  end
  })
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

crawl(@frontier.take(1)[0])

# count in-link counts for every url added to frontier
