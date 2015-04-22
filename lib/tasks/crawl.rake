task crawl: :environment do
  hapli = Crawler.new
  hapli.crawl(hapli.frontier.take(1)[0])
end
