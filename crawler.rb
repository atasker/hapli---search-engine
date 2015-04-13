require 'open-uri'
require 'nokogiri'
require 'rest_client'
require 'pry'
require 'domainatrix'
require 'net/http'
require 'cgi'
require 'json'
require 'set'

@frontier = Set.new
@frontier << "http://www.nytimes.com"
@set = Set.new

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

def crawl(url)
  page = nokogiri(url)
  links = get_links(page)

  # index_page(url, page, links)

  links.each do |link|
    unless link["href"] == nil || link["href"].empty? || link["href"].include?("?")
      sanitized = sanitize(url, link["href"])
      @frontier << sanitized
      delete_empty(@frontier)
    end
  end
  set_in(url)
  puts "URLS to be crawled #{@frontier.size}"
  puts "URLS already crawled #{@set.size}"
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

def already_visited(url)
  # determine if url has already been visited
  canon = canonicalize(url)
  @set.include?(canon) # refer to line 68
end

def set_in(url)
  # insert canonicalized url into bloom filter
  canon = canonicalize(url)

  if !canon.nil?
    @set.add(canon)
  end
end

def nokogiri(url)
  Nokogiri::HTML(RestClient.get(url))
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


# canonicalized urls in the bloom filter
# sanitized urls in the frontier

# choose a url
# crawl that url => array of child urls
# then crawl each element of the array
# then you'll logic to check if you want to
# crawl the children's children based on some
# criteria (# of links, etc.)

#need to separated visited and not visited urls
# downcase & canonicalize urls
# count in-link counts for every url added to frontier
