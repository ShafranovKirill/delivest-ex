defmodule DelivestWeb.Staff.FranchiseLive.Sections do
  use Gettext, backend: DelivestWeb.Gettext

  @ids ~w(brand seller logo images documents)a

  def all, do: Enum.map(@ids, &describe/1)

  def fetch(slug) do
    case Enum.find(@ids, &(Atom.to_string(&1) == slug)) do
      nil -> :error
      id -> {:ok, describe(id)}
    end
  end

  def describe(:brand),
    do:
      section(
        :brand,
        "hero-swatch",
        gettext("Brand"),
        gettext("Name, site description and brand color.")
      )

  def describe(:seller),
    do:
      section(
        :seller,
        "hero-identification",
        gettext("Seller details"),
        gettext("Shown in the site footer and inserted into the legal documents.")
      )

  def describe(:logo),
    do:
      section(
        :logo,
        "hero-photo",
        gettext("Logo"),
        gettext("Shown in the site header and menu instead of the name.")
      )

  def describe(:images),
    do:
      section(
        :images,
        "hero-device-phone-mobile",
        gettext("Icon and link preview"),
        gettext("Shown in the browser tab, on the phone home screen and when the link is shared.")
      )

  def describe(:documents),
    do:
      section(
        :documents,
        "hero-document-text",
        gettext("Legal documents"),
        gettext(
          "Default templates already contain your details. Have a lawyer check them before publishing."
        )
      )

  defp section(id, icon, title, description),
    do: %{id: id, icon: icon, title: title, description: description}
end
