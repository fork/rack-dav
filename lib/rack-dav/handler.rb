module RackDAV
  class Handler

    DEFAULTS = { :resource_class => FileResource, :root => Dir.pwd }

    def initialize(options = {})
      @options = DEFAULTS.merge options
    end

    def call(env)
      request, response = Rack::Request.new(env), Rack::Response.new

      begin
        controller = Controller.new request, response, @options.dup
        controller.run
      rescue HTTPStatus::Status => status
        response.status = status.code
      end

      # Strings in Ruby 1.9 are no longer enumerable. Rack still expects the
      # response.body to be enumerable, however.
      response.body = [response.body] if String === response.body
      response.status ||= 200

      response.finish
    end

  end
end
