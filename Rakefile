require File.expand_path('../config/application', __FILE__)

Rails.application.load_tasks

task crawl: :environment do
  hapli = Crawler.new
  hapli.crawl(hapli.frontier.take(1)[0])
end
