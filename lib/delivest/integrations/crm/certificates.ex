defmodule Delivest.Integrations.Crm.Certificates do
  @moduledoc "Manual CRM certificate lookup and signed promotion bindings."

  alias Delivest.Identity
  alias Delivest.Integrations.Crm
  alias Delivest.Integrations.Crm.{BranchSettings, Registry, Throttle}
  alias Delivest.Integrations.StaffAccess

  @salt "crm-certificate-binding-v1"
  @token_age 600

  def verify(staff, branch_id, provider, code, permission)
      when is_binary(code) and (is_binary(provider) or is_atom(provider)) and
             permission in ["integrations.read", "promotions.create", "promotions.update"] do
    code = String.trim(code)

    with :ok <- Identity.authorize(Identity.fresh_staff(staff), permission, branch_id),
         true <- (code != "" and String.length(code) <= 20) || {:error, :invalid_code},
         {:ok, module} <- Registry.fetch(provider),
         true <-
           function_exported?(module, :get_certificate, 2) || {:error, :unsupported_provider},
         true <- StaffAccess.allowed?(module.key()) || {:error, :feature_disabled},
         %BranchSettings{} = settings <- Crm.get_branch_settings(branch_id),
         true <-
           (permission == "integrations.read" or
              BranchSettings.provider_for(settings, :app) == module.key()) ||
             {:error, :inactive_provider},
         provider_settings when not is_nil(provider_settings) <- Map.get(settings, module.key()),
         true <- module.configured?(provider_settings) || {:error, :not_configured},
         {:ok, certificate} <-
           Throttle.run(module.rate_limit(provider_settings), fn ->
             module.get_certificate(provider_settings, code)
           end) do
      snapshot =
        certificate
        |> Map.new(fn {key, value} ->
          {to_string(key), if(is_atom(value), do: to_string(value), else: value)}
        end)

      snapshot = Map.merge(snapshot, %{"provider" => to_string(module.key()), "code" => code})

      token =
        Phoenix.Token.sign(DelivestWeb.Endpoint, @salt, %{
          branch_id: branch_id,
          generation: settings.generation,
          snapshot: snapshot
        })

      {:ok, snapshot, token}
    else
      false -> {:error, :not_configured}
      error -> error
    end
  end

  def verify(_staff, _branch_id, _provider, _code, _permission),
    do: {:error, :invalid_code}

  def binding(branch_id, token) when is_binary(token) do
    with {:ok, %{branch_id: ^branch_id, generation: generation, snapshot: snapshot}} <-
           Phoenix.Token.verify(DelivestWeb.Endpoint, @salt, token, max_age: @token_age),
         %BranchSettings{generation: ^generation} = settings <- Crm.get_branch_settings(branch_id),
         true <- StaffAccess.allowed?(:frontpad),
         true <- BranchSettings.provider_for(settings, :app) == :frontpad,
         true <- Delivest.Integrations.Frontpad.configured?(settings.frontpad),
         %{"provider" => "frontpad", "code" => code, "type" => type} <- snapshot,
         true <- is_binary(code) and code != "" and type in ~w(product percent amount) do
      {:ok, snapshot}
    else
      _ -> {:error, :invalid_certificate_binding}
    end
  end

  def binding(_branch_id, _token), do: {:error, :invalid_certificate_binding}
end
