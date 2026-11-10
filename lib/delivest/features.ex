defmodule Delivest.Features do
  @moduledoc "Host-managed feature gates for one franchise and its branches."
  import Ecto.Query

  alias Delivest.{Background, Repo}
  alias Delivest.Features.Gate
  alias Delivest.Identity.Branch

  @features ["segments"]

  def enabled?(feature, scope), do: match?({:ok, _}, snapshot(feature, scope))

  def snapshot(feature, scope) do
    with {:ok, key} <- scope_key(scope),
         true <- feature in @features,
         :ok <- valid_branch(scope) do
      parent = Repo.get_by(Gate, feature: feature, scope_key: "franchise")

      child =
        if key == "franchise", do: nil, else: Repo.get_by(Gate, feature: feature, scope_key: key)

      if parent && parent.enabled && (key == "franchise" || (child && child.enabled)) do
        {:ok, %{franchise: parent.generation, branch: if(child, do: child.generation)}}
      else
        {:error, :disabled}
      end
    else
      _ -> {:error, :disabled}
    end
  end

  def still_enabled?(feature, scope, generation),
    do: snapshot(feature, scope) == {:ok, generation}

  @doc "Short, locked transaction for publishing a result calculated at a captured generation."
  def with_enabled(feature, scope, generation, fun) when is_function(fun, 0) do
    with {:ok, key} <- scope_key(scope),
         true <- feature in @features,
         :ok <- valid_branch(scope) do
      Repo.transaction(fn ->
        parent = locked_gate(feature, "franchise")
        child = if key == "franchise", do: nil, else: locked_gate(feature, key)

        valid? =
          parent && parent.enabled && parent.generation == generation.franchise &&
            (key == "franchise" ||
               (child && child.enabled && child.generation == generation.branch))

        if valid?, do: fun.(), else: Repo.rollback(:disabled)
      end)
    else
      _ -> {:error, :disabled}
    end
  end

  @doc "Only call from the host Release command; no staff endpoint delegates to this function."
  def configure(feature, scope, enabled, opts)
      when feature in @features and is_boolean(enabled) and is_list(opts) do
    with {:ok, key} <- scope_key(scope),
         actor when is_binary(actor) and byte_size(actor) > 0 <- Keyword.get(opts, :actor),
         :ok <- valid_branch(scope) do
      Repo.transaction(fn ->
        # The parent gate serializes parent and branch changes, including initial branch insertion.
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        Repo.insert_all(
          Gate,
          [
            %{
              feature: feature,
              scope_key: "franchise",
              enabled: false,
              generation: 0,
              inserted_at: now,
              updated_at: now
            }
          ], on_conflict: :nothing, conflict_target: [:feature, :scope_key])

        parent = locked_gate(feature, "franchise")
        gate = if key == "franchise", do: parent, else: locked_gate(feature, key)
        gate = gate || Repo.insert!(%Gate{feature: feature, scope_key: key})

        if gate.enabled == enabled do
          gate
        else
          updated =
            Repo.update!(
              Ecto.Changeset.change(gate, enabled: enabled, generation: gate.generation + 1)
            )

          Repo.insert_all("feature_audits", [
            %{
              feature: feature,
              scope_key: key,
              enabled: enabled,
              generation: updated.generation,
              actor: actor,
              inserted_at: now
            }
          ])

          if key != "franchise" do
            Repo.update!(Ecto.Changeset.change(parent, generation: parent.generation + 1))
          end

          Background.feature_changed(feature, scope, enabled)
          updated
        end
      end)
    else
      _ -> {:error, :invalid_configuration}
    end
  end

  def configure(_feature, _scope, _enabled, _opts), do: {:error, :invalid_configuration}

  defp locked_gate(feature, key) do
    Repo.one(
      from g in Gate, where: g.feature == ^feature and g.scope_key == ^key, lock: "FOR UPDATE"
    )
  end

  defp valid_branch(:franchise), do: :ok

  defp valid_branch({:branch, id}) do
    {:ok, "branch:" <> canonical} = scope_key({:branch, id})

    if Repo.exists?(from b in Branch, where: b.id == ^canonical and is_nil(b.deleted_at)),
      do: :ok,
      else: {:error, :unknown_branch}
  end

  def scope_key(:franchise), do: {:ok, "franchise"}

  def scope_key({:branch, id}) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, canonical} -> {:ok, "branch:" <> canonical}
      :error -> {:error, :invalid_scope}
    end
  end

  def scope_key(_), do: {:error, :invalid_scope}

  def parse_scope("franchise"), do: :franchise
  def parse_scope("branch:" <> id), do: {:branch, id}
end
