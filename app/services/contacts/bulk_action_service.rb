class Contacts::BulkActionService
  def initialize(account:, user:, params:)
    @account = account
    @user = user
    @params = params.deep_symbolize_keys
  end

  def perform
    # Deleting is only ever done on contacts someone ticked one by one.
    return { success: false, error: 'filter_not_allowed_for_delete' } if delete_requested? && filter.present?
    return delete_contacts if delete_requested?
    return assign_labels if labels_to_add.any?
    return remove_labels if labels_to_remove.any?

    Rails.logger.warn("Unknown contact bulk operation payload: #{@params.keys}")
    { success: false, error: 'unknown_operation' }
  end

  private

  def assign_labels
    Contacts::BulkAssignLabelsService.new(
      account: @account,
      contact_ids: ids,
      labels: labels_to_add
    ).perform
  end

  def remove_labels
    Contacts::BulkRemoveLabelsService.new(
      account: @account,
      contact_ids: ids,
      labels: labels_to_remove
    ).perform
  end

  def delete_contacts
    Contacts::BulkDeleteService.new(
      account: @account,
      contact_ids: ids
    ).perform
  end

  # "Select all" on a filtered list sends the filter instead of ids, so a label reaches every
  # contact that matches it and not only the page on screen, minus anyone unticked after.
  def ids
    if filter.present?
      return Contacts::FilterService.new(@account, @user, filter).perform[:contacts].pluck(:id) - Array(@params[:exclude_ids]).map(&:to_i)
    end

    Array(@params[:ids]).compact
  end

  def filter
    @params[:filter].presence&.deep_stringify_keys&.with_indifferent_access
  end

  def labels_to_add
    @labels_to_add ||= Array(@params.dig(:labels, :add)).reject(&:blank?)
  end

  def labels_to_remove
    @labels_to_remove ||= Array(@params.dig(:labels, :remove)).reject(&:blank?)
  end

  def delete_requested?
    @params[:action_name] == 'delete'
  end
end
