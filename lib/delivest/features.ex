defmodule Delivest.Features do
  @moduledoc "Host-managed feature gates for one franchise and its branches."
  import Ecto.Query

  alias Delivest.{Background, Repo}
  alias Delivest.Features.{Gate, Registry}
  alias Delivest.Identity.Branch

  def enabled?(feature, scope), do: match?({:ok, _}, snapshot(feature, scope))

  @doc "Read a feature's dependency gates for many known branch IDs in one database snapshot."
  def enabled_branches(feature, ids) when is_list(ids) do
    if Registry.known?(feature) do
      canonical =
        ids
        |> Enum.flat_map(fn id ->
          case Ecto.UUID.cast(id) do
            {:ok, value} -> [value]
            _ -> []
          end
        end)
        |> Enum.uniq()

      keys = ["franchise" | Enum.map(canonical, &("branch:" <> &1))]
      names = closure(feature)

      gates =
        Repo.all(
          from g in Gate,
            where: g.feature in ^names and g.scope_key in ^keys
        )
        |> Map.new(&{{&1.feature, &1.scope_key}, &1})

      canonical
      |> Enum.filter(fn id ->
        key = "branch:" <> id
        Enum.all?(names, &enabled_in?(&1, key, gates))
      end)
      |> MapSet.new()
    else
      MapSet.new()
    end
  end

  def enabled_branches(_, _), do: MapSet.new()

  def snapshot(feature, scope) do
    with {:ok, key} <- scope_key(scope),
         true <- Registry.known?(feature),
         :ok <- valid_branch(scope) do
      gates = read_gates(closure(feature), key)
      parent = gates[{feature, "franchise"}]
      child = if key == "franchise", do: nil, else: gates[{feature, key}]

      if Enum.all?(closure(feature), &enabled_in?(&1, key, gates)) do
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

  @doc "Lock the complete dependency closure in canonical order for a short publication."
  def with_enabled(feature, scope, generation, fun) when is_function(fun, 0) do
    with_enabled_many([{feature, scope, generation}], fun)
  end

  @doc "Publish under the union of feature dependencies, locking each gate once in canonical order."
  def with_enabled_many(requests, fun)
      when is_list(requests) and requests != [] and is_function(fun, 0) do
    prepared =
      Enum.reduce_while(requests, {:ok, []}, fn {feature, scope, token}, {:ok, acc} ->
        with true <- Registry.known?(feature),
             {:ok, key} <- scope_key(scope),
             :ok <- valid_branch(scope),
             %{franchise: franchise} <- token,
             true <- is_integer(franchise) do
          {:cont, {:ok, [{feature, key, token} | acc]}}
        else
          _ -> {:halt, {:error, :disabled}}
        end
      end)

    with {:ok, entries} <- prepared do
      Repo.transaction(fn ->
        gate_keys =
          entries
          |> Enum.flat_map(fn {feature, key, _} ->
            for name <- closure(feature),
                scope_key <- Enum.uniq(["franchise", key]),
                do: {name, scope_key}
          end)
          |> Enum.uniq()
          |> Enum.sort()

        gates = lock_keys(gate_keys)

        valid =
          Enum.all?(entries, fn {feature, key, token} ->
            parent = gates[{feature, "franchise"}]
            child = gates[{feature, key}]

            ((Enum.all?(closure(feature), &enabled_in?(&1, key, gates)) and
                parent) && parent.generation == token.franchise) and
              (key == "franchise" or (child && child.generation == token.branch))
          end)

        if valid, do: fun.(), else: Repo.rollback(:disabled)
      end)
    else
      _ -> {:error, :disabled}
    end
  end

  def with_enabled_many(_, _), do: {:error, :disabled}

  @doc "Host-only mutation. Dependencies enable together; disabling requires a matching dependent preview."
  def configure(feature, scope, enabled, opts) when is_boolean(enabled) and is_list(opts) do
    with {:ok, key} <- scope_key(scope),
         true <- Registry.known?(feature),
         actor when is_binary(actor) and byte_size(actor) > 0 <- Keyword.get(opts, :actor),
         :ok <- valid_branch(scope) do
      changes =
        if enabled,
          do: closure(feature),
          else: [feature | transitive_dependents(feature)] |> Enum.uniq()

      Repo.transaction(fn ->
        gates = ensure_and_lock(changes, key)

        active_dependents =
          Enum.filter(transitive_dependents(feature), &enabled_in?(&1, key, gates))

        preview = dependent_preview(feature, key, gates)

        if not enabled and active_dependents != [] and
             Keyword.get(opts, :confirm_dependents) != preview,
           do: Repo.rollback({:dependent_features, preview})

        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
        order = if enabled, do: changes, else: Enum.reverse(changes)

        Enum.each(order, fn name ->
          gate = gates[{name, key}]

          if gate.enabled != enabled do
            updated =
              Repo.update!(
                Ecto.Changeset.change(gate, enabled: enabled, generation: gate.generation + 1)
              )

            Repo.insert_all("feature_audits", [
              %{
                feature: name,
                scope_key: key,
                enabled: enabled,
                generation: updated.generation,
                actor: actor,
                inserted_at: now
              }
            ])

            if key != "franchise" do
              Repo.update_all(
                from(g in Gate,
                  where: g.feature == ^name and g.scope_key == "franchise"
                ),
                inc: [generation: 1]
              )
            end

            Background.feature_changed(name, scope, enabled)
          end
        end)

        Repo.get_by!(Gate, feature: feature, scope_key: key)
      end)
    else
      _ -> {:error, :invalid_configuration}
    end
  end

  def configure(_feature, _scope, _enabled, _opts), do: {:error, :invalid_configuration}

  def disable_preview(feature, scope) do
    with {:ok, key} <- scope_key(scope), true <- Registry.known?(feature) do
      names = [feature | transitive_dependents(feature)]
      gates = read_gates(names, key)
      {:ok, dependent_preview(feature, key, gates)}
    else
      _ -> {:error, :invalid_configuration}
    end
  end

  defp dependent_preview(feature, key, gates) do
    dependents =
      transitive_dependents(feature)
      |> Enum.filter(&enabled_in?(&1, key, gates))
      |> Enum.sort()

    fingerprint =
      [feature | transitive_dependents(feature)]
      |> Enum.sort()
      |> Enum.flat_map(fn name ->
        for scope <- Enum.uniq(["franchise", key]) do
          gate = gates[{name, scope}]
          {name, scope, gate && gate.enabled, gate && gate.generation}
        end
      end)
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %{features: dependents, fingerprint: fingerprint}
  end

  defp closure(feature),
    do:
      Registry.dependencies(feature)
      |> Enum.flat_map(&closure/1)
      |> Kernel.++([feature])
      |> Enum.uniq()

  defp transitive_dependents(feature),
    do:
      Registry.dependents(feature)
      |> Enum.flat_map(&[&1 | transitive_dependents(&1)])
      |> Enum.uniq()

  defp enabled_in?(name, key, gates) do
    parent = gates[{name, "franchise"}]
    child = gates[{name, key}]
    parent && parent.enabled && child && child.enabled
  end

  defp ensure_and_lock(names, key) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    entries =
      for name <- Enum.sort(names),
          scope_key <- Enum.uniq(["franchise", key]),
          do: %{
            feature: name,
            scope_key: scope_key,
            enabled: false,
            generation: 0,
            inserted_at: now,
            updated_at: now
          }

    Repo.insert_all(Gate, entries, on_conflict: :nothing, conflict_target: [:feature, :scope_key])
    lock_existing(names, key)
  end

  defp lock_existing(names, key) do
    # Lock acquisition order must not depend on the query planner's row order.
    keys = for name <- names, scope_key <- Enum.uniq(["franchise", key]), do: {name, scope_key}
    lock_keys(keys |> Enum.uniq() |> Enum.sort())
  end

  defp lock_keys(keys) do
    for(
      {name, scope_key} <- keys,
      gate =
        Repo.one(
          from g in Gate,
            where: g.feature == ^name and g.scope_key == ^scope_key,
            lock: "FOR UPDATE"
        ),
      gate != nil,
      do: gate
    )
    |> Map.new(&{{&1.feature, &1.scope_key}, &1})
  end

  defp read_gates(names, key) do
    keys = Enum.uniq(["franchise", key])

    Repo.all(from g in Gate, where: g.feature in ^names and g.scope_key in ^keys)
    |> Map.new(&{{&1.feature, &1.scope_key}, &1})
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
  def parse_scope(_), do: nil
end
