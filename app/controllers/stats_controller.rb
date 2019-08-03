class StatsController < ApplicationController
  def show
    @key = params.fetch(:id)
    range = RANGES[params[:range] || "3months"]

    if params[:range] == "1year"
      data = Stat.weekly_data(@key, range)
      date_totals = Stat.weekly_totals(@key, range)
    else
      data = Stat.daily_data(@key, range)
      date_totals = Stat.daily_totals(@key, range)
    end

    if params[:total]
      points =
        date_totals.map do |date, count|
          { x: date.strftime("%m/%d"), y: count }
        end
      @series = [{ name: "total", data: points }]
      @total = true
    else
      dates = data.map(&:first).sort.uniq
      count_map = count(data)

      # Build one series for each version, with an entry for every date
      #
      # [ {name: "2.2.2", data: [{x: "2018-07-13", y: 3932}, ...] }, ... ]
      versions = count_map.values.flat_map(&:keys).compact.sort.uniq
      top =
        versions.max_by(MAXES[@key]) do |v|
          count_map[count_map.keys.last][v] || 0
        end

      top_series =
        top.map do |version|
          points =
            dates.map do |date|
              count = count_map.dig(date, version) || 0
              y = (count.to_f / date_totals[date]) * 100
              { x: date.strftime("%m/%d"), y: y }
            end

          { name: "#{@key} #{version}", data: points }
        end

      if top.length < versions.length
        the_rest = {
          name: "Others",
          data:
            dates.map do |date|
              count = count_map[date].reject { |v| v.in?(top) }.sum { |v, c| c }
              y = (count.to_f / date_totals[date]) * 100
              # TODO: Move the formatting to JS
              { x: date.strftime("%m/%d"), y: y }
            end
        }
      end

      @series = the_rest ? top_series.push(the_rest) : top_series
    end

    respond_to do |format|
      format.json { render json: @series }
      format.js
    end
  end

  private

  RANGES = {
    "1year" => Date.today - 1.year,
    "3months" => Date.today - 90.days,
    "1month" => Date.today - 30.days,
    "2weeks" => Date.today - 2.weeks
  }
  RANGES.default = Date.today - 90.days

  MAXES = { "ci" => 7 }
  MAXES.default = 10

  def count(data)
    # Build a hash of hashes we can use to look up values for a specific date
    count_map = Hash.new { |h, k| h[k] = {} }
    data.each { |date, version, count| count_map[date][version] = count }
    count_map
  end
end
