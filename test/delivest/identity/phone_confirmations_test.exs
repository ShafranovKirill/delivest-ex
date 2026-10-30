defmodule Delivest.Identity.PhoneConfirmationsTest do
  use Delivest.DataCase, async: true

  alias Delivest.Identity.{PhoneConfirmation, PhoneConfirmations}
  alias Delivest.Logs.PruneWorker

  defp confirmation(days_ago) do
    at = DateTime.utc_now(:second) |> DateTime.add(-days_ago, :day)

    {:ok, confirmation} =
      PhoneConfirmations.create(%{
        phone: "+79991234567",
        session_id: "s",
        call_id: "c-#{System.unique_integer([:positive])}",
        call_number: "7800"
      })

    confirmation |> Ecto.Changeset.change(inserted_at: at) |> Repo.update!()
  end

  test "the daily prune removes old confirmations and keeps fresh ones" do
    old = confirmation(8)
    fresh = confirmation(1)

    assert {:ok, %{confirmations: count}} = PruneWorker.perform(%Oban.Job{})
    assert count >= 1
    refute Repo.get(PhoneConfirmation, old.id)
    assert Repo.get(PhoneConfirmation, fresh.id)
  end
end
