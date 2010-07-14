module RackDAV
  class Resource < Struct.new(:path, :options)

    # If this is a collection, return the child resources.
    def children
      raise NotImplementedError
    end

    # Is this resource a collection?
    def collection?
      raise NotImplementedError
    end

    # Does this recource exist?
    def exist?
      raise NotImplementedError
    end

    # Return the creation time.
    def creation_date
      raise NotImplementedError
    end

    # Return the time of last modification.
    def last_modified
      raise NotImplementedError
    end

    # Set the time of last modification.
    def last_modified=(time)
      raise NotImplementedError
    end

    # Return an Etag, an unique hash value for this resource.
    def etag
      raise NotImplementedError
    end

    # Return the resource type.
    #
    # If this is a collection, return
    # REXML::Element.new('D:collection')
    def resource_type
      REXML::Element.new 'D:collection' if collection?
    end

    # Return the mime type of this resource.
    def content_type
      raise NotImplementedError
    end

    # Return the size in bytes for this resource.
    def content_length
      raise NotImplementedError
    end

    # HTTP GET request.
    #
    # Write the content of the resource to the response.body.
    def get(request, response)
      raise NotImplementedError
    end

    # HTTP PUT request.
    #
    # Save the content of the request.body.
    def put(request, response)
      raise NotImplementedError
    end

    # HTTP POST request.
    #
    # Usually forbidden.
    def post(request, response)
      raise NotImplementedError
    end

    # HTTP DELETE request.
    #
    # Delete this resource.
    def delete
      raise NotImplementedError
    end

    # HTTP COPY request.
    #
    # Copy this resource to given destination resource.
    def copy(dest, depth)
      raise NotImplementedError
    end

    # HTTP MOVE request.
    #
    # Move this resource to given destination resource.
    def move(dest, depth)
      # TODO make this cheap
      copy(dest, depth)
      delete
    end

    # HTTP MKCOL request.
    #
    # Create this resource as collection.
    def make_collection
      raise NotImplementedError
    end

    def ==(other)
      path == other.path
    end

    def name
      File.basename(path)
    end

    def display_name
      name
    end

    def child(name, option={})
      self.class.new File.join(path, name), options
    end

    def property_names
      %w[ creationdate
          displayname
          getlastmodified
          getetag
          resourcetype
          getcontenttype
          getcontentlength ]
    end

    def get_property(name)
      case name
      when 'resourcetype'     then resource_type
      when 'displayname'      then display_name
      when 'creationdate'     then creation_date.xmlschema
      when 'getcontentlength' then content_length.to_s
      when 'getcontenttype'   then content_type
      when 'getetag'          then etag
      when 'getlastmodified'  then last_modified.httpdate
      end
    end

    def set_property(name, value)
      case name
      when 'resourcetype'    then self.resource_type = value
      when 'getcontenttype'  then self.content_type = value
      when 'getetag'         then self.etag = value
      when 'getlastmodified' then self.last_modified = Time.httpdate(value)
      end
    rescue ArgumentError
      raise HTTPStatus::Conflict
    end

    def remove_property(name)
      raise HTTPStatus::Forbidden
    end

    def parent
      parent_path = File.dirname path
      parent_path == path ? self : self.class.new(parent_path, options)
    end

    def descendants
      children.inject [] do |list, child|
        list << child
        list.concat(child.descendants)
      end
    end

  end
end
