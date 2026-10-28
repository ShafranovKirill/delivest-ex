defmodule DelivestWeb.Client.Franchise.FranchiseJSON do
  alias Delivest.Franchise

  def show(%{
        settings: settings,
        documents: documents,
        address_map: address_map,
        client_auth: client_auth
      }) do
    %{
      data: %{
        name: settings.name,
        description: settings.description,
        primary_color: settings.primary_color,
        logo_url: Franchise.logo_url(settings),
        logo_dark_url: Franchise.logo_dark_url(settings),
        legal: legal(settings),
        address_map: address_map,
        client_auth: client_auth,
        documents: Enum.map(documents, &Map.take(&1, [:kind, :updated_at]))
      }
    }
  end

  def document(%{document: document}) do
    %{data: Map.take(document, [:kind, :body, :updated_at])}
  end

  defp legal(settings) do
    %{
      form: settings.legal_form,
      name: settings.legal_name,
      inn: settings.inn,
      ogrn: settings.ogrn,
      address: settings.legal_address,
      email: settings.email,
      phone: settings.phone
    }
  end
end
