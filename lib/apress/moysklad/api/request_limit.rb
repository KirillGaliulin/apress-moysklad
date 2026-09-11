module Apress
  module Moysklad
    module Api
      class RequestLimit
        REQUEST_COST = 4
        DEFAULT_RESET_TIME = 3_000
        LIMIT_TTL = 300

        attr_reader :headers, :login

        def initialize(headers, login)
          @headers = headers
          @login = login.to_s
        end

        def call
          update_limit
          return if current_limit >= REQUEST_COST

          sleep(calculate_sleep_time)
        end

        private

        # Время через которое можно начать следующую пачку запросов
        #   См. документацию https://dev.moysklad.ru/doc/api/remap/1.2/#/general#1-mojsklad-json-api
        #   X-Lognex-Reset - время до сброса ограничения в миллисекундах. Равно нулю, если ограничение не установлено
        #   X-Lognex-Retry-After - время до сброса ограничения в миллисекундах.
        #   X-Lognex-Retry-TimeInterval - интервал в миллисекундах, в течение которого можно сделать эти запросы
        def calculate_sleep_time
          reset_ms = headers['x-lognex-reset'].to_i
          retry_after_ms = headers['x-lognex-retry-after'].to_i
          retry_interval_ms = headers['x-lognex-retry-timeinterval'].to_i

          reset_time = if reset_ms > 0
                         reset_ms
                       elsif retry_after_ms > 0
                         retry_after_ms
                       elsif retry_interval_ms > 0
                         retry_interval_ms
                       else
                         DEFAULT_RESET_TIME
                       end

          reset_time / 1_000
        end

        # Число запросов, которые можно отправить до получения 429 ошибки
        def rate_limit
          headers['x-ratelimit-remaining']&.to_i || 0
        end

        # Текущее количество запросов, берёт данные из редиса.
        #
        # Returns Integer
        def current_limit
          redis.get(redis_key).to_i
        end

        # Обновление лимитов запросов
        def update_limit
          redis.multi do |pipeline|
            pipeline.set(redis_key, rate_limit)
            pipeline.expire(redis_key, LIMIT_TTL)
          end
        end

        # Оставляем только буквы в логине, преобразуя спецсимволы в _
        def redis_key
          prepared_login = login.gsub(/[^a-zA-Z0-9_-]/, '_')
          "moysklad:rate_limit:#{prepared_login}"
        end

        def redis
          @redis ||= ::Services::Redis.instance
        end
      end
    end
  end
end
