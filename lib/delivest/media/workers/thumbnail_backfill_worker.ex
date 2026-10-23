defmodule Delivest.Media.Workers.ThumbnailBackfillWorker do
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Delivest.Media.Thumbnails

  @impl Oban.Worker
  def perform(_job), do: Thumbnails.enqueue_missing()
end
