require 'time'
require 'fileutils'
require 'pathname'
require 'rexml/document' # TODO use nokogiri, skip builder dependency
require 'uri'

require 'rubygems'
require 'builder' # TODO either add dependency in gemspec or use nokogiri
require 'rack'

module RackDAV
  autoload :FileResource, 'rack-dav/file_resource'
end

require 'rack-dav/builder_namespace'
require 'rack-dav/http_status'
require 'rack-dav/resource'
require 'rack-dav/handler'
require 'rack-dav/controller'
