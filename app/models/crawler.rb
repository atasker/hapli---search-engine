class Crawler < ActiveRecord::Base

  AVOID = ["?", "javascript:void", "mailto:", "news:", "|||", "&", "/cgi-bin/"]
  BADEXT = %w(.pdf .doc .xls .ppt .mp3 .m4v .avi .mpg .rss .xml .json .txt .git .zip .md5 .asc .jpg .gif .png)

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
    @frontier << "http://www.kidsolr.com/"
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
      Net::HTTP.start("localhost", 9200) do |http|
        encoded_url = CGI::escape(url).force_encoding('UTF-8')
        request = Net::HTTP::Put.new("/hapli_search/page/#{encoded_url}")
        request.body = {
          "text" => strip_tags(page.text), #force encoding
          "links" => links
        }.to_json

        request.content_type = "application/json"
        http.request(request)
    end
  end

  def frontier_csv(data)
    File.open("./web_crawler/frontier.csv", "wb") do |csv|
        csv.write(data.join("\n"))
    end
  end

  def visited_csv(data)
    File.open("./web_crawler/visited.csv", "wb") do |csv|
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
    if already_visited(url) || find_bad_extensions(url)
      crawl(find_next)
    else
      if url.class != Array # to ignore inadvertently passing in arrays
        page = nokogiri(url)
        links = get_links(page)
        link_array = []
        links.each do |link|
          unless AVOID.include?(link["href"]) || link["href"] == nil || link["href"].empty? || link["href"].scan(/%/).size > 3
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
      crawl(find_next)
    end
  end

  # extract all <a> links from page

  def get_links(page)
    unless page == [] || page.class == nil
      page.css("a")
    end
  end

  # ignore urls that end with certain extensions

  def find_bad_extensions(url)
    BADEXT.each do |ext|
      if url.end_with?(ext)
        return true
      end
    end
    false
  end

  # find next url in frontier that is not already in visited set

  def find_next
    first = @frontier.take(1)
    @frontier.subtract(first)
    @frontier.take(1)[0]
  end

  # determine if url has already been visited

  def already_visited(url)
    canon = canonicalize(url)
    @visited.include?(canon)
  end

  # insert canonicalized url into visited set

  def visited_in(url)
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
    if link =~ (/^\//) || !link.start_with?("www") && !link.start_with?("http")
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
