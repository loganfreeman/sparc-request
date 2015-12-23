module Portal::StudyLevelActivitiesHelper

  def sla_service_name_display line_item
    if line_item.service.is_available
      line_item.service.name
    else
      line_item.service.name + ' (Disabled)'
    end
  end

  def sla_cost_display line_item
    cost = number_with_precision(Service.cents_to_dollars(line_item.direct_costs_for_one_time_fee), :precision => 2)

    return "$#{cost}"
  end

  def sla_options_buttons line_item_id
    options = raw(
      content_tag(:li, raw(
        content_tag(:button, raw(content_tag(:span, '', class: "glyphicon glyphicon-sunglasses", aria: {hidden: "true"}))+' Details', type: 'button', class: 'btn btn-default form-control actions-button otf_details list'))
      )+
      content_tag(:li, raw(
        content_tag(:button, raw(content_tag(:span, '', class: "glyphicon glyphicon-list-alt", aria: {hidden: "true"}))+' Notes', type: 'button', class: 'btn btn-default form-control actions-button notes list', data: {notable_id: line_item_id, notable_type: "LineItem"}))
      )+
      content_tag(:li, raw(
        content_tag(:button, raw(content_tag(:span, '', class: "glyphicon glyphicon-usd", aria: {hidden: "true"}))+' Add Admin Rate', type: 'button', class: 'btn btn-default form-control actions-button otf_admin_rate'))
      )+
      content_tag(:li, raw(
        content_tag(:button, raw(content_tag(:span, '', class: "glyphicon glyphicon-edit", aria: {hidden: "true"}))+' Edit Activity', type: 'button', class: 'btn btn-default form-control actions-button otf_edit'))
      )+
      content_tag(:li, raw(
        content_tag(:button, raw(content_tag(:span, '', class: "glyphicon glyphicon-remove", aria: {hidden: "true"}))+' Delete Activity', type: 'button', class: 'btn btn-default form-control actions-button otf_delete'))
      )
    )

    span = raw content_tag(:span, '', class: 'glyphicon glyphicon-triangle-bottom')
    button = raw content_tag(:button, raw(span), type: 'button', class: 'btn btn-default btn-sm dropdown-toggle form-control available-actions-button', 'data-toggle' => 'dropdown', 'aria-expanded' => 'false')
    ul = raw content_tag(:ul, options, class: 'dropdown-menu', role: 'menu')

    raw content_tag(:div, button + ul, class: 'btn-group overflow_webkit_button')
  end

  def sla_form_services_select form, line_item
    service = line_item.service
    if service.present? and not service.is_available
      service_name = service.name + ' (Disabled)'
      form.select "service_id", options_for_select([service_name], service_name), {include_blank: true}, class: 'form-control selectpicker', disabled: 'disabled'
    else
      service_list = line_item.sub_service_request.candidate_services.select {|x| x.one_time_fee}
      form.select "service_id", options_from_collection_for_select(service_list, 'id', 'name', line_item.service_id), {include_blank: true}, class: 'form-control selectpicker'
    end
  end

  def fulfillments_drop_button line_item_id
    content_tag(:button, class: 'btn btn-primary btn-sm otf_fulfillments list', title: "View Fulfillments", type: "button", aria: {label: "Fulfillments List"}, data: {toggle: "tooltip", animation: 'false'}) do
      content_tag(:span, '', class: "glyphicon glyphicon-chevron-right", aria: {hidden: "true"})
    end
  end

  def fulfillment_options_buttons fulfillment_id
    options = raw(
      content_tag(:li, raw(
        content_tag(:button, raw(content_tag(:span, '', class: "glyphicon glyphicon-list-alt", aria: {hidden: "true"}))+' Notes', type: 'button', class: 'btn btn-default form-control actions-button notes list', data: {notable_id: fulfillment_id, notable_type: "Fulfillment"}))
      )+
      content_tag(:li, raw(
        content_tag(:button, raw(content_tag(:span, '', class: "glyphicon glyphicon-edit", aria: {hidden: "true"}))+' Edit Fulfillment', type: 'button', class: 'btn btn-default form-control actions-button otf_fulfillment_edit'))
      )+
      content_tag(:li, raw(
        content_tag(:button, raw(content_tag(:span, '', class: "glyphicon glyphicon-remove", aria: {hidden: "true"}))+' Delete Fulfillment', type: 'button', class: 'btn btn-default form-control actions-button otf_fulfillment_delete'))
      )
    )

    span = raw content_tag(:span, '', class: 'glyphicon glyphicon-triangle-bottom')
    button = raw content_tag(:button, raw(span), type: 'button', class: 'btn btn-default btn-sm dropdown-toggle form-control available-actions-button', 'data-toggle' => 'dropdown', 'aria-expanded' => 'false')
    ul = raw content_tag(:ul, options, class: 'dropdown-menu', role: 'menu')

    raw content_tag(:div, button + ul, class: 'btn-group')
  end
end