class Dispatcher
  include Singleton

  attr_reader :async_dispatcher, :sync_dispatcher

  def self.dispatch(event_name, timestamp, data, async = false)
    Rails.configuration.dispatcher.dispatch(event_name, timestamp, data, async)
  end

  def initialize
    @sync_dispatcher = SyncDispatcher.new
    @async_dispatcher = AsyncDispatcher.new
  end

  # Records recreated from history were already seen and acted on where they happened;
  # dispatching them would replay webhooks, automations and notifications for old news.
  def self.silently
    previous = Current.events_silenced
    Current.events_silenced = true
    yield
  ensure
    Current.events_silenced = previous
  end

  def dispatch(event_name, timestamp, data, _async = false)
    return if Current.events_silenced

    @sync_dispatcher.dispatch(event_name, timestamp, data)
    @async_dispatcher.dispatch(event_name, timestamp, data)
  end

  def load_listeners
    @sync_dispatcher.load_listeners
    @async_dispatcher.load_listeners
  end
end
