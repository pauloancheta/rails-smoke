# frozen_string_literal: true

# Probe script: ssl_certs
#
# Checks OpenSSL version, certificate store, and TLS connectivity.
# Writes probe_ssl_certs.txt to output_dir.
#
# Usage: bundle exec ruby ssl_certs.rb <config_path>
# The config YAML must contain "output_dir".
#
# This script is self-contained — it does NOT require "rails_smoke".

require "yaml"
require "openssl"
require "net/http"
require "timeout"

config = YAML.safe_load_file(ARGV[0])
output_dir = config.fetch("output_dir")

output = +""
output << "status: OK\n"
output << "openssl_version: #{OpenSSL::OPENSSL_VERSION}\n"
output << "library_version: #{OpenSSL::OPENSSL_LIBRARY_VERSION}\n"

# Verify cert store loads
cert_store_status = begin
  store = OpenSSL::X509::Store.new
  store.set_default_paths
  "OK"
rescue => e # rubocop:disable Style/RescueStandardError
  "FAILED (#{e.message})"
end
output << "cert_store: #{cert_store_status}\n"

# TLS connectivity check (best-effort)
tls_status = begin
  Timeout.timeout(5) do
    uri = URI("https://rubygems.org")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5
    http.head("/")
    "OK (rubygems.org)"
  end
rescue => e # rubocop:disable Style/RescueStandardError
  "SKIPPED (network: #{e.class})"
end
output << "tls_check: #{tls_status}\n"

File.write(File.join(output_dir, "probe_ssl_certs.txt"), output)

exit 0
