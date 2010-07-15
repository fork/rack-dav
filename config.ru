require "#{ File.dirname __FILE__ }/lib/rack-dav"

use Rack::ShowExceptions
# use Rack::CommonLogger
# use Rack::Reloader
use Rack::Lint

docroot = ARGV[0]? File.expand_path(ARGV[0]) : Dir.pwd
run ::RackDAV::Handler.new(:root => docroot)
