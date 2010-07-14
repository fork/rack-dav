require 'webrick/httputils'

module RackDAV
  class FileResource < Resource
    include WEBrick::HTTPUtils

    # If this is a collection, return the child resources.
    def children
      pathname.opendir do |dir|
        entries = dir.entries - %w[ . .. ]
        entries.map { |basename| child basename }
      end
    end

    # Is this resource a collection?
    def collection?
      pathname.directory?
    end

    # Does this resource exist?
    def exist?
      pathname.exist?
    end

    # Return the creation time.
    def creation_date
      stat.ctime
    end

    # Return the time of last modification.
    def last_modified
      stat.mtime
    end

    # Set the time of last modification.
    def last_modified=(time)
      pathname.utime Time.now, time
    end

    # Return an Etag, an unique hash value for this resource.
    def etag
      sprintf '%x-%x-%x', stat.ino, stat.size, stat.mtime.to_i
    end

    # Return the mime type of this resource.
    def content_type
      if collection?
        'text/html'
      else
        mime_type pathname.to_s, DefaultMimeTypes
      end
    end

    # Return the size in bytes for this resource.
    def content_length
      stat.size
    end

    # HTTP GET request.
    #
    # Write the content of the resource to the response.body.
    def get(request, response)
      if collection?
        response.body = ''
        Rack::Directory.new(root).call(request.env)[2].each do |line|
          response.body << line
        end
        response['Content-Length'] = response.body.size.to_s
      else
        file = Rack::File.new root
        file.path = pathname.to_s
        response.body = file
      end
    end

    # HTTP PUT request.
    #
    # Save the content of the request.body.
    def put(request, response)
      write request.body
    end

    # HTTP POST request.
    #
    # Usually forbidden.
    def post(request, response)
      raise HTTPStatus::Forbidden
    end

    # HTTP DELETE request.
    #
    # Delete this resource.
    def delete
      collection?? pathname.rmtree : pathname.unlink
    end

    # HTTP COPY request.
    #
    # Copy this resource to given destination resource.
    def copy(dest, depth)
      make_backup_and_delete_on_success(dest.pathname) do
        if depth == -1 or !collection?
          FileUtils.cp_r pathname, dest.pathname
        else
          FileUtils.mkdir dest.pathname
        end
      end
    end

    def make_backup_and_delete_on_success(path, &block)
      source = Pathname path

      return yield unless source.exist?

      backup = Pathname source.dirname.join(".backup.#{ source.basename }.#{ Process.pid }.#{ Thread.current.object_id }")
      source.rename backup

      begin
        yield
        backup.directory? ? backup.rmtree : backup.unlink
      rescue => e
        backup.rename source if backup.exist?
        raise e
      end
    end

    # HTTP MKCOL request.
    #
    # Create this resource as collection.
    def make_collection
      pathname.mkdir
    end

    # Write to this resource from given IO.
    def write(io)
      tempfile = "#{ pathname }.#{ Process.pid }.#{ Thread.current.object_id }"

      open(tempfile, 'wb') do |file|
        while part = io.read(8192)
          file << part
        end
      end

      File.rename(tempfile, pathname.to_s)
    ensure
      File.unlink(tempfile) rescue nil
    end

    def pathname
      @pathname ||= Pathname.new File.join(root, path)
    end

    private

      def root
        options[:root]
      end
      def stat
        @stat ||= pathname.stat
      end

  end
end
