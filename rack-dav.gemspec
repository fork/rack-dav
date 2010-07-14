Gem::Specification.new do |s|
  s.name = 'rack-dav'
  s.version = '0.1'
  s.summary = 'WebDAV handler for Rack'
  s.author = 'Florian Aßmann, Matthias Georgi'
  s.email = 'src@fork.de'
  s.homepage = 'http://src.fork.de/rack-dav'
  s.description = 'WebDAV handler for Rack'
  s.require_path = 'lib'
  s.executables << 'bin/rack-dav'
  s.has_rdoc = true
  s.extra_rdoc_files = ['README.md']
  s.files = %w[
    .gitignore
    LICENSE
    rack_dav.gemspec
    lib/rack_dav.rb
    lib/rack_dav/file_resource.rb
    lib/rack_dav/handler.rb
    lib/rack_dav/controller.rb
    lib/rack_dav/builder_namespace.rb
    lib/rack_dav/http_status.rb
    lib/rack_dav/resource.rb
    bin/rack_dav
    spec/handler_spec.rb
    README.md
  ]
end
