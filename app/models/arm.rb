class Arm < ActiveRecord::Base
  audited

  belongs_to :service_request

  has_many :visit_groupings, :dependent => :destroy
  has_many :line_items, :through => :visit_groupings

  attr_accessible :name
  attr_accessible :visit_count
  attr_accessible :subject_count      # maximum number of subjects for any visit grouping

  after_save :fix_visit_grouping_subject_counts

  def fix_visit_grouping_subject_counts
    if self.subject_count_changed?
      self.visit_groupings.each do |vg|
        if vg.subject_count == self.subject_count_was
          vg.update_attributes(:subject_count => self.subject_count)
        end
      end
    end
  end

  def create_visit_grouping line_item
    vg = self.visit_groupings.create(:line_item_id => line_item.id, :arm_id => self.id, :subject_count => self.subject_count)
    vg.create_or_destroy_visits

    if visit_groupings.count > 1
      vg.update_visit_names self.visit_groupings.first
    end
  end

  def per_patient_per_visit_line_items
    visit_groupings.each.map do |vg|
      vg.line_item
    end.compact
  end

  def maximum_direct_costs_per_patient visit_groupings=self.visit_groupings
    total = 0.0
    visit_groupings.each do |vg|
      total += vg.direct_costs_for_visit_based_service_single_subject
    end

    total
  end

  def maximum_indirect_costs_per_patient visit_groupings=self.visit_groupings
    if USE_INDIRECT_COST
      self.maximum_direct_costs_per_patient(visit_groupings) * (self.service_request.protocol.indirect_cost_rate.to_f / 100)
    else
      return 0
    end
  end

  def maximum_total_per_patient visit_groupings=self.visit_groupings
    self.maximum_direct_costs_per_patient(visit_groupings) + maximum_indirect_costs_per_patient(visit_groupings)
  end

  def direct_costs_for_visit_based_service
    total = 0.0
    visit_groupings.each do |vg|
      total += vg.direct_costs_for_visit_based_service
    end
    return total
  end

  def indirect_costs_for_visit_based_service
    total = 0.0
    visit_groupings.each do |vg|
      total += vg.indirect_costs_for_visit_based_service
    end
    return total
  end

  def total_costs_for_visit_based_service
    direct_costs_for_visit_based_service + indirect_costs_for_visit_based_service
  end
  
  # Add a single visit.  Returns true upon success and false upon
  # failure.  If there is a failure, any changes are rolled back.
  # 
  # TODO: I don't quite like the way this is written.  Perhaps we should
  # rename this method to add_visit! and make it raise exceptions; it
  # would be easier to read.  But I'm not sure how to get access to the
  # errors object in that case.
  def add_visit position=nil
    result = self.transaction do
      # Add visits to each line item under the service request
      self.visit_groupings.each do |vg|
        if not vg.add_visit(position) then
          self.errors.initialize_dup(vg.errors) # TODO: is this the right way to do this?
          raise ActiveRecord::Rollback
        end
      end

      # Reload to force refresh of the visits
      self.reload

      self.visit_count ||= 0 # in case we import a service request with nil visit count
      self.visit_count += 1

      self.save or raise ActiveRecord::Rollback
    end

    if result then
      return true
    else
      self.reload
      return false
    end
  end

  def remove_visit position
    result = self.transaction do
      self.visit_groupings.each do |vg|
        if not vg.remove_visit(position) then
          self.errors.initialize_dup(vg.errors)
          raise ActiveRecord::Rollback
        end
      end

      self.reload

      self.visit_count -= 1

      self.save or raise ActiveRecord::Rollback
    end
    
    if result
      return true
    else
      self.reload
      return false
    end
  end

  def insure_visit_count
    if self.visit_count.nil? or self.visit_count <= 0
      self.update_attribute(:visit_count, 1)
      self.reload
    end
  end

  def insure_subject_count
    if subject_count.nil? or subject_count < 0
      self.update_attribute(:subject_count, 1)
      self.reload
    end
  end
end
