# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module ActiveAdmin
  module Oidc
    # Thin wrapper around the OIDC discovery document
    # (`.well-known/openid-configuration`). Does its own HTTP fetch so the
    # gem can expose a normalized interface and error type independent of
    # `omniauth_openid_connect`'s internals.
    class Discovery
      DISCOVERY_PATH = "/.well-known/openid-configuration"

      def initialize(config)
        @config = config
      end

      def document
        @document ||= fetch_and_validate!
      end

      def authorization_endpoint(override: nil)
        override || document.fetch("authorization_endpoint")
      end

      def token_endpoint(override: nil)
        override || document.fetch("token_endpoint")
      end

      def userinfo_endpoint(override: nil)
        override || document.fetch("userinfo_endpoint")
      end

      def jwks_uri(override: nil)
        override || document.fetch("jwks_uri")
      end

      def end_session_endpoint(override: nil)
        override || document["end_session_endpoint"]
      end

      def issuer
        document.fetch("issuer")
      end

      private

      attr_reader :config

      def fetch_and_validate!
        body = fetch_body
        doc  = parse_json(body)
        verify_issuer!(doc)
        doc
      end

      def fetch_body
        uri = URI.join(ensure_trailing_slash(config.issuer), DISCOVERY_PATH.sub(%r{^/}, ""))
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = config.timeout
        http.read_timeout = config.timeout

        response = http.request(Net::HTTP::Get.new(uri.request_uri))
        unless response.is_a?(Net::HTTPSuccess)
          raise DiscoveryError, "Discovery failed with HTTP #{response.code}"
        end

        response.body
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        raise DiscoveryError, "Discovery timed out: #{e.message}"
      rescue SocketError, Errno::ECONNREFUSED => e
        raise DiscoveryError, "Discovery connection failed: #{e.message}"
      end

      def parse_json(body)
        JSON.parse(body)
      rescue JSON::ParserError => e
        raise DiscoveryError, "Discovery returned invalid JSON: #{e.message}"
      end

      def verify_issuer!(doc)
        discovered = doc["issuer"].to_s
        configured = config.issuer.to_s
        return if discovered == configured

        raise DiscoveryError,
              "Discovery issuer mismatch: document said #{discovered.inspect}, " \
              "config expected #{configured.inspect}"
      end

      def ensure_trailing_slash(url)
        url.to_s.end_with?("/") ? url : "#{url}/"
      end
    end
  end
end
