defmodule Delivest.Features.Settings do
  @moduledoc "Administrator controls for optional features exposed in staff settings."
  alias Delivest.{Features, Identity, Repo}
  alias Delivest.Features.Registry
  alias Delivest.Identity.Staff
  alias Delivest.Integrations.StaffAccess

  def authorized?(staff), do: Identity.can?(Identity.fresh_staff(staff), "admin")
  def branch_features, do: Enum.reject(Registry.features(), &StaffAccess.permission?/1)

  def rows(staff, scope) do
    with :ok <- authorize(staff), :ok <- valid_scope(scope) do
      features = if scope == :franchise, do: Registry.features(), else: branch_features()
      {:ok, Enum.map(features, &%{feature: &1, enabled: enabled?(&1, scope)})}
    end
  end

  defp enabled?(feature, scope) do
    if StaffAccess.permission?(feature),
      do: StaffAccess.allowed_key?(feature),
      else: Features.enabled?(feature, scope)
  end

  def preview(staff, feature, scope) do
    with :ok <- authorize(staff), :ok <- allowed(feature, scope) do
      Features.disable_preview(feature, scope)
    end
  end

  def configure(staff, feature, scope, enabled, confirmation \\ nil)

  def configure(staff, feature, scope, enabled, confirmation) when is_boolean(enabled) do
    with %Staff{} = fresh <- Identity.fresh_staff(staff),
         true <- Identity.can?(fresh, "admin"),
         :ok <- allowed(feature, scope) do
      Repo.transaction(fn ->
        actor = "staff:" <> fresh.id

        if enabled and scope != :franchise do
          case Features.configure(feature, :franchise, true,
                 actor: actor,
                 activation_branch: elem(scope, 1),
                 confirm_activation: confirmation
               ) do
            {:ok, _} -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end
        end

        if enabled do
          configure!(feature, scope, true, actor, confirmation)
        else
          {:ok, preview} = Features.disable_preview(feature, scope)
          if confirmation != preview, do: Repo.rollback({:confirmation_required, preview})
          configure!(feature, scope, false, actor, preview)
        end
      end)
      |> tap(fn
        {:ok, _} ->
          Phoenix.PubSub.broadcast(Delivest.PubSub, "features:changed", :features_changed)

        _ ->
          :ok
      end)
    else
      _ -> {:error, :forbidden}
    end
  end

  def configure(_, _, _, _, _), do: {:error, :forbidden}

  defp configure!(feature, scope, enabled, actor, confirmation) do
    case Features.configure(feature, scope, enabled,
           actor: actor,
           confirm_dependents: confirmation,
           confirm_activation: confirmation
         ) do
      {:ok, result} -> result
      {:error, {:dependent_features, preview}} -> Repo.rollback({:confirmation_required, preview})
      {:error, {:activation_required, preview}} -> Repo.rollback({:activation_required, preview})
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp authorize(staff), do: if(authorized?(staff), do: :ok, else: {:error, :forbidden})

  defp allowed(feature, scope) do
    if Registry.known?(feature) and (scope == :franchise or not StaffAccess.permission?(feature)),
      do: valid_scope(scope),
      else: {:error, :forbidden}
  end

  defp valid_scope(:franchise), do: :ok

  defp valid_scope({:branch, id}) do
    with {:ok, id} <- Ecto.UUID.cast(id), {:ok, _} <- Identity.get_branch(id) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  defp valid_scope(_), do: {:error, :forbidden}
end
