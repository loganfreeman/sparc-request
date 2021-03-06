class AddOriginalSubmittedDateToServiceRequest < ActiveRecord::Migration
  def change
    add_column :service_requests, :original_submitted_date, :date

    ServiceRequest.where.not(submitted_at: nil).each do |sr|
      sr.original_submitted_date = sr.submitted_at
      sr.save!(validate: false)
    end
  end
end
