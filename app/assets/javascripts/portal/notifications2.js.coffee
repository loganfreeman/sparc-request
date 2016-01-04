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

$(document).ready ->

  $(document).on('click', '.new_notification', ->
    sub_service_request_id = $(this).data('sub-service-request-id')
    identity_id = $(this).data('identity-id')
    is_service_provider = $(this).data('is-service-provider')
    current_user_id = $(this).data('current-user-id')

    if current_user_id == identity_id
      alert("You can not send a message to yourself.")
    else
      data =
        "sub_service_request_id"  : sub_service_request_id
        "identity_id"             : identity_id
        "is_service_provider"     : is_service_provider
      $.ajax
        type: 'GET'
        url:  "/portal/notifications/new"
        data: data
  )

  $(document).on('click', '.notifications_row > .from,.subject,.preview,.time', ->
    #if you click on the row, it opens the notification show
    row_index   = $(this).parents("tr").data("index")
    notification_id = $(this).parents("table.notifications_table").bootstrapTable("getData")[row_index].id
    data =
      'notification_id': notification_id
    $.ajax
      type: 'GET'
      url: "/portal/messages"
      data: data
  )

  $(document).on('click', '.notifications_row > .bs-checkbox', ->
    #clicks checkbox if you click in the same td
    $(this).children("input[type='checkbox']").trigger('click')
  )

  $(document).on 'click', 'button.message.new',  ->
    data = notification_id: $(this).data('notification-id')
    $.ajax
      type: 'GET'
      url: '/portal/messages/new'
      data: data

  $('.notifications-link .hyperlink').live('click', ->
    $('.notifications-link .notifications_popup').toggle('blind')
  )

  $(document).on('click', '.new-portal-notification-button', ->
    ssr_id = $(this).attr('data-ssr_id')
    sr_id = $(this).attr('data-sr_id')
    if $(this).hasClass('active')
      $(this).removeClass('active')
    else
      $(this).addClass('active')

    $("#portal_notifications_#{ssr_id}_#{sr_id}").slideToggle()
  )

  $(document).on 'click', 'button.mark_as_read_unread',  ->
    selections = $("#notifications-table").bootstrapTable 'getSelections'
    notification_ids = selections.map( (hash, i) -> return hash['id'] )
    if notification_ids.length > 0
      read_or_unread = $(this).data('read')
      data =
        'notification_ids'  : notification_ids
        'read'              : read_or_unread
      $.ajax
        type: 'PUT'
        url: '/portal/notifications/mark_as_read'
        data: data

  $(document).on 'click', 'button#notifications_sent',  ->
    $(".notification_nav").removeClass('btn-primary').addClass('btn-default').find(".glyphicon-refresh").hide()
    $(this).removeClass('btn-default').addClass('btn-primary').find(".glyphicon-refresh").show()
    $("#notification_tabs").data("selected", "sent")
    $("#notifications-table").bootstrapTable 'refresh', {query: {table: "sent"}}

  $(document).on 'click', 'button#notifications_inbox',  ->
    $(".notification_nav").removeClass('btn-primary').addClass('btn-default').find(".glyphicon-refresh").hide()
    $(this).removeClass('btn-default').addClass('btn-primary').find(".glyphicon-refresh").show()
    $("#notification_tabs").data("selected", "inbox")
    $("#notifications-table").bootstrapTable 'refresh', {query: {table: "inbox"}}

  window.notifications_row_style = (row, index) ->
    class_string = 'notifications_row'
    if not row.read
      #makes unread messages appear green in notifications bs table
      class_string += ' success'
    return { classes: class_string }

  window.refresh_notifications_table = ->
    table = $("#notification_tabs").data("selected")
    $("#notifications-table").bootstrapTable 'refresh', {query: {table: "#{table}"}}
