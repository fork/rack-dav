module RackDAV
  class Controller < Struct.new(:request, :response, :options)
    include RackDAV::HTTPStatus

    GUARDS = Hash.new { |h, k| [] }
    GUARDS['options']   = []
    GUARDS['head']      = %w[ MissingResource ]
    GUARDS['get']       = %w[ MissingResource ]
    GUARDS['put']       = %w[ CollectionResource ]
    GUARDS['delete']    = %w[ MissingResource ]
    GUARDS['mkcol']     = %w[ ExistingResource WeirdBody ]
    GUARDS['copy']      = %w[ MissingResource RemoteDestination SameDestination Overwrite ]
    GUARDS['move']      = %w[ MissingResource RemoteDestination SameDestination Overwrite ]
#    GUARDS['propfind']  = %w[ MissingResource MalformedXML ZeroDepth ]
    GUARDS['propfind']  = %w[ MissingResource MalformedXML ] # ?
    GUARDS['proppatch'] = %w[ MissingResource ]
    GUARDS['lock']      = %w[ MissingResource ]
    GUARDS.freeze

    def run
      if env['HTTP_X_LITMUS']
        STDERR.puts
        STDERR.puts "******** #{ env['HTTP_X_LITMUS'] } ********"
        STDERR.puts
      end

      method = request.request_method.downcase
      guard method

      begin
        response.status = send "dav_#{ method }"
      rescue => e
        map_exception e
      end
    end

    private

      def sanitize_path(path)
        path = url_unescape path
        # RADAR parse_uri?
        path
      end

      def resource_class
        options[:resource_class]
      end
      def new_resource(path)
        resource_class.new sanitize_path(path), options
      end

      def resource
        @resource ||= begin
          raise Forbidden if request.path_info.include? '..'
          raise Forbidden if request.env['REQUEST_URI'].include? '#'

          new_resource request.path_info
        end
      end
      def future_resource
        @future_resource ||= new_resource destination.path
      end

      def url_escape(s)
        # FIXME unicode problems
        s.gsub(/([^\/a-zA-Z0-9_.-]+)/n) do
          '%' + $1.unpack('H2' * $1.size).join('%').upcase
        end.tr(' ', '+')
      end

      def url_unescape(s)
        # FIXME unicode problems
        s.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n) do
          [$1.delete('%')].pack('H*')
        end
      end

      def env
        request.env
      end
      def host
        env['HTTP_HOST']
      end
      def destination
        @destination ||= URI env['HTTP_DESTINATION'].sub(/\/$/, '')
      end

      def parse_uri uri
        options[:base_uri] ? url_unescape(URI.parse(uri).path.gsub(/#{ Regexp.escape options[:base_uri] }/, '/')) : url_unescape(URI.parse(uri).path)
      end

      def uri path
        options[:base_uri] ? "http://#{ host }#{ options[:base_uri].gsub(/^(.*)\/$/,'\\1') }#{ url_escape path }" : "http://#{ host }#{ url_escape path }"
      end

      def depth
        case env['HTTP_DEPTH']
        when '0' then 0
        when '1' then 1
        else -1 # RADAR default to Infinity for all COPYs on a collection
        end
      end

      def overwrite?
        env['HTTP_OVERWRITE'].to_s.upcase != 'F'
      end

      def guard(name)
        GUARDS[name].each do |guard|
          case guard
          when 'CollectionResource'
            raise Forbidden if resource.collection?
          when 'ExistingResource'
            raise MethodNotAllowed if resource.exist?
          when 'MalformedXML'
            raise BadRequest if request_document.root.name != 'propfind'
          when 'MissingResource'
            raise NotFound unless resource.exist?
          when 'Overwrite'
            raise PreconditionFailed if !overwrite? and future_resource.exist?
          when 'RemoteDestination'
            same_host = !destination.host || destination.host == request.host
            raise BadGateway unless same_host
          when 'SameDestination'
            raise Forbidden unless destination.path != resource.path
          when 'WeirdBody'
            raise UnsupportedMediaType unless body.empty?
          when 'ZeroDepth'
            raise Conflict unless depth != 0
          end
        end
      end

      def find_resources
        case depth
        when 0 then [resource]
        when 1 then [resource, *resource.children]
        else
          [resource, *resource.descendants]
        end
      end

      def map_exception(e)
        STDERR.puts e.message, "  #{ e.backtrace.join "\n  " }"

        case e
        when URI::InvalidURIError then raise BadRequest
        when Errno::EACCES then raise Forbidden
        when Errno::ENOENT then raise Conflict
        when Errno::EEXIST then raise Conflict
        when Errno::ENOSPC then raise InsufficientStorage
        end

        raise e
      end

      def map_exceptions
        yield
      rescue => e
        map_exception e
      end

      def body
        @body ||= request.body.read
      end

      def request_document
        @request_document ||= begin
          # REXML just drops them, so we do the job here...
          raise REXML::ParseException if body[/xmlns(?:\:[a-z]+)?\=""/]
          REXML::Document.new body
        end
      rescue REXML::ParseException
        raise BadRequest
      end

      def request_match(pattern, document = request_document)
        REXML::XPath::match(document, pattern, '' => 'DAV:')
      end

      def render_xml
        xml = Builder::XmlMarkup.new(:indent => 2)
        xml.instruct! :xml, :version => '1.0', :encoding => 'UTF-8'

        xml.namespace('D') do
          yield xml
        end

        response.body = xml.target!
        response['Content-Type'] = 'text/xml; charset="utf-8"'
        response['Content-Length'] = response.body.size.to_s
      end

      def multistatus
        render_xml do |xml|
          xml.multistatus('xmlns:D' => 'DAV:') do
            yield xml
          end
        end

        MultiStatus
      end

      def response_errors(xml, errors)
        for path, status in errors
          xml.response do
            xml.href uri(path)
            #xml.status "#{ env['HTTP_VERSION'] } #{ status.status_line }" #env['HTTP_VERSION'] doesn't work
            xml.status "HTTP/1.1 #{ status.status_line }"
          end
        end
      end

      def get_properties(resource, names)
        stats = Hash.new { |h, k| h[k] = [] }
        for name in names
          begin
            map_exceptions do
              stats[OK] << [name, resource.get_property(name)]
            end
          rescue Status
            stats[$!] << name
          end
        end
        stats
      end

      def set_properties(resource, pairs)
        stats = Hash.new { |h, k| h[k] = [] }
        for name, value in pairs
          begin
            map_exceptions do
              stats[OK] << [name, resource.set_property(name, value)]
            end
          rescue Status
            stats[$!] << name
          end
        end
        stats
      end

      def propstats(xml, stats)
        return if stats.empty?
        for status, props in stats
          xml.propstat do
            xml.prop do
              for name, value in props
                if value.is_a?(REXML::Element)
                  xml.tag!(name) do
                    rexml_convert(xml, value)
                  end
                else
                  xml.tag!(name, value)
                end
              end
            end
            #xml.status "#{env['HTTP_VERSION']} #{status.status_line}"
            xml.status "HTTP/1.1 #{ status.status_line }"
          end
        end
      end

      def rexml_convert(xml, element)
        if element.elements.empty?
          if element.text
            xml.tag!(element.name, element.text, element.attributes)
          else
            xml.tag!(element.name, element.attributes)
          end
        else
          xml.tag!(element.name, element.attributes) do
            element.elements.each do |child|
              rexml_convert(xml, child)
            end
          end
        end
      end

      def dav_options
        response['Allow']             = 'OPTIONS,HEAD,GET,PUT,POST,DELETE,PROPFIND,PROPPATCH,MKCOL,COPY,MOVE,LOCK,UNLOCK'
        response['DAV']               = '1,2'
        response['MS-Author-Via']     = 'DAV'
        OK
      end

      def dav_head
        response['Etag']              = resource.etag
        response['Content-Type']      = resource.content_type
        response['Last-Modified']     = resource.last_modified.httpdate
        OK
      end

      def dav_get
        resource.get request, response

        response['Content-Length']    = resource.content_length.to_s
        response['Etag']              = resource.etag
        response['Content-Type']      = resource.content_type
        response['Last-Modified']     = resource.last_modified.httpdate
        OK
      end

      def dav_put
        resource.put request, response
        Created
      end

      def dav_post
        resource.post request, response
        Created
      end

      def dav_delete
        resource.delete
        OK
      end

      def dav_mkcol
        resource.make_collection
        Created
      end

      def with_future_resource
        result = future_resource.exist? ? NoContent : Created
        yield future_resource

        result
      end

      def dav_copy
        with_future_resource { |future| resource.copy future, depth }
      end
      def dav_move
        with_future_resource { |future| resource.move future, depth }
      end

      def dav_propfind
        unless request_match('/propfind/allprop').empty?
          names = resource.property_names
        else
          names = request_match('/propfind/prop/*').map { |e| e.name }
          names = resource.property_names if names.empty?
        end

        multistatus do |xml|
          for resource in find_resources
            xml.response do
              xml.href uri(resource.path)
              propstats xml, get_properties(resource, names)
            end
          end
        end
      end

      def dav_proppatch
        prop_rem = request_match('/propertyupdate/remove/prop/*').map { |e| [e.name] }
        prop_set = request_match('/propertyupdate/set/prop/*').map { |e| [e.name, e.text] }

        multistatus do |xml|
          for resource in find_resources
            xml.response do
              xml.href uri(resource.path)
              propstats xml, set_properties(resource, prop_set)
            end
          end
        end

        #resource.save
      end

      def dav_lock
        lockscope = request_match('/lockinfo/lockscope/*').first.name
        locktype = request_match('/lockinfo/locktype/*').first.name
        owner = request_match('/lockinfo/owner/href').first
        locktoken = 'opaquelocktoken:' + sprintf('%x-%x-%s', Time.now.to_i, Time.now.sec, resource.etag)

        response['Lock-Token'] = locktoken

        render_xml do |xml|
          xml.prop('xmlns:D' => "DAV:") do
            xml.lockdiscovery do
              xml.activelock do
                xml.lockscope { xml.tag! lockscope }
                xml.locktype { xml.tag! locktype }
                xml.depth 'Infinity'
                if owner
                  xml.owner { xml.href owner.text }
                end
                xml.timeout "Second-60"
                xml.locktoken do
                  xml.href locktoken
                end
              end
            end
          end
        end
      end

      def dav_unlock
        raise NoContent
      end

  end
end
