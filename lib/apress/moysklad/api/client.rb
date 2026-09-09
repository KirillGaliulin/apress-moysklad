# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'uri'

require 'oj'
require 'logger'

module Apress
  module Moysklad
    module Api
      # Клиент для взаимодействия с API МойСклад
      #
      # @example
      #   client = Apress::Moysklad::Api::Client.new('login', 'password')
      #
      #   client.get(:assortment, limit: 2)
      #   => {:context=>...}
      class Client
        API_URL = 'https://api.moysklad.ru/api/remap'
        API_VERSION = '1.2'

        TIMEOUT = 60 # seconds
        HEADERS = {
          'Accept-Encoding' => 'gzip',
        }.freeze

        attr_reader :login, :password

        def initialize(login, password)
          @login = login
          @password = password
        end

        def get(entity, params = {})
          uri = api_uri(entity)
          uri.query = URI.encode_www_form(params) unless params.empty?

          send_request(uri)
        end

        def send_request(uri)
          req = Net::HTTP::Get.new(uri)
          req.basic_auth login, password
          HEADERS.each do |header, value|
            req.add_field(header, value)
          end
          res = Net::HTTP.start(uri.hostname, uri.port, http_options) do |http|
            http.request(req)
          end

          logger.info "(#{login}) Request url: #{uri}. Response code - message: #{res.code} - #{res.msg}"

          parse_response(res)
        rescue StandardError => e
          logger.info "(#{login}) Request failed. Info: #{e.class} - #{e.message}"
          raise
        end

        def category_param_for_filter(category)
          "productFolder=#{api_uri('productfolder')}/#{category}"
        end

        private

        def api_uri(entity)
          URI "#{API_URL}/#{API_VERSION}/entity/#{entity}"
        end

        def http_options
          {
            open_timeout: TIMEOUT,
            read_timeout: TIMEOUT,
            use_ssl: true,
          }
        end

        def parse_response(res)
          headers = res.each_header.to_h
          is_success = res.is_a? Net::HTTPOK

          if !is_success && !headers['content-type'].to_s.include?('json')
            logger.info "(#{login}) Not code 200 and not json: #{res.msg}, #{res.code}, #{headers.inspect}"
            raise Api::Error.new(res.msg, res.code, headers)
          end

          response = Oj.load(res.body, symbol_keys: true, mode: :compat).tap do |data|
            if data.key? :errors
              err = data[:errors].first

              raise Api::Error.new(err[:error], err[:code])
            end

            unless is_success
              logger.info "(#{login}) Not code 200: #{res.msg}, #{res.code}, #{headers.inspect}"
              raise Api::Error.new(res.msg, res.code, headers)
            end
          end
          Api::RequestLimit.new(headers).call

          logger.info "(#{login}) Response headers: #{headers.inspect}"
          logger.info "(#{login}) Response body: #{response.inspect}"
          response
        end

        def logger
          @logger ||=
            ::Logger.new(File.join(Dir.pwd, 'log/moysklad_debug.log')).tap { |l| l.formatter = ::Logger::Formatter.new }
        end
      end
    end
  end
end
