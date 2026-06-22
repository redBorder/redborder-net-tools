#!/usr/bin/env ruby

########################################################################
## Copyright (c) 2026 ENEO Tecnología S.L.
## This file is part of redBorder.
## redBorder is free software: you can redistribute it and/or modify
## it under the terms of the GNU Affero General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
## redBorder is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
## GNU Affero General Public License for more details.
## You should have received a copy of the GNU Affero General Public License
## along with redBorder. If not, see <http://www.gnu.org/licenses/>.
########################################################################

# Polling daemon that pulls pending Net Tools tasks from the manager API,
# executes them locally, and posts results back.
#
# Configuration is read from /etc/redborder-net-tools/config.yml:
#   manager_url  — base URL of the redborder-webui
#   sensor_uuid  — UUID of this proxy sensor

require 'json'
require 'net/http'
require 'uri'
require 'open3'
require 'timeout'
require 'logger'
require 'shellwords'
require 'yaml'

CONFIG_FILE      = '/etc/redborder-net-tools/config.yml'
POLL_INTERVAL    = 5   # seconds between polls
MAX_OUTPUT_BYTES = 65_535

ALLOWED_TOOLS = %w[ping ping6 traceroute traceroute6 tcpdump dig snmpget snmpbulkwalk timeout].freeze

logger = Logger.new($stdout)
logger.level    = Logger::INFO
logger.progname = 'redborder-net-tools'
logger.formatter = proc { |sev, _dt, prog, msg| "#{sev} [#{prog}] #{msg}\n" }

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

unless File.exist?(CONFIG_FILE)
  logger.error("Config file not found: #{CONFIG_FILE}")
  exit 1
end

config = YAML.safe_load(File.read(CONFIG_FILE)) || {}
manager_url = config['manager_url'].to_s.strip
sensor_uuid = config['sensor_uuid'].to_s.strip

if manager_url.empty? || sensor_uuid.empty?
  logger.error("manager_url and sensor_uuid must be set in #{CONFIG_FILE}")
  exit 1
end

manager_url = manager_url.chomp('/')
pending_path = "/api/v1/net_tools/pending?sensor_uuid=#{URI.encode_www_form_component(sensor_uuid)}"

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def build_http(uri, timeout: 15)
  http             = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl     = uri.scheme == 'https'
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl?
  http.open_timeout = timeout
  http.read_timeout = timeout
  http
end

def api_get(manager_url, path, logger)
  uri     = URI("#{manager_url}#{path}")
  http    = build_http(uri)
  request = Net::HTTP::Get.new(uri)
  request['Accept'] = 'application/json'

  response = http.request(request)
  JSON.parse(response.body)
rescue => e
  logger.warn("GET #{path} failed: #{e.message}")
  nil
end

def api_patch(manager_url, path, body, logger)
  uri     = URI("#{manager_url}#{path}")
  http    = build_http(uri)
  request = Net::HTTP::Patch.new(uri)
  request['Content-Type'] = 'application/json'
  request['Accept']       = 'application/json'
  request.body            = body.to_json

  http.request(request)
rescue => e
  logger.warn("PATCH #{path} failed: #{e.message}")
  nil
end

# ---------------------------------------------------------------------------
# Command validation (defense in depth — command is already validated by webui)
# ---------------------------------------------------------------------------

def safe_command?(command)
  tokens = Shellwords.split(command.to_s)
  return false if tokens.empty?

  first = tokens[0]
  if first == 'timeout'
    return false if tokens.size < 3
    return ALLOWED_TOOLS.include?(tokens[2])
  end

  ALLOWED_TOOLS.include?(first)
rescue ArgumentError
  false
end

# ---------------------------------------------------------------------------
# Command execution
# ---------------------------------------------------------------------------

def run_command(command, logger)
  logger.info("Executing: #{command}")
  output      = ''
  exit_status = nil

  Timeout.timeout(120) do
    stdout_and_err, status = Open3.capture2e(command)
    output      = stdout_and_err.to_s[0, MAX_OUTPUT_BYTES]
    exit_status = status.exitstatus
  end

  logger.info("Exited with status #{exit_status}")
  { output: output, status: exit_status == 0 ? 'done' : 'error' }
rescue Timeout::Error
  logger.warn('Command timed out after 120s')
  { output: 'Command timed out.', status: 'error' }
rescue => e
  logger.warn("Execution failed: #{e.message}")
  { output: e.message, status: 'error' }
end

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

logger.info("Starting. Manager: #{manager_url}, Sensor UUID: #{sensor_uuid}")

loop do
  begin
    data = api_get(manager_url, pending_path, logger)

    if data && data['task']
      task    = data['task']
      task_id = task['id']
      tool    = task['tool']
      command = task['command']
      result_path = "/api/v1/net_tools/#{task_id}?sensor_uuid=#{URI.encode_www_form_component(sensor_uuid)}"

      logger.info("Got task #{task_id} (#{tool})")

      unless safe_command?(command)
        logger.error("Task #{task_id} rejected — unsafe command: #{command}")
        api_patch(manager_url, result_path,
                  { output: 'Command rejected by proxy security policy.', status: 'error' },
                  logger)
      else
        result = run_command(command, logger)
        api_patch(manager_url, result_path,
                  { output: result[:output], status: result[:status] },
                  logger)
        logger.info("Task #{task_id} completed: #{result[:status]}")
      end
    end
  rescue => e
    logger.error("Unexpected error in poll loop: #{e.message}")
  end

  sleep POLL_INTERVAL
end
