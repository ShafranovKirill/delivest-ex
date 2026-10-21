defmodule Delivest.Franchise.Templates do
  alias Delivest.Franchise.{LegalDocument, Settings}

  @dir Path.join(:code.priv_dir(:delivest), "legal")
  @missing "—"

  @templates Map.new(LegalDocument.kinds(), fn kind ->
               path = Path.join(@dir, "#{kind}.md")
               @external_resource path
               {kind, File.read!(path)}
             end)

  def placeholders, do: ~w(brand legal_form legal_name inn ogrn address email phone)

  def default(kind), do: Map.fetch!(@templates, kind)

  def render(body, %Settings{} = settings) do
    Regex.replace(~r/\{\{\s*(\w+)\s*\}\}/, body, fn whole, key ->
      if key in placeholders(), do: value(settings, key), else: whole
    end)
  end

  defp value(settings, "brand"), do: present(settings.name)
  defp value(settings, "address"), do: present(settings.legal_address)
  defp value(settings, key), do: present(Map.fetch!(settings, String.to_existing_atom(key)))

  defp present(value) when value in [nil, ""], do: @missing
  defp present(value), do: value
end
