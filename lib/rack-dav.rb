require 'time'
require 'fileutils'
require 'pathname'
require 'uri'

require 'nokogiri'
require 'rack'

module RackDAV

  lib_path = "#{ File.dirname __FILE__ }/rack-dav"

  REQ = proc { |basename| require "#{ lib_path }/#{ basename }" }
  %w[ http_status resource handler controller ].each(&REQ)

  autoload :FileResource, "#{ lib_path }/file_resource"

end
