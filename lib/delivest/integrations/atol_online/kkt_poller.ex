defmodule Delivest.Integrations.AtolOnline.KktPoller do
  @behaviour Delivest.Integrations.Poller

  import Ecto.Query

  alias Delivest.Fiscal.BranchSettings
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.{AtolOnline, Health, Journal}
  alias Delivest.Integrations.AtolOnline.{Api, Kkt}
  alias Delivest.Repo

  @provider :atol

  @impl true
  def key, do: :atol_kkt

  @impl true
  def interval, do: 3600

  @impl true
  def targets do
    from(i in BranchInfo, select: {i.branch_id, i.fiscal})
    |> Repo.all()
    |> Enum.filter(fn {_id, fiscal} -> monitored?(fiscal) end)
    |> Enum.map(&elem(&1, 0))
  end

  @impl true
  def poll(branch_id) do
    case Delivest.Fiscal.settings(branch_id) do
      %BranchSettings{atol: %AtolOnline.Settings{} = settings} = fiscal ->
        if monitored?(fiscal), do: check(branch_id, settings), else: :done

      _settings ->
        :done
    end
  end

  defp check(branch_id, settings) do
    case Journal.scope([branch_id: branch_id], fn -> Api.kkt_info(settings) end) do
      {:ok, registers} -> report(branch_id, Kkt.issues(registers))
      {:error, _reason} = error -> error
    end
  end

  defp report(branch_id, []) do
    Health.clear_warning(@provider, branch_id)
    :done
  end

  defp report(branch_id, issues) do
    Health.warn(@provider, branch_id, "kkt_issues:" <> Enum.join(issues, ","))
    :done
  end

  defp monitored?(%BranchSettings{mode: :own, atol: %AtolOnline.Settings{sandbox: false}}),
    do: true

  defp monitored?(_fiscal), do: false
end
