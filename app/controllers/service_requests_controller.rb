# Copyright © 2011 MUSC Foundation for Research Development
# All rights reserved.

# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

# 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

# 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
# disclaimer in the documentation and/or other materials provided with the distribution.

# 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products
# derived from this software without specific prior written permission.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,
# BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
# SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
# TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'generate_request_grant_billing_pdf'

class ServiceRequestsController < ApplicationController
  before_filter :initialize_service_request, :except => [:approve_changes]
  before_filter :authorize_identity, :except => [:approve_changes, :show]
  before_filter :authenticate_identity!, :except => [:catalog, :add_service, :remove_service, :ask_a_question, :feedback]
  before_filter :prepare_catalog, :only => :catalog
  layout false, :only => [:ask_a_question, :feedback]
  respond_to :js, :json, :html

  def show
    @protocol = @service_request.protocol
    @service_list = @service_request.service_list
    @admin_offset = params[:admin_offset]

    # TODO: this gives an error in the spec tests, because they think
    # it's trying to render html instead of xlsx
    #
    #   render xlsx: "show", filename: "service_request_#{@service_request.id}", disposition: "inline"
    #
    # So I did this instead, but I don't know if it's right:
    #
    respond_to do |format|
      format.xlsx do
        render xlsx: "show", filename: "service_request_#{@service_request.protocol.id}", disposition: "inline"
      end
    end
  end

  def navigate
    errors = []
    # need to save and navigate to the right page

    #### add logic to save data
    referrer = request.referrer.split('/').last

    # Save/Update any subsidy info we may have
    subsidy_save_update(errors)

    @service_request.update_attributes(params[:service_request])

    #### if study/project attributes are available (step 2 arms nested form), update them
    if params[:study]
      @service_request.protocol.update_attributes(params[:study])
    elsif params[:project]
      @service_request.protocol.update_attributes(params[:project])
    end

    if params[:current_location] == 'service_details'
      @service_request.reload
    end

    # Save/Update any document info we may have
    document_save_update(errors)

    location = params["location"]
    additional_params = request.referrer.split('/').last.split('?').size == 2 ? "?" + request.referrer.split('/').last.split('?').last : nil
    validates = params["validates"]

    if (@validation_groups[location].nil? or @validation_groups[location].map{|vg| @service_request.group_valid? vg.to_sym}.all?) and (validates.blank? or @service_request.group_valid? validates.to_sym) and errors.empty?
      @service_request.save(:validate => false)
      redirect_to "/service_requests/#{@service_request.id}/#{location}#{additional_params}"
    else
      if @validation_groups[location]
        @validation_groups[location].each do |vg|
          errors << @service_request.grouped_errors[vg.to_sym].messages unless @service_request.grouped_errors[vg.to_sym].messages.empty?
        end
      end

      unless validates.blank?
        errors << @service_request.grouped_errors[validates.to_sym].messages unless @service_request.grouped_errors[validates.to_sym].empty?
      end

      session[:errors] = errors.compact.flatten.first # TODO I DON'T LIKE THIS AT ALL

      if @page != 'navigate'
        send @page.to_sym
        render action: @page
      else
        redirect_to :back
      end
    end
  end

  # service request wizard pages

  def catalog
    # uses a before filter defined in application controller named 'prepare_catalog', extracted so that devise controllers could use as well
  end

  def protocol
    cookies.delete :current_step
    @service_request.update_attribute(:service_requester_id, current_user.id) if @service_request.service_requester_id.nil?
    
    if session[:saved_protocol_id]
      @service_request.protocol = Protocol.find session[:saved_protocol_id]
      session.delete :saved_protocol_id
    end

    @ctrc_services = false
    if session[:errors] and session[:errors] != []
      if session[:errors][:ctrc_services]
        @ctrc_services = true
        @ssr_id = @service_request.protocol.find_sub_service_request_with_ctrc(@service_request.id)
      end
    end
  end

  def service_details
    @service_request.add_or_update_arms
  end

  def service_calendar
    #use session so we know what page to show when tabs are switched
    session[:service_calendar_pages] = params[:pages] if params[:pages]

    # TODO: why is @page not set here?  if it's not supposed to be set
    # then there should be a comment as to why it's set in #review but
    # not here

    @service_request.arms.each do |arm|
      #check each ARM for line_items_visits (in other words, it's a new arm)
      if arm.line_items_visits.empty?
        #Create missing line_items_visits
        @service_request.per_patient_per_visit_line_items.each do |line_item|
          arm.create_line_items_visit(line_item)
        end
      else
        #Check to see if ARM has been modified...
        arm.line_items_visits.each do |liv|
          #Update subject counts under certain conditions
          if @service_request.status == 'first_draft' or liv.subject_count.nil? or liv.subject_count > arm.subject_count
            liv.update_attribute(:subject_count, arm.subject_count)
          end
        end
        #Arm.visit_count has benn increased, so create new visit group, and populate the visits
        if arm.visit_count > arm.visit_groups.count
          ActiveRecord::Base.transaction do
            arm.mass_create_visit_group
          end
        end
        #Arm.visit_count has been decreased, destroy visit group (and visits)
        if arm.visit_count < arm.visit_groups.count
          ActiveRecord::Base.transaction do
            arm.mass_destroy_visit_group
          end
        end
      end
    end
  end

  # do not delete.  Method will be needed if calendar totals page is
  # used.
  # def calendar_totals
  #   if @service_request.arms.blank?
  #     @back = 'service_details'
  #   end
  # end


  def service_subsidy
    # this is only if the calendar totals page is not going to be used.
    if @service_request.arms.blank?
      @back = 'service_details'
    end
    @subsidies = []
    @service_request.sub_service_requests.each do |ssr|
      if ssr.subsidy
        # we already have a subsidy; add it to the list
        subsidy = ssr.subsidy
        @subsidies << subsidy
      elsif ssr.eligible_for_subsidy?
        # we don't have a subsidy yet; add it to the list but don't save
        # it yet
        # TODO: is it a good idea to modify this SubServiceRequest like
        # this without saving it to the database?
        ssr.build_subsidy
        @subsidies << ssr.subsidy
      end
    end

    if @subsidies.empty? || !subsidies_for_ssr(@subsidies)
      redirect_to "/service_requests/#{@service_request.id}/document_management"
    end
  end

  def subsidies_for_ssr subsidies
    if @sub_service_request
      has_match = false
      subsidies.each do |subsidy|
        if subsidy.sub_service_request_id == @sub_service_request.id
          has_match = true
        end
      end

      return has_match
    else
      return true
    end
  end

  def document_management
    if @service_request.sub_service_requests.map(&:subsidy).compact.empty?
      @back = 'service_calendar'
    end
  end

  def review
    arm_id = params[:arm_id].to_s if params[:arm_id]
    page = params[:page] if params[:page]
    session[:service_calendar_pages] = params[:pages] if params[:pages]
    session[:service_calendar_pages][arm_id] = page if page && arm_id
    @thead_class = 'red-provider'
    @portal = false
    @service_list = @service_request.service_list
    @protocol = @service_request.protocol

    # Reset all the page numbers to 1 at the start of the review request
    # step.
    @pages = {}
    @service_request.arms.each do |arm|
      @pages[arm.id] = 1
    end

    @tab = 'calendar'
    @review = true
  end

  def obtain_research_pricing
    # TODO: refactor into the ServiceRequest model
    update_service_request_status(@service_request, 'get_a_cost_estimate')
    @service_request.ensure_ssr_ids

    @protocol = @service_request.protocol
    # As the service request leaves draft, so too do the arms
    @protocol.arms.each do |arm|
      arm.update_attributes({:new_with_draft => false})
    end
    @service_list = @service_request.service_list

    send_confirmation_notifications

    render :formats => [:html]
  end

  def confirmation
    update_service_request_status(@service_request, 'submitted')
    @service_request.ensure_ssr_ids
    @service_request.update_arm_minimum_counts

    @protocol = @service_request.protocol
    # As the service request leaves draft, so too do the arms
    @protocol.arms.each do |arm|
      arm.update_attributes({:new_with_draft => false})
      if @protocol.service_requests.map {|x| x.sub_service_requests.map {|y| y.in_work_fulfillment}}.flatten.include?(true)
        arm.populate_subjects
      end
    end
    @service_list = @service_request.service_list

    @service_request.sub_service_requests.each do |ssr|
      ssr.subsidy.update_attributes(:overridden => true) if ssr.subsidy
      ssr.update_attributes(:nursing_nutrition_approved => false, :lab_approved => false, :imaging_approved => false, :committee_approved => false)
    end

    send_confirmation_notifications

    # Send a notification to Lane et al to create users in Epic.  Once
    # that has been done, one of them will click a link which calls
    # approve_epic_rights.
    if USE_EPIC
      if @protocol.selected_for_epic
        @protocol.ensure_epic_user
        if QUEUE_EPIC
          EpicQueue.create(:protocol_id => @protocol.id) unless EpicQueue.where(:protocol_id => @protocol.id).size == 1
        else
          @protocol.awaiting_approval_for_epic_push
          send_epic_notification_for_user_approval(@protocol)
        end
      end
    end

    render :formats => [:html]
  end

  def send_confirmation_notifications
    if @service_request.previous_submitted_at.nil?
      send_notifications(@service_request, @sub_service_request)
    elsif service_request_has_changed_ssr?(@service_request)
      xls = render_to_string :action => 'show', :formats => [:xlsx]
      @service_request.sub_service_requests.each do |ssr|
        if ssr_has_changed?(@service_request, ssr)
          send_ssr_service_provider_notifications(@service_request, ssr, xls)
        end
      end
    end
  end

  def approve_changes
    @service_request = ServiceRequest.find params[:id]
    @approval = @service_request.approvals.where(:id => params[:approval_id]).first
    @previously_approved = true

    if @approval and @approval.identity.nil?
      @approval.update_attributes(:identity_id => current_user.id, :approval_date => Time.now)
      @previously_approved = false
    end
  end

  def save_and_exit
    unless @sub_service_request # if we are editing a sub service request just redirect
      @service_request.update_status('draft', false)
      @service_request.ensure_ssr_ids
    end

    redirect_to USER_PORTAL_LINK
  end

  def refresh_service_calendar
    arm_id = params[:arm_id].to_s if params[:arm_id]
    @arm = Arm.find arm_id if arm_id
    @portal = params[:portal] if params[:portal]
    @thead_class = @portal == 'true' ? 'ui-widget-header' : 'red-provider'
    page = params[:page] if params[:page]
    session[:service_calendar_pages] = params[:pages] if params[:pages]
    session[:service_calendar_pages][arm_id] = page if page && arm_id
    @pages = {}
    @service_request.arms.each do |arm|
      new_page = (session[:service_calendar_pages].nil?) ? 1 : session[:service_calendar_pages][arm.id.to_s].to_i
      @pages[arm.id] = @service_request.set_visit_page new_page, arm
    end
    @tab = 'calendar'
  end

  # methods only used by ajax requests

  def add_service
    id = params[:service_id].sub('service-', '').to_i
    @new_line_items = []
    existing_service_ids = @service_request.line_items.map(&:service_id)

    if existing_service_ids.include? id
      render :text => 'Service exists in line items'
    else
      service = Service.find id

      @new_line_items = @service_request.create_line_items_for_service(
          service: service,
          optional: true,
          existing_service_ids: existing_service_ids,
          recursive_call: false)

      # create sub_service_requests
      @service_request.reload
      @service_request.service_list.each do |org_id, values|
        line_items = values[:line_items]
        ssr = @service_request.sub_service_requests.where(organization_id: org_id.to_i).first_or_create
        unless @service_request.status.nil? and !ssr.status.nil?
          ssr.update_attribute(:status, @service_request.status) if ['first_draft', 'draft', nil].include?(ssr.status)
          @service_request.ensure_ssr_ids unless ['first_draft', 'draft'].include?(@service_request.status)
        end

        line_items.each do |li|
          li.update_attribute(:sub_service_request_id, ssr.id)
        end
      end
    end
  end

  def remove_service
    id = params[:line_item_id].sub('line_item-', '').to_i

    @line_item = @service_request.line_items.find(id)
    service = @line_item.service
    line_item_service_ids = @service_request.line_items.map(&:service_id)

    # look at related services and set them to optional
    # TODO POTENTIAL ISSUE: what if another service has the same related service
    service.related_services.each do |rs|
      if line_item_service_ids.include? rs.id
        @service_request.line_items.find_by_service_id(rs.id).update_attribute(:optional, true)
      end
    end

    @line_items.find_by_service_id(service.id).destroy
    @line_items.reload

    #@service_request = current_user.service_requests.find session[:service_request_id]
    @service_request = ServiceRequest.find session[:service_request_id]
    @page = request.referrer.split('/').last # we need for pages other than the catalog

    # Have the protocol clean up the arms
    @service_request.protocol.arm_cleanup if @service_request.protocol

    # clean up sub_service_requests
    @service_request.reload

    to_delete = @service_request.sub_service_requests.map(&:organization_id) - @service_request.service_list.keys
    to_delete.each do |org_id|
      ssr = @service_request.sub_service_requests.find_by_organization_id(org_id)
      if !['first_draft', 'draft'].include?(@service_request.status) and !@service_request.submitted_at.nil? and @service_request.submitted_at > ssr.created_at
        @protocol = @service_request.protocol
        xls = @protocol.nil? ? nil : render_to_string(:action => 'show', :formats => [:xlsx])
        send_ssr_service_provider_notifications(@service_request, ssr, xls, ssr_deleted=true)
      end
      ssr.destroy
    end

    @service_request.reload

    @line_items = (@sub_service_request.nil? ? @service_request.line_items : @sub_service_request.line_items)
    render :formats => [:js]
  end

  def ask_a_question
    from = params['quick_question']['email'].blank? ? NO_REPLY_FROM : params['quick_question']['email']
    body = params['quick_question']['body'].blank? ? 'No question asked' : params['quick_question']['body']

    quick_question = QuickQuestion.create :to => DEFAULT_MAIL_TO, :from => from, :body => body
    Notifier.ask_a_question(quick_question).deliver
  end

  def feedback
    feedback = Feedback.new(params[:feedback])
    if feedback.save
      Notifier.provide_feedback(feedback).deliver_now
      render :nothing => true
    else
      respond_to do |format|
        format.js { render :status => 403, :json => feedback.errors.to_a.map {|k,v| "#{k.humanize} #{v}".rstrip + '.'} }
      end
    end
  end

  def delete_documents
    # deletes a document unless we are working with a sub_service_request
    @document = @service_request.documents.find params[:document_id]
    @tr_id = "#document_id_#{@document.id}"

    if @sub_service_request.nil?
      @document.destroy # destroys the document
    else
      @sub_service_request.documents.delete @document # removes doc from ssr
      @sub_service_request.save
      @document.destroy if @document.sub_service_requests.empty? #if no ssrs left, destroys document
    end
  end

  def edit_documents
    @document = @service_request.documents.find params[:document_id]
    @service_list = @service_request.service_list
  end

  def new_document
    @service_list = @service_request.service_list
  end

  private

  # Send notifications to all users.
  def send_notifications(service_request, sub_service_request)
    xls = render_to_string :action => 'show', :formats => [:xlsx]
    send_user_notifications(service_request, xls)

    if sub_service_request then
      sub_service_requests = [ sub_service_request ]
    else
      sub_service_requests = service_request.sub_service_requests
    end

    send_admin_notifications(sub_service_requests, xls)
    send_service_provider_notifications(service_request, sub_service_requests, xls)
  end

  def send_user_notifications(service_request, xls)
    # Does an approval need to be created?  Check that the user
    # submitting has approve rights.
    if service_request.protocol.project_roles.detect{|pr| pr.identity_id == current_user.id}.project_rights != "approve"
      approval = service_request.approvals.create
    else
      approval = false
    end

    # send e-mail to all folks with view and above
    service_request.protocol.project_roles.each do |project_role|
      next if project_role.project_rights == 'none'
      Notifier.notify_user(project_role, service_request, xls, approval, current_user).deliver_now unless project_role.identity.email.blank?
    end
  end

  def send_admin_notifications(sub_service_requests, xls)
    sub_service_requests.each do |sub_service_request|
      sub_service_request.organization.submission_emails_lookup.each do |submission_email|
        Notifier.notify_admin(sub_service_request.service_request, submission_email.email, xls, current_user).deliver
      end
    end
  end

  def send_service_provider_notifications(service_request, sub_service_requests, xls) #all sub-service requests on service request
    sub_service_requests.each do |sub_service_request|
      send_ssr_service_provider_notifications(service_request, sub_service_request, xls)
    end
  end

  def send_ssr_service_provider_notifications(service_request, sub_service_request, xls, ssr_deleted=false) #single sub-service request
    previously_submitted_at = service_request.previous_submitted_at.nil? ? Time.now.utc : service_request.previous_submitted_at.utc
    audit_report = sub_service_request.audit_report(current_user, previously_submitted_at, Time.now.utc)

    sub_service_request.organization.service_providers.where("(`service_providers`.`hold_emails` != 1 OR `service_providers`.`hold_emails` IS NULL)").each do |service_provider|
      send_individual_service_provider_notification(service_request, sub_service_request, service_provider, xls, audit_report, ssr_deleted)
    end
  end

  def ssr_has_changed?(service_request, sub_service_request) #specific ssr has changed?
    previously_submitted_at = service_request.previous_submitted_at.nil? ? Time.now.utc : service_request.previous_submitted_at.utc
    unless sub_service_request.audit_report(current_user, previously_submitted_at, Time.now.utc)[:line_items].empty?
      return true
    end
    return false
  end

  def service_request_has_changed_ssr?(service_request) #any ssr on sr has changed?
    service_request.sub_service_requests.each do |ssr|
      if ssr_has_changed?(service_request, ssr)
        return true
      end
    end
    return false
  end

  def send_individual_service_provider_notification(service_request, sub_service_request, service_provider, xls, audit_report=nil, ssr_deleted=false)
    attachments = {}
    attachments["service_request_#{service_request.id}.xlsx"] = xls

    #TODO this is not very multi-institutional
    # generate the required forms pdf if it's required
    if sub_service_request.organization.tag_list.include? 'required forms'
      request_for_grant_billing_form = RequestGrantBillingPdf.generate_pdf service_request
      attachments["request_for_grant_billing_#{service_request.id}.pdf"] = request_for_grant_billing_form
    end

    if audit_report.nil?
      previously_submitted_at = service_request.previous_submitted_at.nil? ? Time.now.utc : service_request.previous_submitted_at.utc
      audit_report = sub_service_request.audit_report(current_user, previously_submitted_at, Time.now.utc)
    end

    Notifier.notify_service_provider(service_provider, service_request, attachments, current_user, audit_report, ssr_deleted).deliver_now
  end

  def send_epic_notification_for_user_approval(protocol)
    Notifier.notify_for_epic_user_approval(protocol).deliver unless QUEUE_EPIC
  end

  # Navigate updates
  # Subsidy saves/updates
  def subsidy_save_update errors
    #### convert dollars to cents for subsidy
    if params[:service_request] && params[:service_request][:sub_service_requests_attributes]
      params[:service_request][:sub_service_requests_attributes].each do |key, values|
        ssr = @service_request.sub_service_requests.find values[:id]
        if !check_for_overridden(ssr)
          direct_cost = ssr.direct_cost_total
          dollars = values[:subsidy_attributes][:pi_contribution]
          funded_amount = direct_cost - Service.dollars_to_cents(dollars)
          percent_subsidy = ((funded_amount / direct_cost) * 100).round(2)
          if dollars.blank? # we don't want to create a subsidy if it's blank
            values.delete(:subsidy_attributes)
            ssr.subsidy.delete if ssr.subsidy
          else
            values[:subsidy_attributes][:pi_contribution] = Service.dollars_to_cents(dollars)
            values[:subsidy_attributes][:stored_percent_subsidy] = percent_subsidy
          end
        else
          direct_cost = ssr.direct_cost_total
          percent_subsidy = ssr.subsidy.stored_percent_subsidy
          contribution = (direct_cost * (percent_subsidy / 100.00)).ceil
          contribution = direct_cost - contribution
          values[:subsidy_attributes][:pi_contribution] = contribution
        end
      end
    end
  end

  def check_for_overridden ssr
    overridden = false
    if ssr.subsidy && ssr.subsidy.overridden
      overridden = true
    end

    overridden
  end

  # Document saves/updates
  def document_save_update errors
     #### save/update documents if we have them
    process_ssr_organization_ids = params[:process_ssr_organization_ids]
    document_id = params[:document_id]
    doc_object = Document.find(document_id) if document_id
    document = params[:document]
    doc_type = params[:doc_type]
    doc_type_other = params[:doc_type_other]
    upload_clicked = params[:upload_clicked]

    if doc_type and process_ssr_organization_ids and (document or document_id)
      # have all required ingredients for successful document
      if document_id # update existing document
        org_ids = doc_object.sub_service_requests.map{|ssr| ssr.organization_id.to_s}
        to_delete = org_ids - process_ssr_organization_ids
        to_add = process_ssr_organization_ids - org_ids

        # add access
        to_add.each do |org_id|
          sub_service_request = @service_request.sub_service_requests.find_or_create_by(:organization_id => org_id.to_i)
          sub_service_request.documents << doc_object
          sub_service_request.save
        end

        # remove access
        to_delete.each do |org_id|
          ssr = @service_request.sub_service_requests.find_by_organization_id org_id.to_i
          doc_object.sub_service_requests.delete ssr
          doc_object.reload
          doc_object.destroy if doc_object.sub_service_requests.empty?
        end

        # update document's attributes
        if doc_object
          if @sub_service_request and doc_object.sub_service_requests.size > 1
            new_doc = document ? document : doc_object.document # if no new document provided use the old document
            newDocument = Document.create :document => new_doc, :doc_type => params[:doc_type], :doc_type_other => params[:doc_type_other], :service_request_id => @service_request.id
            @sub_service_request.documents << newDocument
            @sub_service_request.documents.delete doc_object
            @sub_service_request.save
          else
            new_doc = document || doc_object.document
            doc_object.update_attributes(:document => new_doc, :doc_type => doc_type, :doc_type_other => doc_type_other)
          end
        end
      else # new document
        newDocument = Document.create :document => document, :doc_type => doc_type, :doc_type_other => doc_type_other, :service_request_id => @service_request.id
        process_ssr_organization_ids.each do |org_id|
          sub_service_request = @service_request.sub_service_requests.find_by_organization_id org_id.to_i
          sub_service_request.documents << newDocument
          sub_service_request.save
        end
      end
    elsif upload_clicked == "1" and ((doc_type == "" or !process_ssr_organization_ids) or ( !document and !document_id ))
      # collect errors
      doc_errors = {}
      doc_errors[:recipients] = ["You must select at least one recipient"] if !process_ssr_organization_ids
      doc_errors[:document] = ["You must select a document to upload"] if !document and !document_id
      doc_errors[:doc_type] = ["You must provide a document type"] if doc_type == ""
      errors << doc_errors
    end
    # end document saving stuff
  end

  def update_service_request_status(service_request, status)
    unless service_request.submitted_at?
      service_request.update_status(status)
      if (status == 'submitted')
        service_request.previous_submitted_at = @service_request.submitted_at
        service_request.update_attribute(:submitted_at, Time.now)
      end
    end
  end
end
