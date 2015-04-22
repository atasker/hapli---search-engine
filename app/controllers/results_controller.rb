class ResultsController < ApplicationController


  def index
    @query = params[:q]

    Net::HTTP.start("localhost", 9200) do |http|
      @request = Net::HTTP::Get.new("/hapli_search/_search/?q=#{@query}")
      @response = http.request(@request)
    end

    @parsed = JSON.parse(@response.body)
    @hits = @parsed["hits"]["total"]
    @time = @parsed["hits"]["max_score"]
  end


end
