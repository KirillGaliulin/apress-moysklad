require 'logger'

module Apress
  module Moysklad
    module Api
      class RequestLimit
        REQUEST_COST = 4

        attr_reader :headers

        def initialize(headers)
          @headers = headers
        end

        def call
          return if rate_limit.nil? || rate_limit >= REQUEST_COST

          logger.info "Rate limit: #{rate_limit} < #{REQUEST_COST}"
          logger.info "Sleeping #{reset_time} secs"
          sleep(reset_time)
        end

        private

        def reset_time
          headers['x-lognex-reset'].to_f / 1_000
        end

        def rate_limit
          headers['x-ratelimit-remaining']&.to_i
        end

        def logger
          @logger ||= ::Logger.new(File.join(Dir.pwd, 'log/moysklad_debug.log'))
        end
      end
    end
  end
end
