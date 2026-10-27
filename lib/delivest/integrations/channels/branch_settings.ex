defmodule Delivest.Integrations.Channels.BranchSettings do
  use Ecto.Schema
  import Ecto.Changeset

  alias Delivest.Integrations.Channels.Registry

  @primary_key false
  embedded_schema do
    for module <- Registry.modules() do
      embeds_one module.key(), module.settings_schema(), on_replace: :update
    end
  end

  def changeset(settings, attrs) do
    Enum.reduce(Registry.modules(), cast(settings, attrs, []), fn module, changeset ->
      cast_embed(changeset, module.key(), with: &module.settings_schema().changeset/2)
    end)
  end
end
