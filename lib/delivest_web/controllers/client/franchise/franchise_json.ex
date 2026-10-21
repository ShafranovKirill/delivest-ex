defmodule DelivestWeb.Client.Franchise.FranchiseJSON do
  def show(%{settings: settings, documents: documents}) do
    %{
      data: %{
        name: settings.name,
        description: settings.description,
        primary_color: settings.primary_color,
        legal: legal(settings),
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
