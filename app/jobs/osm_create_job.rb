class OsmCreateJob < OsmCommonJob # (:element_id, :element_type, :user_id, :place_id, :tags)

  def self.enqueue(user_id, place_id, tags)
    # Do not enqeue job if not in production or test environment
    # return if Rails.env.development?
    return unless Rails.env.production? || Rails.env.test?

    # Remove wheelchair tag if value is "unknown"
    tags.delete("wheelchair") if tags["wheelchair"] == 'unknown'

    tags = extract_osm_key_value(tags)

    new(nil, 'node', user_id, place_id, tags).tap do |job|
      Delayed::Job.enqueue(job)
    end
  end

  def perform
    osm_element     = Rosemary::Node.new
    osm_element.lat = tags.delete('lat')
    osm_element.lon = tags.delete('lon')
    osm_element.add_tags(tags)
    osm_changeset   = find_or_create_changeset(user, place.data_set_id)
    element_id      = api.create(osm_element, osm_changeset)
  end

  def before(job)
    logger.debug("Starting OsmCreateJob: #{job.id} >>>>>>>>>>>>>>>>>>>>>>>>")
    raise ArgumentError.new("Client cannot be nil") if client.nil?
  end

  def success(job)
    logger.debug("Hoooray, success!")
    current_place = place
    current_place.update_attributes!(osm_id: element_id, osm_type: element_type, matcher_id: user_id)
  end

  def self.extract_osm_key_value(tags)
    # change osm_key, osm_value tags into a single one like this:
    # "osm_key"   => "amenity"
    # "osm_value" => "bank"
    #
    # "amenity" => "bank"

    osm_key   = tags.delete("osm_key")
    osm_value = tags.delete("osm_value")
    tags[osm_key] = osm_value
    tags
  end

end
