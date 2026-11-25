defmodule DelivestWeb.Staff.FranchiseLive.Sections do
  use Gettext, backend: DelivestWeb.Gettext

  @ids ~w(brand maintenance auth cutlery seller loyalty logo images documents analytics snapshot)a

  def all, do: Enum.map(@ids, &describe/1)

  def export_sections do
    [
      %{
        id: "storefront",
        title: gettext("Storefront"),
        description:
          gettext("Address, contacts, working hours, delivery settings and delivery zones.")
      },
      %{
        id: "catalog",
        title: gettext("Catalog"),
        description: gettext("Categories, products, modifiers and photos for every branch.")
      },
      %{
        id: "franchise",
        title: gettext("Franchise settings"),
        description: gettext("Brand, seller details and legal documents.")
      },
      %{
        id: "integrations",
        title: gettext("Integrations"),
        description:
          gettext("CRM, fiscal, channels, delivery and payment settings, including secret keys.")
      }
    ]
  end

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

  def describe(:auth),
    do:
      section(
        :auth,
        "hero-user-circle",
        gettext("Customer sign-in"),
        gettext("Whether customers must sign in before placing an order.")
      )

  def describe(:maintenance),
    do:
      section(
        :maintenance,
        "hero-wrench-screwdriver",
        gettext("Maintenance"),
        gettext(
          "Temporarily close every public storefront while keeping staff and existing orders available."
        )
      )

  def describe(:cutlery),
    do:
      section(
        :cutlery,
        "hero-sparkles",
        gettext("Cutlery with orders"),
        gettext("Free cutlery for orders placed on the site.")
      )

  def describe(:seller),
    do:
      section(
        :seller,
        "hero-identification",
        gettext("Seller details"),
        gettext("Shown in the site footer and inserted into the legal documents.")
      )

  def describe(:loyalty),
    do:
      section(
        :loyalty,
        "hero-star",
        gettext("Marketing Push messages"),
        gettext("Message frequency limits across all branches.")
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

  def describe(:analytics),
    do:
      section(
        :analytics,
        "hero-chart-bar",
        gettext("Network analytics"),
        gettext("Extended analytics and branch comparison across the network.")
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

  def describe(:snapshot),
    do:
      section(
        :snapshot,
        "hero-archive-box-arrow-down",
        gettext("Full instance backup"),
        gettext("Export or restore the entire database and every stored file.")
      )

  defp section(id, icon, title, description),
    do: %{id: id, icon: icon, title: title, description: description}
end
