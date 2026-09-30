class Crm::Hubspot::CreateLeadJob < ApplicationJob
  queue_as :low

  def perform(conversation)
    Crm::Hubspot::LeadCreationService.new(conversation).perform
  end
end
