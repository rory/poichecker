class OsmUpdateJob < OsmCommonJob

  def self.enqueue(element_id, element_type, user_id, place_id, tags)
    # Do not enqeue job if not in production or test environment
    # return if Rails.env.development?
    return unless Rails.env.production? || Rails.env.test?

    # Remove wheelchair tag if value is "unknown"
    tags.delete("wheelchair") if tags["wheelchair"] == 'unknown'

    tags = extract_osm_key_value(tags)

    new(element_id, element_type, user_id, place_id, tags).tap do |job|
      Delayed::Job.enqueue(job)
    end
  end

  def perform
    begin

      osm_element   = update_element(element_type, element_id, tags)
      osm_changeset = find_or_create_changeset(user, place.data_set_id)
      api.save(osm_element, osm_changeset)

    rescue Rosemary::Conflict => conflict
      # Catch exception and ignore it, so the job thinks it was successful.
      logger.info "IGNORE: #{element_type}:#{element_id} nothing has changed!"
    end
  end

  def update_element(element_type, element_id, tags)
    element_from_osm = api.find_element(element_type, element_id)
    element_copy = element_from_osm.dup
    element_copy.tags.merge!(tags)

    # Use spaceship operator for comparision:
    # as "element_copy == element_from_osm" is false because of object_id
    comparison_value = (element_from_osm <=> element_copy)

    # Ignore this job, as there are no changes to be saved
    raise Rosemary::Conflict.new('NotChanged') if comparison_value == 0
    element_copy
  end

  def before(job)
    logger.debug("Starting OsmUpdateJob: #{job.id} >>>>>>>>>>>>>>>>>>>>>>>>")
    raise ArgumentError.new("Client cannot be nil") if client.nil?
  end

  def after(job)
    logger.debug("Finished OsmUpdateJob: #{job.id} <<<<<<<<<<<<<<<<<<<<<<<<")
  end

  def success(job)
    logger.debug("Hoooray, success!")
    current_place = place
    current_place.update_attributes!(osm_id: element_id, osm_type: element_type, matcher_id: user_id)
  end

  def error(job,exception)
    logger.error(exception.message)
  end

  def failure(job)
  end

  def self.extract_osm_key_value(tags)
    # Remove osm_key and osm_value tags, as we do not want to change osm types when updating.
    tags.reject {|k,v| k == "osm_key" || k == "osm_value" }
  end


end