defmodule DelivestWeb.Staff.BranchLive.Sections do
  use Gettext, backend: DelivestWeb.Gettext

  @ids ~w(general location hours kitchen links ycart)a

  def all, do: Enum.map(@ids, &describe/1)

  def fetch(slug) do
    case Enum.find(@ids, &(Atom.to_string(&1) == slug)) do
      nil -> :error
      id -> {:ok, describe(id)}
    end
  end

  def describe(:general),
    do: section(:general, "hero-building-storefront", gettext("General"), nil)

  def describe(:location),
    do:
      section(
        :location,
        "hero-map-pin",
        gettext("Location"),
        gettext("The address and the point of the branch for customers and the pickup map.")
      )

  def describe(:hours), do: section(:hours, "hero-clock", gettext("Working Hours"), nil)

  def describe(:kitchen),
    do:
      section(
        :kitchen,
        "hero-fire",
        gettext("Kitchen"),
        gettext(
          "The kitchen screen shows orders being cooked. Without it, or with Frontpad, the operator marks orders ready."
        )
      )

  def describe(:links),
    do: section(:links, "hero-chat-bubble-left-right", gettext("Social Links & Messengers"), nil)

  def describe(:ycart), do: section(:ycart, "hero-map", gettext("YCart Settings"), nil)

  defp section(id, icon, title, description),
    do: %{id: id, icon: icon, title: title, description: description}
end
