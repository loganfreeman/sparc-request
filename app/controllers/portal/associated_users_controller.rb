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

class Portal::AssociatedUsersController < Portal::BaseController
  layout nil

  respond_to :html, :json, :js
  before_filter :find_project, :only => [:show, :edit, :new, :create, :update]
  before_filter :protocol_authorizer_view, :only => [:show]
  before_filter :protocol_authorizer_edit, :only => [:edit, :new, :create, :update]

  def show
    # TODO: is it right to call to_i here?
    # TODO: id here should be the id of a project role, not an identity
    project_role = @protocol.project_roles.find {|role| role.identity.id == params[:id].to_i}
    @user = project_role.try(:identity)
    render :nothing => true # TODO: looks like there's no view for show
  end

  def edit
    @identity = Identity.find params[:identity_id]
    @protocol_role = ProjectRole.find params[:id]
    @protocol_role.populate_for_edit
    @sub_service_request = SubServiceRequest.find params[:sub_service_request_id] if params[:sub_service_request_id]
    respond_to do |format|
      format.js
      format.html
    end
  end

  # TODO: why does edit use identity_id, but new uses user_id?
  def new
    @identity = Identity.find params[:user_id]
    @protocol_role = @protocol.project_roles.build(:identity_id => @identity.id)
    @protocol_role.populate_for_edit
    if params[:sub_service_request_id]
      @sub_service_request = SubServiceRequest.find(params[:sub_service_request_id])
    end
    respond_to do |format|
      format.js
      format.html
    end
  end

  def create
    @protocol_role = @protocol.project_roles.build(params[:project_role])
    @protocol_role.identity.assign_attributes params[:identity]
    @identity = Identity.find @protocol_role.identity_id

    if @protocol_role.unique_to_protocol? && @protocol_role.fully_valid?
      if params[:change_primary_pi] == "true"
        ProjectRole.find(params[:primary_pi_pr_id]).update_attributes(project_rights: "request", role: "general-access-user")
      end
      @protocol_role.save
      @identity.update_attributes params[:identity]
      if SEND_AUTHORIZED_USER_EMAILS
        @protocol.emailed_associated_users.each do |project_role|
          UserMailer.authorized_user_changed(project_role.identity, @protocol).deliver_now unless project_role.identity.email.blank?
        end
      end

      if USE_EPIC
        if @protocol.selected_for_epic
          Notifier.notify_for_epic_user_approval(@protocol).deliver unless QUEUE_EPIC
        end
      end
    end

    if params[:sub_service_request_id]
      @sub_service_request = SubServiceRequest.find(params[:sub_service_request_id])
      @protocol = @sub_service_request.service_request.protocol
      render 'portal/admin/create_authorized_users'
    else
      respond_to do |format|
        format.js
        format.html
      end
    end
  end

  def update
    @protocol_role = ProjectRole.find params[:id]    
    @protocol_role.identity.assign_attributes params[:identity]
    @identity = Identity.find @protocol_role.identity_id

    epic_access = @protocol_role.epic_access
    epic_rights = @protocol_role.epic_rights.clone
    @protocol_role.assign_attributes params[:project_role]

    if @protocol_role.fully_valid?
      if params[:change_primary_pi] == "true"
        ProjectRole.find(params[:primary_pi_pr_id]).update_attributes(project_rights: "request", role: "general-access-user")
      end
      @protocol_role.save
      @identity.update_attributes params[:identity]
      if SEND_AUTHORIZED_USER_EMAILS
        @protocol.emailed_associated_users.each do |project_role|
          UserMailer.authorized_user_changed(project_role.identity, @protocol).deliver_now unless project_role.identity.email.blank?
        end
      end

      if USE_EPIC
        if @protocol.selected_for_epic
          if epic_access and not @protocol_role.epic_access
            # Access has been removed
            Notifier.notify_for_epic_access_removal(@protocol, @protocol_role).deliver unless QUEUE_EPIC
          elsif @protocol_role.epic_access and not epic_access
            # Access has been granted
            Notifier.notify_for_epic_user_approval(@protocol).deliver unless QUEUE_EPIC
          elsif epic_rights != @protocol_role.epic_rights
            # Rights has been changed
            Notifier.notify_for_epic_rights_changes(@protocol, @protocol_role, epic_rights).deliver unless QUEUE_EPIC
          end
        end
      end
    end

    if params[:sub_service_request_id]
      @protocol = Protocol.find(params[:protocol_id])
      @sub_service_request = SubServiceRequest.find(params[:sub_service_request_id])
      render 'portal/admin/update_authorized_users'
    else
      respond_to do |format|
        format.js
        format.html
      end
    end
  end

  def destroy
    @protocol_role = ProjectRole.find params[:id]
    protocol = @protocol_role.protocol
    epic_access = @protocol_role.epic_access
    project_role_clone = @protocol_role.clone
    @protocol_role.destroy

    if USE_EPIC
      if protocol.selected_for_epic
        if epic_access
          Notifier.notify_primary_pi_for_epic_user_removal(protocol, project_role_clone).deliver unless QUEUE_EPIC
        end
      end
    end

    if params[:sub_service_request_id]
      @sub_service_request = SubServiceRequest.find(params[:sub_service_request_id])
      @protocol = @sub_service_request.service_request.protocol
      render 'portal/admin/destroy_authorized_users'
    else
      respond_to do |format|
        format.js
        format.html
      end
    end
  end

  def search
    term = params[:term].strip
    results = Identity.search(term).map do |i|
      {
       :label => i.display_name, :value => i.id, :email => i.email, :institution => i.institution, :phone => i.phone, :era_commons_name => i.era_commons_name,
       :college => i.college, :department => i.department, :credentials => i.credentials, :credentials_other => i.credentials_other
      }
    end

    # TODO: this behavior is particularly annoying.  If I backspace over
    # the "No results" in the search box, then I don't type something
    # new quickly enough, it displays "No results" again.  I suppose we
    # should highlight "No results" so that typing something new will
    # automatically overwrite it.
    results = [{:label => 'No Results'}] if results.empty?

    render :json => results.to_json
  end

private
  def find_project
    @protocol = Protocol.find(params[:protocol_id])
  end
end
