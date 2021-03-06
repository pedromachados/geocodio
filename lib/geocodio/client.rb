require 'net/http'
require 'json'
require 'cgi'

require 'geocodio/client/error'
require 'geocodio/client/response'
require 'geocodio/utils'

module Geocodio
  class Client
    include Geocodio::Utils

    CONTENT_TYPE = 'application/json'
    METHODS = {
      :get    => Net::HTTP::Get,
      :post   => Net::HTTP::Post,
      :put    => Net::HTTP::Put,
      :delete => Net::HTTP::Delete
    }
    HOST = 'api.geocod.io'
    BASE_PATH = '/v1'
    PORT = 80

    def initialize(api_key = ENV['GEOCODIO_API_KEY'])
      @api_key = api_key
    end

    # Geocodes one or more addresses. If one address is specified, a GET request
    # is submitted to http://api.geocod.io/v1/geocode. Multiple addresses will
    # instead submit a POST request.
    #
    # @param addresses [Array<String>] one or more String addresses
    # @return [Geocodio::Address, Array<Geocodio::AddressSet>] One or more Address Sets
    def geocode(*addresses)
      addresses = addresses.first if addresses.first.is_a?(Array)

      if addresses.size < 1
        raise ArgumentError, 'You must provide at least one address to geocode.'
      elsif addresses.size == 1
        geocode_single(addresses.first)
      else
        geocode_batch(addresses)
      end
    end

    # Reverse geocodes one or more pairs of coordinates. Coordinate pairs may be
    # specified either as a comma-separated "latitude,longitude" string, or as
    # a Hash with :lat/:latitude and :lng/:longitude keys. If one pair of
    # coordinates is specified, a GET request is submitted to
    # http://api.geocod.io/v1/reverse. Multiple pairs of coordinates will
    # instead submit a POST request.
    #
    # @param coordinates [Array<String>, Array<Hash>] one or more pairs of coordinates
    # @return [Geocodio::Address, Array<Geocodio::AddressSet>] One or more Address Sets
    def reverse_geocode(*coordinates)
      coordinates = coordinates.first if coordinates.first.is_a?(Array)

      if coordinates.size < 1
        raise ArgumentError, 'You must provide coordinates to reverse geocode.'
      elsif coordinates.size == 1
        reverse_geocode_single(coordinates.first)
      else
        reverse_geocode_batch(coordinates)
      end
    end
    alias :reverse :reverse_geocode

    # Sends a GET request to http://api.geocod.io/v1/parse to correctly dissect
    # an address into individual parts. As this endpoint does not do any
    # geocoding, parts missing from the passed address will be missing from the
    # result.
    #
    # @param address [String] the full or partial address to parse
    # @return [Geocodio::Address] a parsed and formatted Address
    def parse(address)
      Address.new get('/parse', q: address).body
    end

    private

      METHODS.each do |method, _|
        define_method(method) do |path, params = {}, options = {}|
          request method, path, options.merge(params: params)
        end
      end

      def geocode_single(address)
        response  = get '/geocode', q: address
        addresses = parse_results(response)

        AddressSet.new(address, *addresses)
      end

      def reverse_geocode_single(pair)
        pair = normalize_coordinates(pair)

        response  = get '/reverse', q: pair
        addresses = parse_results(response)

        AddressSet.new(pair, *addresses)
      end

      def geocode_batch(addresses)
        response = post '/geocode', {}, body: addresses

        parse_nested_results(response)
      end

      def reverse_geocode_batch(pairs)
        pairs.map! { |pair| normalize_coordinates(pair) }
        response = post '/reverse', {}, body: pairs

        parse_nested_results(response)
      end

      def request(method, path, options)
        path += "?api_key=#{@api_key}"

        if params = options[:params] and !params.empty?
          q = params.map { |k, v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }
          path += "&#{q.join('&')}"
        end

        req = METHODS[method].new(BASE_PATH + path, 'Accept' => CONTENT_TYPE)

        if options.key?(:body)
          req['Content-Type'] = CONTENT_TYPE
          req.body = options[:body] ? JSON.dump(options[:body]) : ''
        end

        http = Net::HTTP.new HOST, PORT
        res  = http.start { http.request(req) }

        case res
        when Net::HTTPSuccess
          return Response.new(res)
        else
          raise Error, res
        end
      end
  end
end
