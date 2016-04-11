class ProtocolSaver 

  def initialize(protocol, service_request)
    @protocol = protocol
    @service_request = service_request
  end

  def save_new_protocol
    @protocol.save
    flash[:notice] = "New #{@protocol.type.downcase} created"

    if @service_request
      @service_request.update_attribute(:protocol_id, @protocol.id) unless @service_request.protocol.present?
      @service_request.update_attribute(:status, 'draft')
      @service_request.sub_service_requests.each do |ssr|
        ssr.update_attribute(:status, 'draft')
      end
    end
  end

  def save_updated_protocol
    @protocol.save
    session[:saved_protocol_id] = @protocol.id
    flash[:notice] = "#{@protocol.type.humanize} updated"

    #Added as a safety net for older SRs
    if @service_request.status == "first_draft"
      @service_request.update_attributes(status: "draft")
    end
  end
end