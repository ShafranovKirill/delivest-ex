defmodule Delivest.Franchise do
  alias Delivest.Identity
  alias Delivest.Franchise.{Assets, Documents, SettingsStore, Templates}

  defdelegate get_settings, to: SettingsStore, as: :get
  defdelegate change_settings(settings, attrs \\ %{}), to: SettingsStore, as: :change
  defdelegate list_documents, to: Documents, as: :list
  defdelegate parse_document_kind(value), to: Documents, as: :parse_kind
  defdelegate placeholders, to: Templates
  defdelegate icon_url(settings, name), to: Assets
  defdelegate share_image_url(settings), to: Assets
  defdelegate logo_url(settings), to: Assets
  defdelegate logo_dark_url(settings), to: Assets

  @logo_fields %{light: :logo_key, dark: :logo_dark_key}

  def update_settings(staff, attrs), do: authorized(staff, fn -> SettingsStore.save(attrs) end)

  def update_icon(staff, binary),
    do: authorized(staff, fn -> replace_image(:icon_key, Assets.store_icon(binary)) end)

  def remove_icon(staff), do: authorized(staff, fn -> replace_image(:icon_key, {:ok, nil}) end)

  def update_share_image(staff, binary),
    do:
      authorized(staff, fn ->
        replace_image(:share_image_key, Assets.store_share_image(binary))
      end)

  def remove_share_image(staff),
    do: authorized(staff, fn -> replace_image(:share_image_key, {:ok, nil}) end)

  def update_logo(staff, variant, binary),
    do: authorized(staff, fn -> replace_image(logo_field(variant), Assets.store_logo(binary)) end)

  def remove_logo(staff, variant),
    do: authorized(staff, fn -> replace_image(logo_field(variant), {:ok, nil}) end)

  def update_document(staff, kind, body),
    do: authorized(staff, fn -> Documents.save(kind, body) end)

  def reset_document(staff, kind), do: authorized(staff, fn -> Documents.reset(kind) end)

  def get_document(kind) do
    document = Documents.get(kind)
    %{document | body: Templates.render(document.body, get_settings())}
  end

  defp replace_image(field, {:ok, value}) do
    previous = SettingsStore.current(field)

    with {:ok, settings} <- SettingsStore.save_images(%{field => value}) do
      if previous != value, do: delete_image(field, previous)
      {:ok, settings}
    end
  end

  defp replace_image(_field, error), do: error

  defp delete_image(:icon_key, dir), do: Assets.delete_icon(dir)
  defp delete_image(:share_image_key, key), do: Assets.delete_share_image(key)
  defp delete_image(_logo_field, key), do: Assets.delete_logo(key)

  defp logo_field(variant), do: Map.fetch!(@logo_fields, variant)

  defp authorized(staff, fun) do
    if Identity.can?(staff, "admin"), do: fun.(), else: {:error, :forbidden}
  end
end
