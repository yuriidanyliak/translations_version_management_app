require 'zip'

module ApplicationHelper
  def flatten_hash(input_hash)
    input_hash.each_with_object({}) do |(key, value), hash|
      if value.is_a? Hash
        flatten_hash(value).map do |nested_key, nested_value|
          hash["#{key}_#{nested_key}"] = nested_value
        end
      else 
        hash[key] = value
      end
    end
  end

  def unpack_and_parse(raw)
    data = ""

    Zip::File.open_buffer(raw) do |zip|
      zip.each do |entry|
        next unless entry.file?

        entry.extract("/tmp/#{Time.now.getutc.strftime('%Y-%m-%d_%H:%m:%s')}")
        data = JSON.parse(entry.get_input_stream.read)
      end
    end

    data
  end

  def inject_translations(spec)
    resulting_spec = spec.clone

    translations = lokalize_wrapper.download_from_lokalize

    translations.each do |path, translation|
      keys_array = path.split('_')
      keys_array.size > 1 ? last_key = keys_array.pop : last_key = keys_array.last

      command_string = 'resulting_spec'
      keys_array.each { |key| command_string = command_string + "['" + key + "']" }

      command_string = "#{command_string} = '#{translation}'"
      eval(command_string)
    rescue NoMethodError, IndexError
    end

    resulting_spec
  end
end
