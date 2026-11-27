defmodule Delivest.Media.Workers.ThumbnailWorker do
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [keys: [:file_id], period: :infinity, states: :incomplete]

  alias Delivest.Media
  alias Delivest.Media.{File, Thumbnails}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_id" => id}}) do
    case Media.get_file(id) do
      %File{} = file -> if Thumbnails.missing?(file), do: store(file), else: :ok
      _done_or_deleted -> :ok
    end
  end

  defp store(file) do
    case Thumbnails.store(file) do
      {:ok, _file} -> :ok
      {:error, :invalid_image} -> {:cancel, :invalid_image}
      {:error, reason} -> {:error, reason}
    end
  end
end
