defmodule Delivest.Media.Config do
  use Gettext, backend: DelivestWeb.Gettext

  @mb 1024 * 1024

  def upload_settings(_type \\ "image") do
    %{
      accept: ~w(.jpg .jpeg .png .webp),
      max_entries: 1,
      max_size: 10 * @mb,
      description: gettext("Images: JPG, PNG, WEBP (Max 10MB)")
    }
  end

  def format_extensions(type \\ "image") do
    type
    |> upload_settings()
    |> Map.get(:accept)
    |> Enum.map_join(", ", fn "." <> ext -> String.upcase(ext) end)
  end
end
