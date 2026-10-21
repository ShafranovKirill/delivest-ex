defmodule Delivest.Franchise do
  alias Delivest.Identity
  alias Delivest.Franchise.{Documents, SettingsStore, Templates}

  defdelegate get_settings, to: SettingsStore, as: :get
  defdelegate change_settings(settings, attrs \\ %{}), to: SettingsStore, as: :change
  defdelegate list_documents, to: Documents, as: :list
  defdelegate parse_document_kind(value), to: Documents, as: :parse_kind
  defdelegate placeholders, to: Templates

  def update_settings(staff, attrs), do: authorized(staff, fn -> SettingsStore.save(attrs) end)

  def update_document(staff, kind, body),
    do: authorized(staff, fn -> Documents.save(kind, body) end)

  def reset_document(staff, kind), do: authorized(staff, fn -> Documents.reset(kind) end)

  def get_document(kind) do
    document = Documents.get(kind)
    %{document | body: Templates.render(document.body, get_settings())}
  end

  defp authorized(staff, fun) do
    if Identity.can?(staff, "admin"), do: fun.(), else: {:error, :forbidden}
  end
end
