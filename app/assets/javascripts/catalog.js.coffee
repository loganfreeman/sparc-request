#= require cart

loadDescription = (url) ->
  $.ajax
    type: 'POST'
    url: url

$(document).ready ->

  $('#institution_accordion').accordion
    autoHeight: false
    collapsible: true
    change: (event, ui)->
      if url = (ui.newHeader.find('a').attr('href') or ui.oldHeader.find('a').attr('href'))
        loadDescription(url)

  $('.provider_accordion').accordion
    autoHeight: false
    collapsible: true
    active: false
    change: (event, ui)->
      if url = (ui.newHeader.find('a').attr('href') or ui.oldHeader.find('a').attr('href'))
        loadDescription(url)
  

  $('.title .name a').live 'click', ->
    $(this).parents('.title').siblings('.service-description').toggle()


  autoComplete = $('#service_query').autocomplete
    source: '/search/services'
    minLength: 2
    search: (event, ui) ->
      $('.catalog-search-clear-icon').remove()
      $("#service_query").after('<img src="/assets/spinner.gif" class="catalog-search-spinner" />')
    open: (event, ui) ->
      $('.catalog-search-spinner').remove()
      $("#service_query").after('<img src="/assets/clear_icon.png" class="catalog-search-clear-icon" />')
      $('.service-name').qtip
        content: { text: false}
        position:
          corner:
            target: "rightMiddle"
            tooltip: "leftMiddle"

          adjust: screen: true

        show:
          delay: 0
          when: "mouseover"
          solo: true

        hide:
          delay: 0
          when: "mouseout"
          solo: true
        
        style:
          tip: true
          border:
            width: 0
            radius: 4

          name: "light"
          width: 250

    close: (event, ui) ->
      $('.catalog-search-spinner').remove()
      $('.catalog-search-clear-icon').remove()

  .data("autocomplete")._renderItem = (ul, item) ->
    if item.label == 'No Results'
      $("<li class='search_result'></li>")
      .data("item.autocomplete", item)
      .append("#{item.label}")
      .appendTo(ul)
    else
      $("<li class='search_result'></li>")
      .data("item.autocomplete", item)
      .append("#{item.parents}<br><span class='service-name' title='#{item.description}'>#{item.label}</span><br><button id='service-#{item.value}' sr_id='#{item.sr_id}' style='font-size: 11px;' class='add_service'>Add to Cart</button><span class='service-description'>#{item.description}</span>")
      .appendTo(ul)
  
  $('.catalog-search-clear-icon').live 'click', ->
    $("#service_query").autocomplete("close")
    $("#service_query").clearFields()

  $('.submit-request-button').click ->
    if $('#line_item_count').val() <= 0
      $('#submit_error').dialog
        modal: true
        buttons:
            Ok: ->
              $(this).dialog('close')
      return false

  $('#sign_in').dialog
    modal: true
    title: "Please select one of the options below:"
    width: 800
    height: 400
    #dialogClass: 'no-close'
