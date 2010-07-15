module RackDAV
  class Handler < Proc

    def self.new(options = {})
      options[:resource_class] ||= RackDAV.const_get :FileResource
      options[:root] ||= Dir.pwd

      super do |env|
        response = Rack::Response.new
        Controller.run Rack::Request.new(env), response, options
        response.finish
      end
    end

  end
end
